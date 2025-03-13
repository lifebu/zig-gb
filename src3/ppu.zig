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
    // TODO: Add support to disable background with this.
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
    // TODO: Add support for lcd_enable. 
    // When set to true, add .halt uop to uop_fifo. 
    // When set to false, start add initialize ppu (like on start). 
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
// TODO: Consider creating custom fifo that uses a ring-buffer. In testing, the readItem function costs 51% of all cycles.
// writeItem() => write(), write() => writeSlice(), readItem() => read(), readableLength() => len(), clear() / discard() => create own function 
// Use RingBuffer with FixedBufferAllocator.
// Consider using "AssumeLength" where appropriate.
const BackgroundFifo = std.fifo.LinearFifo(FifoData, .{ .Static = tile_size_x });
const ObjectFiFo = std.fifo.LinearFifo(FifoData, .{ .Static = tile_size_x });

const ObjectLineEntry = struct {
    obj_pos_x: u8,
    tile_row: u4, // single_height: [0, 7], double_height: [0, 15]
    tile_index: u8,
    palette_index: u3,
    obj_prio: u6, // CGB: OAM index, DMG: Unused
    obj_flip_x: bool,
    bg_prio: ObjectPriority,
};
const ObjectLineList = std.BoundedArray(ObjectLineEntry, 10);
pub fn sort_objects(_: void, lhs: ObjectLineEntry, rhs: ObjectLineEntry) bool {
    return lhs.obj_pos_x < rhs.obj_pos_x;
}

const MicroOp = enum {
    advance_draw,
    advance_hblank,
    advance_oam_scan,
    advance_vblank,
    clear_fifo_bg,
    fetch_low_bg,
    fetch_low_obj,
    fetch_high_bg,
    fetch_high_obj,
    fetch_push_bg,
    fetch_push_obj,
    fetch_tile_bg,
    fetch_tile_obj,
    fetch_tile_window,
    halt,
    nop,
    nop_draw,
    oam_check,
    push_pixel,
};
const MicroOpFifo = std.fifo.LinearFifo(MicroOp, .{ .Static = cycles_per_line });

// oam_scan
const oam_scan = [_]MicroOp{ .oam_check, .nop } ** (oam_size - 1) 
                   ++ [_]MicroOp{ .oam_check, .advance_draw };

// draw
const draw_bg_tile = [_]MicroOp{ .fetch_tile_bg, .nop_draw, .fetch_low_bg, .nop_draw, .fetch_high_bg, };
const draw_window_tile = [_]MicroOp{ .fetch_tile_window, .nop_draw, .fetch_low_bg, .nop_draw, .fetch_high_bg };
const draw_object_tile = [_]MicroOp{ .fetch_tile_obj, .nop, .fetch_low_obj, .nop, .fetch_high_obj, };

// hblank
const hblank = [_]MicroOp{ .nop } ** 203;
// vblank
const vblank = [_]MicroOp{ .nop } ** 455;

const FetcherData = struct {
    tile_addr: u16,
    first_bitplane: u8, 
    second_bitplane: u8,
    palette_index: u3,
    obj_prio: u6, // CGB: OAM index, DMG: Unused
    obj_flip_x: bool,
    bg_prio: ObjectPriority,
};

pub const State = struct {
    background_fifo: BackgroundFifo = BackgroundFifo.init(), 
    object_fifo: ObjectFiFo = ObjectFiFo.init(),
    uop_fifo: MicroOpFifo = MicroOpFifo.init(), 
    // In overscan space: [0, 167]
    lcd_overscan_x: u8 = 0, 
    lcd_y: u8 = 0, 
    draw_window: bool = false,
    line_cycles: u9 = 0,
    fetcher_data: FetcherData = undefined,
    oam_scan_idx: u6 = 0,
    // TODO: Rethink what data structure is best for this.
    // I would like a sorted list (obj_pos_x ascending) and also an easy way to get the first element of the list.
    oam_line_list: ObjectLineList = ObjectLineList.init(0) catch unreachable,

    color2bpp: [def.num_2bpp]u8 = [_]u8{ 0 } ** def.num_2bpp,
};

pub fn init(state: *State) void {
    state.uop_fifo.write(&oam_scan) catch unreachable;
}

