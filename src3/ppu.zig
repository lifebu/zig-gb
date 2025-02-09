const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

const tile_size_x = 8;
const tile_size_y = 8;
const tile_size_byte = 16;

const tile_map_size_x = 32;
const tile_map_size_y = 32;
const tile_map_size_byte = tile_map_size_x * tile_map_size_y;

const oam_size = 40;
const obj_size_byte = 4;
const obj_per_line = 10;

const cycles_per_line = 456;

// TODO: Maybe move general ppu constructs into it's own source file?
const Mode = enum(u2) {
    h_blank,
    v_blank,
    oam_scan,
    draw,
};

const LcdControl = packed struct {
    bg_window_enable: bool = false,
    obj_enable: bool = false,
    obj_size: enum(u1) {
        single_height,
        double_height,
    } = .single_height,
    bg_map_area: enum(u1) {
        first_map,
        second_map,
    } = .first_map,
    bg_window_tile_data: enum(u1) {
        second_tile_data,
        first_tile_data,
    } = .second_tile_data,
    window_enable: bool = false,
    window_map_area: enum(u1) {
        first_map,
        second_map,
    } = .first_map,
    lcd_enable: bool = false,

    pub fn fromMem(memory: *[def.addr_space]u8) LcdControl {
        return @bitCast(memory[mem_map.lcd_control]);
    } 
};

const Object = packed struct {
    y_position: u8,
    x_position: u8,
    tile_index: u8,
    flags: packed struct {
        cgb_palette: u3,
        vram_bank: u1,
        dmg_palette: enum(u1) {
            obp0,
            obp1,
        },
        x_flip: bool,
        y_flip: bool,
        priority: enum(u1) {
            obj_over_bg,
            obj_under_bg,
        },
    },

    pub fn fromOAM(memory: *[def.addr_space]u8, obj_idx: u6) *align(1) const Object {
        const address: u16 = mem_map.oam_low + (@as(u16, obj_idx) * obj_size_byte);
        return @ptrCast(&memory[address]);
    }

    pub fn print(self: Object, obj_idx: u6) void {
        std.debug.print("Object ({any}): ({any}, {any}): tile: {any}, prio: {s}, y_flip: {any}, x_flip: {any}, dmg_palette: {s}, vram_bank: {any}, cgb_palette: {any}\n", .{ 
            obj_idx, self.x_position, self.y_position, self.tile_index, 
            std.enums.tagName(@TypeOf(self.flags.priority), self.flags.priority).?, 
            self.flags.y_flip, self.flags.x_flip, 
            std.enums.tagName(@TypeOf(self.flags.dmg_palette), self.flags.dmg_palette).?, self.flags.vram_bank, self.flags.cgb_palette 
        });
    }
};

const BackgroundFifoPixel = packed struct(u5) {
    palette_id: u3 = 0,
    color_id: u2 = 0,
};

const ObjectFifoPixel = packed struct(u12) {
    obj_prio: u6 = 0, // CGB: OAM index, DMG: Unused
    palette_id: u3 = 0,
    color_id: u2 = 0, 
    bg_prio: u1 = 0,
};

// TODO: uOps Buffer could also use this, so we can move it into it's own file and generalize it? 
/// Static size version of std.RingBuffer
pub fn Fifo(comptime T: type, comptime capacity: usize) type {
   return struct {
        const Self = @This();

        pub const Error = error{ Full };

        data: [capacity]T = undefined,
        write_idx: usize = 0,
        read_idx: usize = 0,

        fn mask(index: usize) usize {
            return index % capacity;
        }
        fn mask2(index: usize) usize {
            return index % (2 * capacity);
        }

        pub fn pop(self: *Self) Error!T {
            const is_empty: bool = self.write_idx == self.read_idx;
            if(is_empty) {
                return Error.Full;
            }

            const value = self.data[mask(self.read_idx)];
            self.read_idx = mask2(self.read_idx + 1);
            return value;
        }

        pub fn push(self: *Self, value: T) Error!void {
            const is_full: bool = mask2(self.write_idx + self.data.len) == self.read_idx;
            if(is_full) {
                return error.Full;
            }

            self.data[mask(self.write_idx)] = value;
            self.write_idx = mask2(self.write_idx + 1);
        } 

        pub fn pushSlice(self: *Self, values: []const T) Error!void {
            if (self.len() + values.len > self.data.len) {
                return error.Full;
            }

            for (0..values.len) |i| {
                self.push(values[i]) catch unreachable;
            }
        }

        pub fn len(self: Self) usize {
            const wrap_offset = 2 * self.data.len * @intFromBool(self.write_idx < self.read_idx);
            const adjusted_write_idx = self.write_idx + wrap_offset;
            return adjusted_write_idx - self.read_idx;
        }

        pub fn clear(self: *Self) void {
            self.read_idx = 0; 
            self.write_idx = 0;
        }
    };
}

