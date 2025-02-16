const std = @import("std");
const assert = std.debug.assert;

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

// TODO: Think about the order of declarations I want to have in this file, what does zig standard do?
// constants, declaration, function?
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

const BackgroundFifo2bpp = struct {
    first_bitplane: u8,
    second_bitplane: u8,
    pallete_addr: u16,
    used_pixels: u4,
};
const BackgroundFifo = std.fifo.LinearFifo(BackgroundFifo2bpp, .{ .Static = 2 });

const ObjectFifo2bpp = struct {
    first_bitplane: u8, 
    second_bitplane: u8, 
    pallete_addr: u16,
    used_pixels: u4,

    obj_prio: u6, // CGB: OAM index, DMG: Unused
    // TODO: use the enum from the object or u1?
    bg_prio: u1,
};
const ObjectFiFo = std.fifo.LinearFifo(ObjectFifo2bpp, .{ .Static = 2 });

const ObjectLineEntry = struct {
    // TODO: actuall u8, but we can have negative screen_pos for partially visible objects because they also count to the object limit!
    screen_pos_x: i9, // to compose uOps.
    tile_row: u4, // single_height: [0, 7], double_height: [0, 15]
    tile_index: u8,
    palette_addr: u16,
    obj_prio: u6, // CGB: OAM index, DMG: Unused
    // TODO: use the enum from the object or u1?
    bg_prio: u1,
};
const ObjectLineList = std.BoundedArray(ObjectLineEntry, 10);

const MicroOp = enum {
    advance_mode_draw,
    advance_mode_hblank,
    advance_mode_oam_scan,
    advance_mode_vblank,
    clear_fifo,
    fetch_data_low,
    fetch_data_high,
    fetch_push_bg,
    fetch_push_obj,
    fetch_tile_bg,
    fetch_tile_obj,
    fetch_tile_window,
    inc_lcd_y,
    nop,
    nop_draw,
    oam_check,
    push_pixel,
};
const MicroOpFifo = std.fifo.LinearFifo(MicroOp, .{ .Static = cycles_per_line });

const oam_scan_uops = [_]MicroOp{ .oam_check, .nop } ** (oam_size - 1) 
                   ++ [_]MicroOp{ .oam_check, .advance_mode_draw };
const draw_bg_tile_uops = [_]MicroOp{ .fetch_tile_bg, .nop_draw, .fetch_data_low, .nop_draw, .fetch_data_high, .fetch_push_bg, };
// TODO: Be careful of the timing. The first time this runs is when we have 8 pixels left in the fifo, otherwise the 6 cycle penalty makes no sense!
const draw_window_tile_uops = [_]MicroOp{ .fetch_tile_window, .nop_draw, .fetch_data_low, .nop_draw, .fetch_data_high, .fetch_push_bg, };
const hblank_uops = [_]MicroOp{ .nop } ** 203;
const vblank_uops = [_]MicroOp{ .nop } ** 455;

/// Generates all uops needed for the draw mode and hblank mode of the current line.
fn genMicroCodeDrawAndHBlank(state: *State, line_initial_shift: u3) void {
    // TODO: Add support for objects and window!
    // TODO: I need to rethink how to generate this code better in a dynamic way.
    // draw
    for(0..2) |_| {
        state.uop_fifo.write(&draw_bg_tile_uops) catch unreachable;
    }
    for(0..19) |_| {
        state.uop_fifo.write(&draw_bg_tile_uops) catch unreachable;
        state.uop_fifo.write(&[_]MicroOp{ .fetch_push_bg, .fetch_push_bg }) catch unreachable;
    }
    state.uop_fifo.write(&draw_bg_tile_uops) catch unreachable;
    state.uop_fifo.write(&[_]MicroOp{ .fetch_push_bg }) catch unreachable;
    // TODO: pretty hacky!
    const initial_shift_uops = [_]MicroOp{ .fetch_push_bg } ++ draw_bg_tile_uops ++ [_]MicroOp{ .fetch_push_bg, .fetch_push_bg };
    for(0..line_initial_shift) |i| {
        state.uop_fifo.writeItem(initial_shift_uops[i]) catch unreachable;
    }
    state.uop_fifo.write(&[_]MicroOp{ .advance_mode_hblank }) catch unreachable;

    // hblank
    const hblank_len = 455 - 80 - state.uop_fifo.readableLength();
    state.uop_fifo.write(hblank_uops[0..hblank_len]) catch unreachable;
    const advance: MicroOp = if(state.lcd_y >= 143) .advance_mode_vblank else .advance_mode_oam_scan;
    state.uop_fifo.writeItem(advance) catch unreachable;
}