pub fn cycle(state: *State, memory: *[def.addr_space]u8) void {
    var lcd_stat = LcdStat.fromMem(memory);
    const lcd_control = LcdControl.fromMem(memory);

    const uop: MicroOp = state.uop_fifo.readItem().?;
    switch(uop) {
        .advance_draw => {
            lcd_stat.mode = .draw;
            state.uop_fifo.writeAssumeCapacity(&draw_bg_tile); 
            state.background_fifo.discard(state.background_fifo.readableLength());
            state.object_fifo.discard(state.object_fifo.readableLength());
            state.draw_window = false;
            // TODO: This sorting breaks the drawing priority. If the objects have the same x-coordinate the one that comes first in the OAM wins.
            // Example: Title screen from pokemon blu
            std.mem.sort(ObjectLineEntry, state.oam_line_list.buffer[0..state.oam_line_list.len], {}, sort_objects);
            state.oam_scan_idx = 0;
            state.lcd_overscan_x = 0;
            checkLcdX(state, memory);
        },
        .advance_hblank => {
            // TODO: Add more asserts everywhere to make sure this works correctly!
            assert(state.lcd_overscan_x > (def.overscan_width) - 1); // we drew to few pixels before entering hblank
            assert(state.lcd_overscan_x < (def.overscan_width) + 1); // we drew to many pixels before entering hblank

            const hblank_len = 455 - 80 - state.line_cycles;
            state.uop_fifo.write(hblank[0..hblank_len]) catch unreachable;
            const advance: MicroOp = if(state.lcd_y >= 143) .advance_vblank else .advance_oam_scan;
            state.uop_fifo.writeItem(advance) catch unreachable;
            lcd_stat.mode = .h_blank;
            state.lcd_y += 1;
        },
        .advance_oam_scan => {
            lcd_stat.mode = .oam_scan;
            state.uop_fifo.write(&oam_scan) catch unreachable;
            state.oam_line_list.resize(0) catch unreachable;
            state.oam_scan_idx = 0;
            state.line_cycles = 0;
        },
        .advance_vblank => {
            lcd_stat.mode = .v_blank;
            state.line_cycles = 0;
            state.uop_fifo.write(&vblank) catch unreachable;
            state.lcd_y = (state.lcd_y + 1) % 154;
            const advance: MicroOp = if(state.lcd_y == 0) .advance_oam_scan else .advance_vblank;
            state.uop_fifo.writeItem(advance) catch unreachable;
        },
        .clear_fifo_bg => {
            state.background_fifo.discard(state.background_fifo.readableLength());
        },
        .fetch_low_bg => {
            state.fetcher_data.first_bitplane = memory[state.fetcher_data.tile_addr];
            state.fetcher_data.tile_addr += 1;
            tryPushPixel(state, memory);
        },
        .fetch_low_obj => {
            state.fetcher_data.first_bitplane = memory[state.fetcher_data.tile_addr];
            state.fetcher_data.tile_addr += 1;
        },
        .fetch_high_bg => {
            state.fetcher_data.second_bitplane = memory[state.fetcher_data.tile_addr];
            fetchPushBg(state, memory);
        },
        .fetch_high_obj => {
            state.fetcher_data.second_bitplane = memory[state.fetcher_data.tile_addr];
            fetchPushObj(state, memory);
        },
        .fetch_push_bg => {
            fetchPushBg(state, memory);
        },
        .fetch_push_obj => {
            fetchPushObj(state, memory);
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
            // TODO: I would like to use a simpler pop-style, but the objects a sorted by x_position ascending.
            // This is very over the top!
            var found: bool = false;
            var object: ObjectLineEntry = undefined;
            for(state.oam_line_list.slice()) |i_object| {
                if(i_object.obj_pos_x == state.lcd_overscan_x) {
                    object = i_object;
                    found = true;
                }
            }
            assert(found); // We must find the correct object when we trigger a tile fetch.
            const obj_tile_base_addr: u16 = mem_map.first_tile_address;
            // In double height mode you are allowed to use either an even tile_index or the next odd tile_index and draw the same object.
            const obj_tile_index_offset: u8 = @as(u8, @intFromEnum(lcd_control.obj_size)) * (object.tile_index % 2);
            const obj_tile_index: u8 = object.tile_index - obj_tile_index_offset;
            const tile_offset: u2 = @intCast(object.tile_row / tile_size_y);
            const tile_base_addr: u16 = obj_tile_base_addr + (@as(u16, obj_tile_index + tile_offset) * tile_size_byte);
            state.fetcher_data.tile_addr = tile_base_addr + ((object.tile_row % tile_size_y) * def.byte_per_line);
            state.fetcher_data.palette_index = object.palette_index;
            state.fetcher_data.bg_prio = object.bg_prio;
            state.fetcher_data.obj_flip_x = object.obj_flip_x;
            state.fetcher_data.obj_prio = object.obj_prio;
        },
        .fetch_tile_window => {
            const windowmap_base_addr: u16 = if(lcd_control.window_map_area == .first_map) mem_map.first_tile_map_address else mem_map.second_tile_map_address;
            const win_x: u8 = memory[mem_map.window_x];
            const win_pos_x: u8 = if(win_x >= 7) win_x - 7 else 0;
            const win_pos_y: u8 = memory[mem_map.window_y];
            const tilemap_addr: u16 = getTileMapAddr(state, windowmap_base_addr, win_pos_x, win_pos_y);
            state.fetcher_data.tile_addr = getTileAddr(state, memory, lcd_control, tilemap_addr);
            state.fetcher_data.palette_index = 0;
            tryPushPixel(state, memory);
        },
        .halt => {
            state.uop_fifo.writeItem(.halt) catch unreachable;
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
                const tile_row: u4 = @intCast(object_flip % object_height);
                // starting from the 11th object, this will throw an error. Fine, we only need the first 10.
                state.oam_line_list.append(.{ 
                    .obj_pos_x = object.x_position, 
                    .tile_row = tile_row,
                    .tile_index = object.tile_index, 
                    .palette_index =  @intFromEnum(object.flags.dmg_palette),
                    .obj_prio = state.oam_scan_idx, // CGB: OAM index, DMG: Unused
                    .obj_flip_x = object.flags.x_flip,
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

    memory[mem_map.lcd_y] = state.lcd_y;
    lcd_stat.ly_is_lyc = state.lcd_y == memory[mem_map.lcd_y_compare];
    // TODO: Add support for stat interrupt.
    lcd_stat.toMem(memory);
}

// TODO: zig 0.14.0 has labeled switches that I can use for fallthrough.
// https://github.com/ziglang/zig/issues/8220
fn fetchPushBg(state: *State, memory: *[def.addr_space]u8) void {
    if(state.background_fifo.readableLength() == 0) { // push succeeded
        const color_ids: [tile_size_x]u2 = convert2bpp(state.fetcher_data.first_bitplane, state.fetcher_data.second_bitplane, false);
        inline for(color_ids) |color_id| {
            state.background_fifo.writeItem(.{ 
                .color_id = color_id, 
                .bg_prio = .obj_over_bg, 
                .palette_index = 0, 
                .obj_prio = 0 
            }) catch unreachable;
        }
        if(state.draw_window) {
            state.uop_fifo.write(&draw_window_tile) catch unreachable;
        } else {
            state.uop_fifo.write(&draw_bg_tile) catch unreachable;
        }
    } else { // push failed 
        state.uop_fifo.writeItem(.fetch_push_bg) catch unreachable;
    }
    tryPushPixel(state, memory);

}

// TODO: zig 0.14.0 has labeled switches that I can use for fallthrough.
// https://github.com/ziglang/zig/issues/8220
fn fetchPushObj(state: *State, memory: *[def.addr_space]u8) void {
    // TODO: Not a big fan of all those conditions, maybe we can write it better by using transparent data?
    const color_ids: [tile_size_x]u2 = convert2bpp(state.fetcher_data.first_bitplane, state.fetcher_data.second_bitplane, state.fetcher_data.obj_flip_x);
    inline for(0..color_ids.len) |i| {
        const newData = FifoData{
            .color_id = color_ids[i], 
            .bg_prio = state.fetcher_data.bg_prio, 
            .palette_index = state.fetcher_data.palette_index, 
            .obj_prio = state.fetcher_data.obj_prio 
        };

        if(state.object_fifo.readableLength() > i) { // Mix existing pixel.
            // TODO: Not that nice to just raw access the fifo!
            var fifo_index = state.object_fifo.head + i;
            fifo_index %= state.object_fifo.buf.len;
            const current_pixel: *FifoData = &state.object_fifo.buf[fifo_index];
            const use_new: bool = current_pixel.color_id == color_id_transparent;
            if(use_new) {
                current_pixel.* = newData;
            }

        } else { // Add new pixel
            state.object_fifo.writeItem(newData) catch unreachable;
        }
    }
    if(state.draw_window) {
        state.uop_fifo.write(&draw_window_tile) catch unreachable;
    } else {
        state.uop_fifo.write(&draw_bg_tile) catch unreachable;
    }
    tryPushPixel(state, memory);
}

fn getTileMapAddr(state: *State, tilemap_base_addr: u16, pixel_offset_x: u8, pixel_offset_y: u8) u16 {
    const fifo_pixel_count: u8 = @intCast(state.background_fifo.readableLength());
    const lcd_x: i9 = @as(i9, state.lcd_overscan_x) - 8 + fifo_pixel_count;
    const pixel_x: u16 = @as(u16, @intCast(@max(0, lcd_x))) + pixel_offset_x; 
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

fn mixBackgroundColorId(bg_colorid: u2, original_bg_colorid: u2, obj_colorid: u2, original_obj_colorid: u2, bg_prio: ObjectPriority) u2 {
    if(bg_prio == .obj_over_bg) {
        return if(original_obj_colorid == color_id_transparent) bg_colorid else obj_colorid;
    } else {
        return if(original_bg_colorid == color_id_transparent) obj_colorid else bg_colorid;
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

fn checkLcdX(state: *State, memory: *[def.addr_space]u8) void {
    const lcd_control = LcdControl.fromMem(memory);

    const scroll_x: u8 = memory[mem_map.scroll_x];
    const scroll_overscan_x: u8 = tile_size_x - (scroll_x % tile_size_x);

    const win_x: u8 = memory[mem_map.window_x];
    const win_overscan_x: u8 = win_x + 1;
    const win_pos_y: u8 = memory[mem_map.window_y];

    // TODO: This now has to be tested every time we push a pixel, can we do this more rarely? Only test when relevant?
    // advance, scroll and window can only happen once per line. and object only up to 10 per line => max 8% hit-rate.
    if(state.lcd_overscan_x == def.overscan_width) {
        state.uop_fifo.discard(state.uop_fifo.readableLength());
        state.uop_fifo.writeItem(.advance_hblank) catch unreachable;
    } else if (state.lcd_overscan_x == scroll_overscan_x)  {
        state.uop_fifo.discard(state.uop_fifo.readableLength());
        state.uop_fifo.write(&draw_bg_tile) catch unreachable;
        state.background_fifo.discard(state.background_fifo.readableLength());
    } else if (state.lcd_y >= win_pos_y and state.lcd_overscan_x == win_overscan_x and lcd_control.window_enable and lcd_control.bg_window_enable) {
        state.uop_fifo.discard(state.uop_fifo.readableLength());
        state.uop_fifo.write(&draw_window_tile) catch unreachable;
        state.background_fifo.discard(state.background_fifo.readableLength());
        state.draw_window = true;
    } else if(lcd_control.obj_enable) {
        // TODO: Use the state.oam_scan_idx to speed this up, because the list is sorted.
        for(state.oam_line_list.slice()) |object| {
            if(object.obj_pos_x == state.lcd_overscan_x) {
                state.uop_fifo.discard(state.uop_fifo.readableLength());
                state.uop_fifo.write(&draw_object_tile) catch unreachable;
                break;
            }
        }
    }
}

fn tryPushPixel(state: *State, memory: *[def.addr_space]u8) void {
    if(state.background_fifo.readableLength() == 0) {
        return;
    }
    assert(state.lcd_overscan_x < def.overscan_width); // we tried to put a pixel outside of the screen.
    assert(state.lcd_y < def.resolution_height); // we tried to put a pixel outside of the screen.

    // fall back transparent object pixel that will be drawn over if we don't have pixels in the object fifo.
    const empty_pixel = FifoData{ .bg_prio = .obj_over_bg, .color_id = color_id_transparent, .obj_prio = 0, .palette_index = 0 };
    const obj_pixel: FifoData = state.object_fifo.readItem() orelse empty_pixel;
    const obj_palette_addr: u16 = mem_map.obj_palettes_dmg + obj_pixel.palette_index;
    const obj_palette = getPalette(memory[obj_palette_addr]);
    const obj_color_id: u2 = obj_palette[obj_pixel.color_id];

    const bg_pixel: FifoData = state.background_fifo.readItem() orelse unreachable;
    const bg_palette = getPalette(memory[mem_map.bg_palette]);
    const bg_color_id: u2 = bg_palette[bg_pixel.color_id];

    const color_id: u2 = mixBackgroundColorId(bg_color_id, bg_pixel.color_id, obj_color_id, obj_pixel.color_id, obj_pixel.bg_prio);
    const first_hw_color_bit: u8 = @intCast(color_id & 0b01);
    const second_hw_color_bit: u8 = @intCast((color_id & 0b10) >> 1);

    // TODO: Move the shader code to use a texture of hardware colorIds and not bitplanes!
    // Like the example from sokol chipz
    const bitplane_idx: u13 = (@as(u13, state.lcd_overscan_x) / def.tile_width) * 2 + (@as(u13, state.lcd_y) * def.resolution_2bpp_width);
    // TODO: This breaks after the first frame, because we are "adding" color ids to it, the last frame will be "smeared" on top of this frame.
    const first_bitplane: *u8 = &state.color2bpp[bitplane_idx];
    const second_bitplane: *u8 = &state.color2bpp[bitplane_idx + 1];

    const tile_pixel_x = state.lcd_overscan_x % 8;
    const tile_pixel_shift: u3 = @intCast(tile_size_x - tile_pixel_x - 1);
    first_bitplane.* |= first_hw_color_bit << tile_pixel_shift;
    second_bitplane.* |= second_hw_color_bit << tile_pixel_shift;

    state.lcd_overscan_x += 1;
    checkLcdX(state, memory);
}
