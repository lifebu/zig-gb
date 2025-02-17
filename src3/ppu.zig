const std = @import("std");
const assert = std.debug.assert;

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

// TODO: Think about the order of declarations I want to have in this file, what does zig standard do?
// constants, declaration, function?
const tile_size_x = 8;
const tile_size_y = 8;
const tile_size_byte = 16;
const color_id_transparent = 0;

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

const ObjectPriority = enum(u1) {
    obj_over_bg,
    obj_under_bg,
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
        priority: ObjectPriority,
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

const FifoData = struct {
    color_id: u2,
    palette_index: u3, // CGB: 0-7, DMG: 0-1 
    obj_prio: u6, // CGB: OAM index, DMG: Unused
    bg_prio: ObjectPriority,
};
const BackgroundFifo = std.fifo.LinearFifo(FifoData, .{ .Static = tile_size_x });
const ObjectFiFo = std.fifo.LinearFifo(FifoData, .{ .Static = tile_size_x });

const ObjectLineEntry = struct {
    // TODO: actuall u8, but we can have negative screen_pos for partially visible objects because they also count to the object limit!
    screen_pos_x: i9, // to compose uOps.
    tile_row: u4, // single_height: [0, 7], double_height: [0, 15]
    tile_index: u8,
    palette_index: u3,
    obj_prio: u6, // CGB: OAM index, DMG: Unused
    obj_flip_y: bool,
    bg_prio: ObjectPriority,
};
const ObjectLineList = std.BoundedArray(ObjectLineEntry, 10);

const MicroOp = enum {
    advance_mode_draw,
    advance_mode_hblank,
    advance_mode_oam_scan,
    advance_mode_vblank,
    fetch_data_low_bg,
    fetch_data_low_obj,
    fetch_data_high_bg,
    fetch_data_high_obj,
    fetch_push_bg,
    fetch_push_obj,
    fetch_tile_bg,
    fetch_tile_obj,
    fetch_tile_window,
    nop,
    nop_draw,
    oam_check,
    push_pixel,
};
const MicroOpFifo = std.fifo.LinearFifo(MicroOp, .{ .Static = cycles_per_line });

const oam_scan_uops = [_]MicroOp{ .oam_check, .nop } ** (oam_size - 1) 
                   ++ [_]MicroOp{ .oam_check, .advance_mode_draw };
const draw_bg_tile_uops = [_]MicroOp{ .fetch_tile_bg, .nop_draw, .fetch_data_low_bg, .nop_draw, .fetch_data_high_bg, .fetch_push_bg, };
// TODO: I need to clear the background_fifo the first time we encounter the window (which explains the 6 cycle penalty). 
const draw_window_tile_uops = [_]MicroOp{ .fetch_tile_window, .nop_draw, .fetch_data_low_bg, .nop_draw, .fetch_data_high_bg, .fetch_push_bg, };
// TODO: How can I draw objects at the edge of the screen that are only partially visible? 
// Maybe the first 6 cycles on a line that are thrown away acording to documentation can actually be used for objects like this?
// This might be complicated for the mixing code? This would be like an overdraw?
const draw_object_tile_uops = [_]MicroOp{ .fetch_tile_obj, .nop, .fetch_data_low_obj, .nop, .fetch_data_high_obj, .fetch_push_obj };
const hblank_uops = [_]MicroOp{ .nop } ** 203;
const vblank_uops = [_]MicroOp{ .nop } ** 455;

/// Generates all uops needed for the draw mode and hblank mode of the current line.
fn genMicroCodeDrawAndHBlank(state: *State, line_initial_shift: u3) void {
    // TODO: Add support for objects and window!
    // TODO: I need to rethink how to generate this code better in a dynamic way.
    // draw
    // TODO: According to pandocs the first tile we would load (draw_bg_tile_uops) will be discarded.
    // Because I don't handle this corerectly I will just add 6 nops instead.
    // Later I should load garbage data and discard it, so that I can support partially visible objects.
    state.uop_fifo.write(&[_]MicroOp{ .nop, .nop, .nop, .nop, .nop, .nop }) catch unreachable;
    state.uop_fifo.write(&draw_bg_tile_uops) catch unreachable;
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

const FetcherData = struct {
    tile_addr: u16,
    first_bitplane: u8, 
    second_bitplane: u8,
    palette_index: u3,
    obj_prio: u6, // CGB: OAM index, DMG: Unused
    obj_flip_y: bool,
    bg_prio: ObjectPriority,
};

pub const State = struct {
    background_fifo: BackgroundFifo = BackgroundFifo.init(), 
    object_fifo: ObjectFiFo = ObjectFiFo.init(),
    uop_fifo: MicroOpFifo = MicroOpFifo.init(),     
    lcd_x: u8 = 0, 
    lcd_y: u8 = 0, 
    line_cycles: u9 = 0,
    line_initial_shift: u3 = 0,
    fetcher_data: FetcherData = undefined,
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
            state.lcd_x = 0;
        },
        .advance_mode_hblank => {
            assert(state.lcd_x > 159); // we drew to few pixels before entering hblank
            assert(state.lcd_x < 161); // we drew to many pixels before entering hblank
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
        .fetch_data_low_bg => {
            state.fetcher_data.first_bitplane = memory[state.fetcher_data.tile_addr];
            state.fetcher_data.tile_addr += 1;
            tryPushPixel(state, memory);
        },
        // TODO: zig 0.14.0 has labeled switches that I can use for fallthrough.
        // Fall from _bg to _obj
        // https://github.com/ziglang/zig/issues/8220
        .fetch_data_low_obj => {
            state.fetcher_data.first_bitplane = memory[state.fetcher_data.tile_addr];
            state.fetcher_data.tile_addr += 1;
        },
        .fetch_data_high_bg => {
            state.fetcher_data.second_bitplane = memory[state.fetcher_data.tile_addr];
            tryPushPixel(state, memory);
        },
        // TODO: zig 0.14.0 has labeled switches that I can use for fallthrough.
        // Fall from _bg to _obj
        // https://github.com/ziglang/zig/issues/8220
        .fetch_data_high_obj => {
            state.fetcher_data.second_bitplane = memory[state.fetcher_data.tile_addr];
        },
        .fetch_push_bg => {    
            if(state.background_fifo.readableLength() == 0) {
                // TODO: Move this into a helper function that pushes fetcher_data into the fifo, (which can also include 2bpp conversion).
                // Because the object is basically the same code.
                // I should try to write the function so that I am using std.fifo.write(), which will return an error if it fails. This requires that I generate an entire fifo_data array!
                const color_ids: [tile_size_x]u2 = convert2bpp(state.fetcher_data.first_bitplane, state.fetcher_data.second_bitplane, false);
                inline for(color_ids) |color_id| {
                    state.background_fifo.writeItem(.{ 
                        .color_id = color_id, 
                        .bg_prio = .obj_over_bg, 
                        .palette_index = 0, 
                        .obj_prio = 0 
                    }) catch unreachable;
                }
            }
            tryPushPixel(state, memory);
        },
        .fetch_push_obj => {
            // TODO: Mix with existing object data if we have one. This will crash if we already have 2 object data.
            const color_ids: [tile_size_x]u2 = convert2bpp(state.fetcher_data.first_bitplane, state.fetcher_data.second_bitplane, state.fetcher_data.obj_flip_y);
            inline for(color_ids) |color_id| {
                state.object_fifo.writeItem(.{ 
                    .color_id = color_id, 
                    .bg_prio = state.fetcher_data.bg_prio, 
                    .palette_index = state.fetcher_data.palette_index, 
                    .obj_prio = state.fetcher_data.obj_prio 
                }) catch unreachable;
            }
            tryPushPixel(state, memory);
        },
        .fetch_tile_bg => {
            const tilemap_base_addr: u16 = if(lcd_control.bg_map_area == .first_map) mem_map.first_tile_map_address else mem_map.second_tile_map_address;
            const scroll_x: u8 = memory[mem_map.scroll_x];
            const scroll_y: u8 = memory[mem_map.scroll_y];
            const tilemap_addr: u16 = getTileMapAddr(state, tilemap_base_addr, scroll_x, scroll_y);
            state.fetcher_data.tile_addr = getTileAddr(state, memory, lcd_control, tilemap_addr);
            state.fetcher_data.palette_index = 0;
            tryPushPixel(state, memory);
        },
        .fetch_tile_obj => {
            const object: ObjectLineEntry = state.oam_line_list.pop();
            const obj_tile_base_addr: u16 = mem_map.first_tile_address;
            // In double height mode you are allowed to use either an even tile_index or the next odd tile_index and draw the same object.
            const obj_tile_index_offset: u8 = @as(u8, @intFromEnum(lcd_control.obj_size)) * (object.tile_index % 2);
            const obj_tile_index: u8 = object.tile_index - obj_tile_index_offset;
            const tile_offset: u2 = @intCast(object.tile_row / tile_size_y);
            const tile_base_addr: u16 = obj_tile_base_addr + (@as(u16, obj_tile_index + tile_offset) * tile_size_byte);
            state.fetcher_data.tile_addr = tile_base_addr + ((object.tile_row % tile_size_y) * def.byte_per_line);
            state.fetcher_data.palette_index = object.palette_index;
            state.fetcher_data.bg_prio = object.bg_prio;
            state.fetcher_data.obj_flip_y = object.obj_flip_y;
            state.fetcher_data.obj_prio = object.obj_prio;
        },
        .fetch_tile_window => {
            const windowmap_base_addr: u16 = if(lcd_control.window_map_area == .first_map) mem_map.first_tile_map_address else mem_map.second_tile_map_address;
            const win_pos_x: u8 = memory[mem_map.window_x] - 7;
            const win_pos_y: u8 = memory[mem_map.window_y];
            const tilemap_addr: u16 = getTileMapAddr(state, windowmap_base_addr, win_pos_x, win_pos_y);
            state.fetcher_data.tile_addr = getTileAddr(state, memory, lcd_control, tilemap_addr);
            state.fetcher_data.palette_index = 0;
            tryPushPixel(state, memory);
        },
        .nop => {
        },
        .nop_draw => {
            tryPushPixel(state, memory);
        },
        .oam_check => {
            const object = Object.fromOAM(memory, state.oam_scan_idx);
            const object_height: u8 = tile_size_y * (1 + @as(u8, @intFromEnum(lcd_control.obj_size)));
            const obj_pixel_y: i16 = @as(i16, state.lcd_y) + 16 - @as(i16, object.y_position);
            if(obj_pixel_y >= 0 and  obj_pixel_y < object_height) {
                const object_flip: u8 = @intCast(if(object.flags.y_flip) object_height - 1 - obj_pixel_y  else obj_pixel_y);
                const tile_row: u4 = @intCast(object_flip % tile_size_y);
                // starting from the 11th object, this will throw an error. Fine, we only need the first 10.
                state.oam_line_list.append(.{ 
                    .screen_pos_x = @as(i9, object.x_position) - 8, 
                    .tile_row = tile_row,
                    .tile_index = object.tile_index, 
                    .palette_index =  @intFromEnum(object.flags.dmg_palette),
                    .obj_prio = state.oam_scan_idx, // CGB: OAM index, DMG: Unused
                    .obj_flip_y = object.flags.y_flip,
                    .bg_prio = object.flags.priority,
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
    const fifo_pixel_count: u16 = @intCast(state.background_fifo.readableLength());
    const pixel_x: u16 = @as(u16, state.lcd_x) + pixel_offset_x + fifo_pixel_count; 
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

fn convert2bpp(first_bitplane: u8, second_bitplane: u8, reverse: bool) [tile_size_x]u2 {
    var first_bitplane_var: u8 = if(reverse) @bitReverse(first_bitplane) else first_bitplane;
    var second_bitplane_var: u8 = if(reverse) @bitReverse(second_bitplane) else second_bitplane;
    var result: [tile_size_x]u2 = undefined;
    inline for(0..tile_size_x) |i| {
        first_bitplane_var, const first_bit: u2 = @shlWithOverflow(first_bitplane_var, 1);
        second_bitplane_var, const second_bit: u2 = @shlWithOverflow(second_bitplane_var, 1);
        result[i] = first_bit + (second_bit << 1); // LSB first
    }
    return result;
}

fn mixObjectColorId(current_obj_colorid: u2, new_obj_colorid: u2) u2 {
    return if(current_obj_colorid == color_id_transparent) new_obj_colorid else current_obj_colorid;
}

fn mixBackgroundColorId(bg_colorid: u2, obj_colorid: u2, bg_prio: ObjectPriority) u2 {
    if(bg_prio == .obj_over_bg) {
        return if(obj_colorid == color_id_transparent) bg_colorid else obj_colorid;
    } else {
        return if(bg_colorid == color_id_transparent) obj_colorid else bg_colorid;
    }
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
    if(state.background_fifo.readableLength() == 0) {
        return;
    }
   
    const bg_pixel: FifoData = state.background_fifo.readItem() orelse unreachable;
    if(state.line_initial_shift > 0) {
        state.line_initial_shift -= 1;
        return; // Discard background pixel.
    }

    // fall back transparent object pixel that will be drawn over if we don't have pixels in the object fifo.
    const empty_pixel = FifoData{ .bg_prio = .obj_over_bg, .color_id = color_id_transparent, .obj_prio = 0, .palette_index = 0 };
    const obj_pixel: FifoData = state.object_fifo.readItem() orelse empty_pixel;
    const obj_palette_addr: u16 = mem_map.obj_palettes_dmg + obj_pixel.palette_index;
    const obj_palette = getPalette(memory[obj_palette_addr]);
    const obj_color_id: u2 = obj_palette[obj_pixel.color_id];

    const bg_palette = getPalette(memory[mem_map.bg_palette]);
    const bg_color_id: u2 = bg_palette[bg_pixel.color_id];

    const color_id: u2 = mixBackgroundColorId(bg_color_id, obj_color_id, obj_pixel.bg_prio);
    const first_hw_color_bit: u8 = @intCast(color_id & 0b01);
    const second_hw_color_bit: u8 = @intCast((color_id & 0b10) >> 1);

    // TODO: Move the shader code to use a texture of hardware colorIds and not bitplanes!
    const bitplane_idx: u13 = (@as(u13, state.lcd_x) / def.tile_width) * 2 + (@as(u13, state.lcd_y) * def.resolution_2bpp_width);
    const first_bitplane: *u8 = &state.color2bpp[bitplane_idx];
    const second_bitplane: *u8 = &state.color2bpp[bitplane_idx + 1];

    const tile_pixel_x = state.lcd_x % 8;
    const tile_pixel_shift: u3 = @intCast(tile_size_x - tile_pixel_x - 1);
    first_bitplane.* |= first_hw_color_bit << tile_pixel_shift;
    second_bitplane.* |= second_hw_color_bit << tile_pixel_shift;

    state.lcd_x += 1;
}