const MicroOp = enum {
    advance_mode_draw,
    advance_mode_hblank,
    advance_mode_oam_scan,
    advance_mode_vblank,
    clear_fifo,
    fetch_data_high,
    fetch_data_low,
    fetch_push_bg,
    fetch_tile,
    inc_lcd_y,
    nop,
    nop_draw,
    oam_check,
    push_pixel,
};

pub const State = struct {
    background_fifo: Fifo(BackgroundFifoPixel, def.tile_width * 2) = .{}, 
    object_fifo: Fifo(ObjectFifoPixel, def.tile_width * 2) = .{},
    // TODO: std.BoundedArray? Because we sometimes only want to use part of the buffer and loop!
    // TODO: std.BoundedArray allows to pop one element from the back. 
    // TODO: But it would be convenient if we had a BoundedArray as a FIFO (new use case for the pixel fifo type? only requires tryPushSlice() instead of tryPush8().
    // TODO: Have a way to know where a MicroOp came from to debug this! (add a second byte with runtime information and advance pc by two?)
    uop_buf: [cycles_per_line]MicroOp = [1]MicroOp{ .nop } ** cycles_per_line,
    uop_pc: u16 = 0,
    lcd_x: u8 = 0, 
    lcd_y: u8 = 0, 
    fetcher_tilemap_addr: u16 = 0,
    fetcher_tile_addr: u16 = 0,
    fetcher_data_low: u8 = 0,
    fetcher_data_high: u8 = 0,
    fetcher_bg_data: [def.tile_width]BackgroundFifoPixel = undefined,
    // TODO: This can exist implicitly in the gb memory later.
    mode: Mode = .oam_scan,
    oam_scan_idx: u6 = 0,
    // TODO: can also be filled partially, do we use a zig's BoundedArray? write_idx? invalid_oam_index?
    // TODO: What data do we store here, what is easiest for the draw function? a list of indices into OAM? A copy of the object? Pre-digested data?
    // https://www.reddit.com/r/EmuDev/comments/1bpxuwp/gameboy_ppu_mode_2_oam_scan/ => X-Pos (8-bits), Tile-Row 0-15 (4 bits), sprite-num 0-39 (6 bits)
    oam_line_list: std.BoundedArray(u6, 10) = std.BoundedArray(u6, 10).init(0) catch unreachable,

    color2bpp: [def.num_2bpp]u8 = [_]u8{ 0 } ** 40 ** 144,
};

pub fn init(state: *State) void {
    std.mem.copyForwards(MicroOp, state.uop_buf[0..oam_scan_uops.len], &oam_scan_uops);
}

const oam_scan_uops = [_]MicroOp{ .oam_check, .nop } ** (oam_size - 1) 
                   ++ [_]MicroOp{ .oam_check, .advance_mode_draw };
// TODO: Add override uOps in this buffer to enable window and objects!
// TODO: Try to dynamically generate the buffer from the parts. The 19 parts are basically the same if you allow fetch_push_bg to reinsert itself at the end.
const draw_uops = [_]MicroOp{ .fetch_tile, .nop_draw, .fetch_data_low, .nop_draw, .fetch_data_high, .fetch_push_bg, } ** 2
               ++ [_]MicroOp{ .fetch_tile, .nop_draw, .fetch_data_low, .nop_draw, .fetch_data_high, .fetch_push_bg, .fetch_push_bg, .fetch_push_bg } ** 19
               ++ [_]MicroOp{ .fetch_tile, .nop_draw, .fetch_data_low, .nop_draw, .fetch_data_high, .fetch_push_bg, .fetch_push_bg, .advance_mode_hblank };

