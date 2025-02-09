const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");


const tile_size_x = 8;
const tile_size_y = 8;
const tile_size_byte = 16;

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

    pub fn fromMem(memory: [def.addr_space]u8) LcdControl {
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
            OBP0,
            OBP1,
        },
        x_flip: bool,
        y_flip: bool,
        priority: enum(u1) {
            OBJ_OVER_BG,
            OBJ_UNDER_BG,
        },
    },

    pub fn fromOAM(memory: [def.addr_space]u8, obj_idx: u6) *align(1) const Object {
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
    palleteID: u3 = 0,
    colorID: u2 = 0,
};

const ObjectFifoPixel = packed struct(u12) {
    obj_prio: u6 = 0, // CGB: OAM index, DMG: Unused
    palleteID: u3 = 0,
    colorID: u2 = 0, 
    bg_prio: u1 = 0,
};

// TODO: uOps Buffer could also use this, so we can move it into it's own file and generalize it? 
pub fn PixelFifo(comptime T: type) type {
   return struct {
        const Self = @This();

        const fifo_length = def.tile_width * 2;
        pixels: [fifo_length]T = undefined,
        write_idx: usize = 0,
        read_idx: usize = 0,

        pub fn pop(self: *Self) T {
            std.debug.assert(self.read_idx != self.write_idx);

            const value = self.pixels[self.read_idx];
            self.read_idx = (self.read_idx + 1) % fifo_length;
            return value;
        }

        /// returns true if succeeded.
        pub fn tryPush8(self: *Self, pixels: [def.tile_width]T) bool {
            const offset = fifo_length * @as(usize, @intFromBool(self.write_idx < self.read_idx));
            const length = self.write_idx + offset - self.read_idx;
            if(length + pixels.len > fifo_length) {
                return false;
            }

            inline for(0..pixels.len) |i| {
                self.pixels[self.write_idx] = pixels[i];
                self.write_idx = (self.write_idx + 1) % fifo_length;
            }
            return true;
        }

        pub fn clear(self: *Self) void {
            self.read_idx = self.write_idx;
        }
    };
}

const MicroOp = enum {
    advance_mode_draw,
    advance_mode_hblank,
    advance_mode_oam_scan,
    advance_mode_vblank,
    clear_fifo,
    fetch_construct,
    fetch_data_high,
    fetch_data_low,
    fetch_push,
    fetch_tile,
    inc_lcd_y,
    nop,
    nop_draw,
    oam_check,
    push_pixel,
};

pub const State = struct {
    background_fifo: PixelFifo(BackgroundFifoPixel) = .{}, 
    object_fifo: PixelFifo(ObjectFifoPixel) = .{},
    // TODO: std.BoundedArray? Because we sometimes only want to use part of the buffer and loop!
    // TODO: std.BoundedArray allows to pop one element from the back. 
    // TODO: But it would be convenient if we had a BoundedArray as a FIFO (new use case for the pixel fifo type? only requires tryPushSlice() instead of tryPush8().
    // TODO: Have a way to know where a MicroOp came from to debug this! (add a second byte with runtime information and advance pc by two?)
    uop_buf: [cycles_per_line]MicroOp = [1]MicroOp{ .nop } ** cycles_per_line,
    uop_pc: u16 = 0,
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

    color2bpp: [def.num_2bpp]u8 = [40]u8{  
        0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 16, 16, 17, 17, 18, 18, 19, 19, 
    } ** 144,
};

pub fn init(state: *State) void {
    // TODO: Some initialization function when we change state!
    state.oam_line_list.resize(0) catch unreachable;
    state.oam_scan_idx = 0;
    state.uop_pc = 0;
    state.mode = .oam_scan;
    state.lcd_y = 0;
    std.mem.copyForwards(MicroOp, state.uop_buf[0..oam_scan_uops.len], &oam_scan_uops);
}

const oam_scan_uops = [_]MicroOp{ .oam_check, .nop } ** (oam_size - 1) 
                      ++ [_]MicroOp{ .oam_check, .advance_mode_draw };
// TODO: Add override uOps in this buffer to enable window and objects!
// TODO: Check again if this buffer actualy makes sense. The fetch_push is tried multiple times until the push succeeds. 
const draw_uops = [_]MicroOp{ .fetch_tile, .nop_draw, .fetch_data_low, .nop_draw, .fetch_data_high, .fetch_construct, .nop_draw, .nop_draw, .fetch_push } ** 19 
               ++ [_]MicroOp{ .advance_mode_hblank };

pub fn cycle(state: *State, memory: [def.addr_space]u8) void {
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
            state.fetcher_tilemap_addr = if(lcd_control.bg_map_area == .first_map) mem_map.first_tile_map_address else mem_map.second_tile_map_address;
            state.uop_pc = 0;
        },
        .fetch_construct => {
            // TODO: this is no longer in 2bp, which I assumed would be best to be pushed to the shader. A better way to do this?
            // TODO: Maybe we split the data in the fetcher_bg_data into 2bpp color and palette_data? 
            for(0..state.fetcher_bg_data.len) |bit_idx| {
                const bit_offset: u3 = 7 - @as(u3, @intCast(bit_idx));
                const one: u8 = 1;
                const mask: u8 = one << bit_offset;
                const firstBit: u8 = (state.fetcher_data_low & mask) >> bit_offset;
                const secondBit: u8 = (state.fetcher_data_high & mask) >> bit_offset;
                const colorID: u2 = @intCast(firstBit + (secondBit << 1)); // LSB first
                const palleteID: u3 = 0; // Only for objects
                state.fetcher_bg_data[bit_idx] = .{ .colorID = colorID, .palleteID = palleteID };
            }
            tryPushPixel();
        },
        // TODO: Try to combine fetch_data_high and fetch_data_low 
        .fetch_data_high => {
            state.fetcher_data_high = memory[state.fetcher_tile_addr];
            state.fetcher_tile_addr += 1;
            tryPushPixel();
        },
        .fetch_data_low => {
            state.fetcher_data_low = memory[state.fetcher_tile_addr];
            state.fetcher_tile_addr += 1;
            tryPushPixel();
        },
        .fetch_push => {
            const succeeded: bool = state.background_fifo.tryPush8(state.fetcher_bg_data);
            if(!succeeded) unreachable;
            // TODO: If we fail to push we need to try again.
            tryPushPixel();
        },
        .fetch_tile => {
            const bgWindowTileBaseAddress: u16 = if(lcd_control.bg_window_tile_data == .second_tile_data) mem_map.second_tile_address else mem_map.first_tile_address;
            const signedAdressing: bool = bgWindowTileBaseAddress == mem_map.second_tile_address;
            var tileAddressOffset: u16 = memory[state.fetcher_tilemap_addr];
            // TODO: This feels like something that can be done better.
            if(signedAdressing) {
                if(tileAddressOffset < 128) {
                    tileAddressOffset += 128;
                } else {
                    tileAddressOffset -= 128;
                }
            }

            state.fetcher_tile_addr = bgWindowTileBaseAddress + tileAddressOffset * tile_size_byte;
            state.fetcher_tilemap_addr += 1;
            tryPushPixel();
        },
        .nop => {},
        .nop_draw => {
            tryPushPixel();
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

fn tryPushPixel() void {
    // TODO: Use both pixel fifos to try to push a pixel to the screen.
}
