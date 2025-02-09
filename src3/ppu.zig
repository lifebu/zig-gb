const std = @import("std");
const assert = std.debug.assert;

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

pub const LcdStat = packed struct {
    mode: enum(u2) {
        h_blank,
        v_blank,
        oam_scan,
        draw,
    },
    ly_is_lyc: bool = false,
    mode_0_select: bool = false,
    mode_1_select: bool = false,
    mode_2_select: bool = false,
    lyc_select: bool = false,
    _: u1 = 0,

    pub fn fromMem(memory: *[def.addr_space]u8) LcdStat {
        return @bitCast(memory[mem_map.lcd_stat]);
    } 

    pub fn toMem(self: LcdStat, memory: *[def.addr_space]u8) void {
        memory[mem_map.lcd_stat] = @bitCast(self);
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

// TODO: Think about what data structure is best for the draw function.
const BackgroundFifo2bpp = struct {
    first_bitplane: u8,
    second_bitplane: u8,
    pallete_addr: u16,
    /// Used to incrementally shift out a pixel out of the bitplanes.
    current_shift: u3 = 0,
};
const BackgroundFifoPixel = packed struct(u5) {
    palette_id: u3 = 0,
    color_id: u2 = 0,
};
const BackgroundFifo = std.fifo.LinearFifo(BackgroundFifoPixel, .{ .Static = def.tile_width * 2 });

const ObjectFifoPixel = packed struct(u12) {
    obj_prio: u6 = 0, // CGB: OAM index, DMG: Unused
    palette_id: u3 = 0,
    color_id: u2 = 0, 
    bg_prio: u1 = 0,
};
const ObjectFiFo = std.fifo.LinearFifo(ObjectFifoPixel, .{ .Static = def.tile_width * 2 });

const MicroOp = enum {
    advance_mode_draw,
    advance_mode_hblank,
    advance_mode_oam_scan,
    advance_mode_vblank,
    clear_fifo,
    fetch_data,
    fetch_push_bg,
    fetch_tile,
    inc_lcd_y,
    nop,
    nop_draw,
    oam_check,
    push_pixel,
};
const MicroOpFifo = std.fifo.LinearFifo(MicroOp, .{ .Static = cycles_per_line });

pub const State = struct {
    background_fifo: BackgroundFifo = BackgroundFifo.init(), 
    object_fifo: ObjectFiFo = ObjectFiFo.init(),
    // TODO: Have a way to know where a MicroOp came from to debug this! (add a second byte with runtime information and advance pc by two?)
    uop_fifo: MicroOpFifo = MicroOpFifo.init(),     
    lcd_x: u8 = 0, 
    lcd_y: u8 = 0, 
    line_cycles: u9 = 0,
    fetcher_tilemap_addr: u16 = 0,
    fetcher_tile_addr: u16 = 0,
    fetcher_data: std.BoundedArray(u8, 2) = std.BoundedArray(u8, 2).init(0) catch unreachable,
    fetcher_bg_data: [def.tile_width]BackgroundFifoPixel = undefined,
    oam_scan_idx: u6 = 0,
    // TODO: What data do we store here, what is easiest for the draw function? a list of indices into OAM? A copy of the object? Pre-digested data?
    // https://www.reddit.com/r/EmuDev/comments/1bpxuwp/gameboy_ppu_mode_2_oam_scan/ => X-Pos (8-bits), Tile-Row 0-15 (4 bits), sprite-num 0-39 (6 bits)
    oam_line_list: std.BoundedArray(u6, 10) = std.BoundedArray(u6, 10).init(0) catch unreachable,

    color2bpp: [def.num_2bpp]u8 = [_]u8{ 0 } ** 40 ** 144,
};

pub fn init(state: *State) void {
    state.uop_fifo.write(&oam_scan_uops) catch unreachable;
}

const oam_scan_uops = [_]MicroOp{ .oam_check, .nop } ** (oam_size - 1) 
                   ++ [_]MicroOp{ .oam_check, .advance_mode_draw };
// TODO: Add override uOps in this buffer to enable window and objects!
// TODO: Try to dynamically generate the buffer from the parts. The 19 parts are basically the same if you allow fetch_push_bg to reinsert itself at the end.
const draw_uops = [_]MicroOp{ .fetch_tile, .nop_draw, .fetch_data, .nop_draw, .fetch_data, .fetch_push_bg, } ** 2
               ++ [_]MicroOp{ .fetch_tile, .nop_draw, .fetch_data, .nop_draw, .fetch_data, .fetch_push_bg, .fetch_push_bg, .fetch_push_bg } ** 19
               ++ [_]MicroOp{ .fetch_tile, .nop_draw, .fetch_data, .nop_draw, .fetch_data, .fetch_push_bg, .fetch_push_bg, .advance_mode_hblank };

// Note: Maximum length for hblank. Penalties make this shorter.
const hblank_uops = [_]MicroOp{ .nop } ** 203;
const vblank_uops = [_]MicroOp{ .nop } ** 455;

pub fn cycle(state: *State, memory: *[def.addr_space]u8) void {
    var lcd_stat = LcdStat.fromMem(memory);
    const lcd_control = LcdControl.fromMem(memory);

    const uop: MicroOp = state.uop_fifo.readItem().?;
    switch(uop) {
        .advance_mode_draw => {
            lcd_stat.mode = .draw;
            state.uop_fifo.write(&draw_uops) catch unreachable;
            state.background_fifo.discard(state.background_fifo.readableLength());
            state.object_fifo.discard(state.object_fifo.readableLength());
            const tile_map_base_addr: u16 = if(lcd_control.bg_map_area == .first_map) mem_map.first_tile_map_address else mem_map.second_tile_map_address;
            state.fetcher_tilemap_addr = tile_map_base_addr + tile_map_size_x * @as(u16, state.lcd_y / tile_size_y);
            assert(state.fetcher_tilemap_addr >= tile_map_base_addr and state.fetcher_tilemap_addr <= tile_map_base_addr + tile_map_size_byte);
            state.lcd_x = 0;
        },
        .advance_mode_hblank => {
            lcd_stat.mode = .h_blank;
            const hblank_len = 455 - state.line_cycles - 1;
            state.uop_fifo.write(hblank_uops[0..hblank_len]) catch unreachable;
            state.lcd_y += 1;
            state.line_cycles = 0;
            const advance: MicroOp = if(state.lcd_y >= 144) .advance_mode_vblank else .advance_mode_oam_scan;
            state.uop_fifo.writeItem(advance) catch unreachable;
        },
        .advance_mode_oam_scan => {
            lcd_stat.mode = .oam_scan;
            state.uop_fifo.write(&oam_scan_uops) catch unreachable;
            state.oam_line_list.resize(0) catch unreachable;
            state.oam_scan_idx = 0;
        },
        .advance_mode_vblank => {
            lcd_stat.mode = .v_blank;
            state.uop_fifo.write(&vblank_uops) catch unreachable;
            state.lcd_y = (state.lcd_y + 1) % 154;
            const advance: MicroOp = if(state.lcd_y == 0) .advance_mode_oam_scan else .advance_mode_vblank;
            state.uop_fifo.writeItem(advance) catch unreachable;
        },
        .fetch_data => {
            state.fetcher_data.append(memory[state.fetcher_tile_addr]) catch unreachable;
            state.fetcher_tile_addr += 1;
            tryPushPixel(state, memory);
        },
        .fetch_push_bg => {
            // TODO: this is no longer in 2bp, which I assumed would be best to be pushed to the shader. A better way to do this?
            // TODO: Maybe we split the data in the fetcher_bg_data into 2bpp color and palette_data? 
            // TODO: struct of arrays? 
            // TODO: Can I remove this conditional here?
            if(state.fetcher_data.len > 0) {
                const second_bitplane: u8 = state.fetcher_data.pop();
                const first_bitplane: u8 = state.fetcher_data.pop();
                // TODO: write this into background_fifo
                const data = BackgroundFifo2bpp{ .first_bitplane = first_bitplane, .second_bitplane = second_bitplane, .pallete_addr = mem_map.bg_palette, .current_shift = 0, };
                if(data.pallete_addr == 0) {}
                for(0..state.fetcher_bg_data.len) |bit_idx| {
                    const bit_offset: u3 = 7 - @as(u3, @intCast(bit_idx));
                    const one: u8 = 1;
                    const mask: u8 = one << bit_offset;
                    const first_bit: u8 = (first_bitplane & mask) >> bit_offset;
                    const second_bit: u8 = (second_bitplane & mask) >> bit_offset;
                    const color_id: u2 = @intCast(first_bit + (second_bit << 1)); // LSB first
                    const palette_id: u3 = 0; // Only for objects
                    state.fetcher_bg_data[bit_idx] = .{ .color_id = color_id, .palette_id = palette_id };
                }
            }
            // TODO: pushing data failed? => write a fetch_push_bg into uops fifo!
            state.background_fifo.write(&state.fetcher_bg_data) catch {};
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

    state.line_cycles += 1;
    lcd_stat.toMem(memory);
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
    if(state.background_fifo.readableLength() <= def.tile_width) {
        return;
    }

    const pixel: BackgroundFifoPixel = state.background_fifo.readItem().?;
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