// TODO: The length of this is dynamic!
const hblank_uops = [_]MicroOp{ .nop } ** 203;
const vblank_uops = [_]MicroOp{ .nop } ** 455;

pub fn cycle(state: *State, memory: *[def.addr_space]u8) void {
    const lcd_control = LcdControl.fromMem(memory);
    const uop: MicroOp = state.uop_buf[state.uop_pc];
    state.uop_pc += 1;
    switch(uop) {
        .advance_mode_draw => {
            state.mode = .draw;
            std.debug.assert(draw_uops.len == 172);
            std.mem.copyForwards(MicroOp, state.uop_buf[0..draw_uops.len], &draw_uops);
            state.background_fifo.clear();
            state.object_fifo.clear();
            const tile_map_base_addr: u16 = if(lcd_control.bg_map_area == .first_map) mem_map.first_tile_map_address else mem_map.second_tile_map_address;
            state.fetcher_tilemap_addr = tile_map_base_addr + tile_map_size_x * @as(u16, state.lcd_y / tile_size_y);
            std.debug.assert(state.fetcher_tilemap_addr >= tile_map_base_addr and state.fetcher_tilemap_addr <= tile_map_base_addr + tile_map_size_byte);
            state.uop_pc = 0;
            state.lcd_x = 0;
        },
        .advance_mode_hblank => {
            state.lcd_y += 1;
            state.mode = .h_blank;
            std.debug.assert(hblank_uops.len == 203);
            // TODO: This copying is very unsafe and can easily lead to issues. A fifo-style feels better!
            std.mem.copyForwards(MicroOp, state.uop_buf[0..hblank_uops.len], &hblank_uops);
            state.uop_buf[hblank_uops.len] = if(state.lcd_y >= 144) .advance_mode_vblank else .advance_mode_oam_scan;
            state.uop_pc = 0;
        },
        .advance_mode_oam_scan => {
            state.mode = .oam_scan;
            // TODO: This copying is very unsafe and can easily lead to issues. A fifo-style feels better!
            std.mem.copyForwards(MicroOp, state.uop_buf[0..oam_scan_uops.len], &oam_scan_uops);
            state.uop_pc = 0;
            state.oam_line_list.resize(0) catch unreachable;
            state.oam_scan_idx = 0;
            state.uop_pc = 0;
        },
        .advance_mode_vblank => {
            state.lcd_y += 1;
            state.mode = .v_blank;
            // TODO: This copying is very unsafe and can easily lead to issues. A fifo-style feels better!
            std.debug.assert(vblank_uops.len == 455);
            std.mem.copyForwards(MicroOp, state.uop_buf[0..vblank_uops.len], &vblank_uops);
            // TODO: Really not nice!
            if(state.lcd_y >= 153) {
                state.uop_buf[vblank_uops.len] = .advance_mode_oam_scan;
                state.lcd_y = 0;
            } else {
                state.uop_buf[vblank_uops.len] = .advance_mode_vblank;
            }
            state.uop_pc = 0;
        },
        // TODO: Try to combine fetch_data_high and fetch_data_low 
        .fetch_data_high => {
            state.fetcher_data_high = memory[state.fetcher_tile_addr];
            state.fetcher_tile_addr += 1;
            tryPushPixel(state, memory);
        },
        .fetch_data_low => {
            state.fetcher_data_low = memory[state.fetcher_tile_addr];
            state.fetcher_tile_addr += 1;
            tryPushPixel(state, memory);
        },
        .fetch_push_bg => {
            // TODO: this is no longer in 2bp, which I assumed would be best to be pushed to the shader. A better way to do this?
            // TODO: Maybe we split the data in the fetcher_bg_data into 2bpp color and palette_data? 
            for(0..state.fetcher_bg_data.len) |bit_idx| {
                const bit_offset: u3 = 7 - @as(u3, @intCast(bit_idx));
                const one: u8 = 1;
                const mask: u8 = one << bit_offset;
                const first_bit: u8 = (state.fetcher_data_low & mask) >> bit_offset;
                const second_bit: u8 = (state.fetcher_data_high & mask) >> bit_offset;
                const color_id: u2 = @intCast(first_bit + (second_bit << 1)); // LSB first
                const palette_id: u3 = 0; // Only for objects
                state.fetcher_bg_data[bit_idx] = .{ .color_id = color_id, .palette_id = palette_id };
            }
            // TODO: If we fail to push we need to try again (dynamic!).
            state.background_fifo.pushSlice(&state.fetcher_bg_data) catch {};
            tryPushPixel(state, memory);
        },
        .fetch_tile => {
            const bg_window_tile_base_addr: u16 = if(lcd_control.bg_window_tile_data == .second_tile_data) mem_map.second_tile_address else mem_map.first_tile_address;
            const signed_mode: bool = bg_window_tile_base_addr == mem_map.second_tile_address;
            const tile_value: u16 = memory[state.fetcher_tilemap_addr];
            const tile_addr_offset: u16 = if(signed_mode) (tile_value + 128) % 256 else tile_value;

            const tile_base_addr: u16 = bg_window_tile_base_addr + tile_addr_offset * tile_size_byte;
            state.fetcher_tile_addr = tile_base_addr + ((state.lcd_y % tile_size_y) * def.byte_per_line);
            state.fetcher_tilemap_addr += 1;
            tryPushPixel(state, memory);
        },
        .nop => {},
        .nop_draw => {
            tryPushPixel(state, memory);
        },
        .oam_check => {
            const object = Object.fromOAM(memory, state.oam_scan_idx);
            const object_height: u8 = if(lcd_control.obj_size == .double_height) tile_size_y * 2 else tile_size_y;
            if(state.lcd_y + 16 >= object.y_position and state.lcd_y + 16 < object.y_position + object_height) {
                // starting from the 11th object, this will throw an error. Fine, we only need the first 10.
                state.oam_line_list.append(state.oam_scan_idx) catch {};
            }
            state.oam_scan_idx += 1;
        },
        else => { 
            std.debug.print("PPU_MICRO_OP_NOT_IMPLEMENTED: {any}\n", .{uop});
            unreachable; 
        },
    }
}