pub const State = struct {
    background_fifo: BackgroundFifo = BackgroundFifo.init(), 
    fifo_pixel_count: u8 = 0,
    fifo_is_suspended: bool = false,
    object_fifo: ObjectFiFo = ObjectFiFo.init(),
    uop_fifo: MicroOpFifo = MicroOpFifo.init(),     
    lcd_x: u8 = 0, 
    lcd_y: u8 = 0, 
    line_cycles: u9 = 0,
    line_initial_shift: u3 = 0,
    fetcher_tile_addr: u16 = 0,
    fetcher_data: ObjectFifo2bpp = undefined,
    oam_scan_idx: u6 = 0,
    oam_line_list: ObjectLineList = ObjectLineList.init(0) catch unreachable,

    color2bpp: [def.num_2bpp]u8 = [_]u8{ 0 } ** 40 ** 144,
};

pub fn init(state: *State) void {
    state.uop_fifo.write(&oam_scan_uops) catch unreachable;
}

pub fn cycle(state: *State, memory: *[def.addr_space]u8) void {
    var lcd_stat = LcdStat.fromMem(memory);
    const lcd_control = LcdControl.fromMem(memory);

    const uop: MicroOp = state.uop_fifo.readItem().?;
    switch(uop) {
        .advance_mode_draw => {
            lcd_stat.mode = .draw;
            const scroll_x: u8 = memory[mem_map.scroll_x];
            state.line_initial_shift = @intCast(scroll_x % 8);
            genMicroCodeDrawAndHBlank(state, state.line_initial_shift);
            state.background_fifo.discard(state.background_fifo.readableLength());
            state.object_fifo.discard(state.object_fifo.readableLength());
            state.fifo_pixel_count = 0;
            state.lcd_x = 0;
        },
        .advance_mode_hblank => {
            assert(state.lcd_x == 160); // Must reach the end of the screen before entering hblank
            lcd_stat.mode = .h_blank;
            state.lcd_y += 1;
        },
        .advance_mode_oam_scan => {
            lcd_stat.mode = .oam_scan;
            state.uop_fifo.write(&oam_scan_uops) catch unreachable;
            state.oam_line_list.resize(0) catch unreachable;
            state.oam_scan_idx = 0;
            state.line_cycles = 0;
        },
        .advance_mode_vblank => {
            lcd_stat.mode = .v_blank;
            state.line_cycles = 0;
            state.uop_fifo.write(&vblank_uops) catch unreachable;
            state.lcd_y = (state.lcd_y + 1) % 154;
            const advance: MicroOp = if(state.lcd_y == 0) .advance_mode_oam_scan else .advance_mode_vblank;
            state.uop_fifo.writeItem(advance) catch unreachable;
        },
        .fetch_data_low => {
            state.fetcher_data.first_bitplane = memory[state.fetcher_tile_addr];
            state.fetcher_tile_addr += 1;
            tryPushPixel(state, memory);
        },
        .fetch_data_high => {
            state.fetcher_data.second_bitplane = memory[state.fetcher_tile_addr];
            state.fetcher_data.used_pixels = 0;
            tryPushPixel(state, memory);
        },
        .fetch_push_bg => {
            const length_before: u8 = @intCast(state.background_fifo.readableLength());
            state.background_fifo.writeItem(.{ // We use an ObjectFifo2bpp Type which is a super-set of BackgroundFifo2bpp.
                .first_bitplane = state.fetcher_data.first_bitplane,
                .second_bitplane = state.fetcher_data.second_bitplane,
                .pallete_addr = state.fetcher_data.pallete_addr, 
                .used_pixels = state.fetcher_data.used_pixels,
            }) catch {};
            const length_after: u8 = @intCast(state.background_fifo.readableLength());
            state.fifo_pixel_count += (length_after - length_before) * tile_size_x; 
            tryPushPixel(state, memory);
        },
        .fetch_push_obj => {
            // TODO: Mix with existing object data if we have one. This will crash if we already have 2 object data.
            state.object_fifo.writeItem(state.fetcher_data) catch {};
            state.fifo_is_suspended = false;
            tryPushPixel(state, memory);
        },
        .fetch_tile_bg => {
            const tilemap_base_addr: u16 = if(lcd_control.bg_map_area == .first_map) mem_map.first_tile_map_address else mem_map.second_tile_map_address;
            const scroll_x: u8 = memory[mem_map.scroll_x];
            const scroll_y: u8 = memory[mem_map.scroll_y];
            const tilemap_addr: u16 = getTileMapAddr(state, tilemap_base_addr, scroll_x, scroll_y);
            state.fetcher_tile_addr = getTileAddr(state, memory, lcd_control, tilemap_addr);
            state.fetcher_data.pallete_addr = mem_map.bg_palette;
            tryPushPixel(state, memory);
        },
        .fetch_tile_obj => {
            const object: ObjectLineEntry = state.oam_line_list.pop();
            const obj_tile_base_addr: u16 = mem_map.first_tile_address;
            // In double height mode you are allowed to use either an even tile_index or the next tile_index and draw the same object.
            const obj_tile_index = if(lcd_control.obj_size == .double_height) object.tile_index - (object.tile_index % 2) else object.tile_index;
            const tile_offset: u2 = @intCast(object.tile_row / tile_size_y);
            const tile_base_addr: u16 = obj_tile_base_addr + (@as(u16, obj_tile_index + tile_offset) * tile_size_byte);
            state.fetcher_tile_addr = tile_base_addr + ((object.tile_row % tile_size_y) * def.byte_per_line);
            state.fetcher_data.pallete_addr = object.palette_addr;
            state.fetcher_data.bg_prio = object.bg_prio;
            state.fetcher_data.obj_prio = object.obj_prio;
            state.fifo_is_suspended = true;
        },
        .fetch_tile_window => {
            const windowmap_base_addr: u16 = if(lcd_control.window_map_area == .first_map) mem_map.first_tile_map_address else mem_map.second_tile_map_address;
            const win_pos_x: u8 = memory[mem_map.window_x] - 7;
            const win_pos_y: u8 = memory[mem_map.window_y];
            const tilemap_addr: u16 = getTileMapAddr(state, windowmap_base_addr, win_pos_x, win_pos_y);
            state.fetcher_tile_addr = getTileAddr(state, memory, lcd_control, tilemap_addr);
            state.fetcher_data.pallete_addr = mem_map.bg_palette;
            tryPushPixel(state, memory);
        },
        .nop => {
        },
        .nop_draw => {
            tryPushPixel(state, memory);
        },
        .oam_check => {
            const object = Object.fromOAM(memory, state.oam_scan_idx);
            const object_height: u8 = if(lcd_control.obj_size == .double_height) tile_size_y * 2 else tile_size_y;
            const obj_pixel_y: i16 = @as(i16, state.lcd_y) + 16 - @as(i16, object.y_position);
            if(obj_pixel_y >= 0 and  obj_pixel_y < object_height) {
                // starting from the 11th object, this will throw an error. Fine, we only need the first 10.
                state.oam_line_list.append(.{ 
                    .screen_pos_x = @as(i9, object.x_position) - 8, 
                    .tile_row = @intCast(obj_pixel_y),
                    .tile_index = object.tile_index, 
                    .palette_addr = if(object.flags.dmg_palette == .obp0) mem_map.obj_palette_0 else mem_map.obj_palette_1,
                    .obj_prio = state.oam_scan_idx, // CGB: OAM index, DMG: Unused
                    .bg_prio = @intFromEnum(object.flags.priority),
                }) catch {};
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

fn getTileMapAddr(state: *State, tilemap_base_addr: u16, pixel_offset_x: u8, pixel_offset_y: u8) u16 {
    const pixel_x: u16 = @as(u16, state.lcd_x) + pixel_offset_x  + state.fifo_pixel_count; 
    const pixel_y: u16 = @as(u16, state.lcd_y) + pixel_offset_y;

    const tilemap_x: u16 = (pixel_x / tile_size_x) % tile_map_size_x;
    const tilemap_y: u16 = (pixel_y / tile_size_y) % tile_map_size_y;
    assert(tilemap_x < tile_map_size_x and tilemap_y < tile_map_size_y);
    const tilemap_addr: u16 = tilemap_base_addr + tilemap_x + (tilemap_y * tile_map_size_y);
    return tilemap_addr;
} 

fn getTileAddr(state: *State, memory: *[def.addr_space]u8, lcd_control: LcdControl, tilemap_addr: u16) u16 {
    const bg_window_tile_base_addr: u16 = if(lcd_control.bg_window_tile_data == .second_tile_data) mem_map.second_tile_address else mem_map.first_tile_address;
    const signed_mode: bool = bg_window_tile_base_addr == mem_map.second_tile_address;
    const tile_index: u16 = memory[tilemap_addr];
    const tile_addr_offset: u16 = if(signed_mode) (tile_index + 128) % 256 else tile_index;
    const tile_base_addr: u16 = bg_window_tile_base_addr + tile_addr_offset * tile_size_byte;
    const tile_addr: u16 = tile_base_addr + ((state.lcd_y % tile_size_y) * def.byte_per_line);
    return tile_addr;
}

fn getPalette(paletteByte: u8) [4]u2 {
    // https://gbdev.io/pandocs/Palettes.html
    const color_id3: u2 = @intCast((paletteByte & (0b11 << 6)) >> 6);
    const color_id2: u2 = @intCast((paletteByte & (0b11 << 4)) >> 4);
    const color_id1: u2 = @intCast((paletteByte & (0b11 << 2)) >> 2);
    const color_id0: u2 = @intCast((paletteByte & (0b11 << 0)) >> 0);
    return [4]u2{ color_id0, color_id1, color_id2, color_id3 };
}

fn tryPushPixel(state: *State, memory: *[def.addr_space]u8) void {
    // pixel mixing requires at least 8 pixels.
    if(state.fifo_pixel_count <= 8 or state.fifo_is_suspended) {
        return;
    }
    
    const pixel2bpp: *BackgroundFifo2bpp = &state.background_fifo.buf[state.background_fifo.head];
    pixel2bpp.used_pixels += 1;
    pixel2bpp.first_bitplane, const first_color_bit = @shlWithOverflow(pixel2bpp.first_bitplane, 1);
    pixel2bpp.second_bitplane, const second_color_bit = @shlWithOverflow(pixel2bpp.second_bitplane, 1);
    // TODO: Maybe we can make this behaviour clearer if we had discard pixel function that is also microcoded?
    if(state.line_initial_shift > 0) {
        state.line_initial_shift -= 1;
    } else {
        const color_id: u2 = @as(u2, first_color_bit) + (@as(u2, second_color_bit) << 1); // LSB first

        const palette = getPalette(memory[pixel2bpp.pallete_addr]);
        const hw_color_id: u2 = palette[color_id];
        const first_hw_color_bit: u8 = @intCast(hw_color_id & 0b01);
        const second_hw_color_bit: u8 = @intCast((hw_color_id & 0b10) >> 1);

        const bitplane_idx: u13 = (@as(u13, state.lcd_x) / def.tile_width) * 2 + (@as(u13, state.lcd_y) * def.resolution_2bpp_width);
        const first_bitplane: *u8 = &state.color2bpp[bitplane_idx];
        const second_bitplane: *u8 = &state.color2bpp[bitplane_idx + 1];

        // TODO: This breaks when we introduce scrolling!
        const tile_pixel_x = state.lcd_x % 8;
        const tile_pixel_shift: u3 = @intCast(tile_size_x - tile_pixel_x - 1);
        first_bitplane.* |= first_hw_color_bit << tile_pixel_shift;
        second_bitplane.* |= second_hw_color_bit << tile_pixel_shift;

        state.lcd_x += 1;
        state.fifo_pixel_count -= 1;
    }

    if(pixel2bpp.used_pixels > 7) {
        // Pop it if there is now more pixel data to get!
        _ = state.background_fifo.readItem();
    }
}