// TODO: Can we have an easier way of reinterpreting the u8 as an array of u2?
// TODO: Find out why color_id0 is LSB?
fn getPalette(paletteByte: u8) [4]u2 {
    // https://gbdev.io/pandocs/Palettes.html
    const color_id3: u2 = @intCast((paletteByte & (3 << 6)) >> 6);
    const color_id2: u2 = @intCast((paletteByte & (3 << 4)) >> 4);
    const color_id1: u2 = @intCast((paletteByte & (3 << 2)) >> 2);
    const color_id0: u2 = @intCast((paletteByte & (3 << 0)) >> 0);
    return [4]u2{ color_id0, color_id1, color_id2, color_id3 };
}

// TODO: unpacking 2bpp earlier to pack it here again is very bad!
fn tryPushPixel(state: *State, memory: *[def.addr_space]u8) void {
    // pixel mixing requires at least 8 pixels.
    if(state.background_fifo.len() <= def.tile_width) {
        return;
    }

    const pixel: BackgroundFifoPixel = state.background_fifo.pop() catch unreachable;
    const bg_palette = getPalette(memory[mem_map.bg_palette]);
    const color_id = bg_palette[pixel.color_id];
    const first_color_bit: u8 = color_id & 0b01;
    const second_color_bit: u8 = (color_id & 0b10) >> 1;

    const tile_pixel_x = state.lcd_x % 8;
    // TODO: This breaks when we introduce scrolling!
    const shift: u3 = @intCast(tile_size_x - tile_pixel_x - 1);

    const bitplane_idx: u13 = (@as(u13, state.lcd_x) / def.tile_width) * 2 + (@as(u13, state.lcd_y) * def.resolution_2bpp_width);

    var first_bitplane = state.color2bpp[bitplane_idx];
    var second_bitplane = state.color2bpp[bitplane_idx + 1];
    first_bitplane |= first_color_bit << shift;
    second_bitplane |= second_color_bit << shift;

    state.color2bpp[bitplane_idx] = first_bitplane;
    state.color2bpp[bitplane_idx + 1] = second_bitplane;

    state.lcd_x += 1;
}
