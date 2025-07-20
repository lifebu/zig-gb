const std = @import("std");
const assert = std.debug.assert;

const def = @import("defines.zig");
const Fifo = @import("util/fifo.zig");
const mem_map = @import("mem_map.zig");
// TODO: Try to get rid of mmu dependency. It is currently required to read out IE and IF.
const MMU = @import("mmu.zig");

const tile_size_x = 8;
const tile_size_y = 8;
const tile_size_byte = 16;
const color_id_transparent = 0;

const tile_map_size_x = 32;
const tile_map_size_y = 32;
const tile_map_size_byte = tile_map_size_x * tile_map_size_y;
const tile_map_pixel_size_x = tile_map_size_x * tile_size_x;
const tile_map_pixel_size_y = tile_map_size_y * tile_size_y;

const oam_size = 40;
const obj_size_byte = 4;
const obj_per_line = 10;
const obj_double_height = tile_size_y * 2;

const cycles_per_line = 456;
const cycles_oam_scan = 80;

const vblank_scanlines = 10;
const max_lcd_y = def.resolution_height + vblank_scanlines;

const TileMapAddress = enum(u1) {
    map_9800,
    map_9C00,
};
const LcdControl = packed struct {
    // TODO: Add support to disable background with this.
    bg_window_enable: bool = false,
    obj_enable: bool = false,
    obj_size: enum(u1) {
        single_height,
        double_height,
    } = .single_height,
    bg_map_area: TileMapAddress = .map_9800,
    bg_window_tile_data: enum(u1) {
        tile_8800,
        tile_8000,
    } = .tile_8800,
    window_enable: bool = false,
    window_map_area: TileMapAddress = .map_9800,
    // TODO: Add support for lcd_enable. 
    // When set to true, add .halt uop to uop_fifo. 
    // When set to false, start add initialize ppu (like on start). 
    lcd_enable: bool = false,

    pub fn fromMem(mmu: *MMU.State) LcdControl {
        return @bitCast(mmu.memory[mem_map.lcd_control]);
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

    pub fn fromMem(mmu: *MMU.State) LcdStat {
        return @bitCast(mmu.memory[mem_map.lcd_stat]);
    } 

    pub fn toMem(self: LcdStat, mmu: *MMU.State) void {
        mmu.memory[mem_map.lcd_stat] = @bitCast(self);
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

    pub fn fromOAM(mmu: *MMU.State, obj_idx: u6) *align(1) const Object {
        const address: u16 = mem_map.oam_low + (@as(u16, obj_idx) * obj_size_byte);
        return @ptrCast(&mmu.memory[address]);
    }
};

const FifoData = struct {
    color_id: u2,
    palette_addr: u16,
    palette_index: u3, // CGB: 0-7, DMG: 0-1 
    obj_prio: u6, // CGB: OAM index, DMG: Unused
    bg_prio: ObjectPriority,
};
const transparent_pixel = FifoData{ .bg_prio = .obj_over_bg, .color_id = color_id_transparent, .obj_prio = 0, .palette_addr = 0, .palette_index = 0 };
const BackgroundFifo = Fifo.RingbufferFifo(FifoData, tile_size_x);
const ObjectFiFo = Fifo.RingbufferFifo(FifoData, tile_size_x);

const FetcherData = struct {
    palette_index: u3 = 0,
    tile_addr: u16 = 0,
    first_bitplane: u8 = 0, 
    second_bitplane: u8 = 0,

    obj_pos_x: u8 = 0,
    obj_tile_row: u4 = 0, // single_height: [0, 7], double_height: [0, 15]
    obj_flip_x: bool = false,
    bg_prio: ObjectPriority = .obj_over_bg,
    obj_prio: u6 = 0, // CGB: OAM index, DMG: Unused
    obj_tile_index: u8 = 0,

    // note: requires stable sort
    fn sortObjects(_: void, lhs: FetcherData, rhs: FetcherData) bool {
        return lhs.obj_pos_x < rhs.obj_pos_x;
    }
};
const ObjectLineFifo = Fifo.RingbufferFifo(FetcherData, obj_per_line);

const MicroOp = enum {
    advance_draw,
    advance_hblank,
    advance_oam_scan,
    advance_vblank,
    fetch_low_bg,
    fetch_low_obj,
    fetch_high_bg,
    fetch_high_obj,
    fetch_push_bg,
    fetch_tile_bg,
    fetch_tile_obj,
    fetch_tile_window,
    halt,
    nop,
    nop_draw,
    oam_check,
    push_pixel,
};
const MicroOpFifo = Fifo.RingbufferFifo(MicroOp, cycles_per_line);

const oam_scan = [_]MicroOp{ .oam_check, .nop } ** (oam_size - 1) ++ [_]MicroOp{ .oam_check, .advance_draw };
const draw_bg_tile = [_]MicroOp{ .fetch_tile_bg, .nop_draw, .fetch_low_bg, .nop_draw, .fetch_high_bg, };
const draw_window_tile = [_]MicroOp{ .fetch_tile_window, .nop_draw, .fetch_low_bg, .nop_draw, .fetch_high_bg };
const draw_object_tile = [_]MicroOp{ .fetch_tile_obj, .nop, .fetch_low_obj, .nop, .fetch_high_obj, };
const blank = [_]MicroOp{ .nop } ** (cycles_per_line - 1);

pub const State = struct {
    current_bg_window_uops: []const MicroOp = undefined,
    uop_fifo: MicroOpFifo = .{}, 
    draw_cycles: u9 = 0,
    line_penalty: u9 = 0,

    oam_scan_idx: u6 = 0,
    oam_line_list: ObjectLineFifo = .{},

    background_fifo: BackgroundFifo = .{}, 
    object_fifo: ObjectFiFo = .{},
    // In overscan space: [0, 167]
    lcd_overscan_x: u8 = 0, 
    lcd_y: u8 = 0, 
    fetcher_data: FetcherData = .{},

    colorIds: [def.overscan_resolution]u8 = [_]u8{ 0 } ** def.overscan_resolution,
};

pub fn init(state: *State) void {
    // TODO: Once we have an actual system and cpu think about what we need to do to initialize the PPU.
    state.uop_fifo.write(&oam_scan);
}

// TODO: Remove dependency to the memory array.
pub fn cycle(state: *State, mmu: *MMU.State) void {
    // TODO: PPU also needs to know the mmu, because the ppu needs to discard/change cpu read/write requests into mmu that the ppu owns.
    var lcd_stat = LcdStat.fromMem(mmu);
    const lcd_control = LcdControl.fromMem(mmu);

    const uop: MicroOp = state.uop_fifo.readItem().?;
    switch(uop) {
        .advance_draw => {
            lcd_stat.mode = .draw;
            state.current_bg_window_uops = &draw_bg_tile;
            state.uop_fifo.write(state.current_bg_window_uops); 
            state.background_fifo.clear();
            state.object_fifo.clear();
            assert(state.oam_line_list.isAligned()); // Sort requires contiguous mmu.
            std.mem.sort(FetcherData, state.oam_line_list.buffer[0..state.oam_line_list.length()], {}, FetcherData.sortObjects);
            state.lcd_overscan_x = 0;
            // Advance is done in the last cycle of oam_scan. We set it to the max value so that it overflows to 0. 
            state.draw_cycles = std.math.maxInt(u9);
            state.line_penalty = 0;
            checkLcdX(state, mmu);
        },
        .advance_hblank => {
            assert(state.lcd_overscan_x > (def.overscan_width) - 1); // we drew to few pixels before entering hblank
            assert(state.lcd_overscan_x < (def.overscan_width) + 1); // we drew to many pixels before entering hblank

            lcd_stat.mode = .h_blank;
            // TODO: The actual length of draw_cycles is not what is expected (172 + state.line_penalty)
            // If you add the following line to main, you can see the timing as a line going through (best to use pkmn_silv title screen):
            // state.ppu.colorIds = [_]u8{ 0 } ** def.overscan_resolution;
            // In practice the error is between 76-135 dots (0,1-0,2% error).
            const length = cycles_per_line - 1 - state.draw_cycles - cycles_oam_scan;
            advanceBlank(state, length);
        },
        .advance_oam_scan => {
            lcd_stat.mode = .oam_scan;
            state.uop_fifo.write(&oam_scan);
            state.oam_line_list.clearRealign(); // required for std.mem.sort
            state.oam_scan_idx = 0;
        },
        .advance_vblank => {
            mmu.memory[mem_map.interrupt_flag] |= mem_map.interrupt_vblank;
            lcd_stat.mode = .v_blank;
            advanceBlank(state, blank.len);
        },
        .fetch_low_bg => {
            state.fetcher_data.first_bitplane = mmu.memory[state.fetcher_data.tile_addr];
            state.fetcher_data.tile_addr += 1;
            tryPushPixel(state, mmu);
        },
        .fetch_low_obj => {
            state.fetcher_data.first_bitplane = mmu.memory[state.fetcher_data.tile_addr];
            state.fetcher_data.tile_addr += 1;
        },
        .fetch_high_bg => {
            state.fetcher_data.second_bitplane = mmu.memory[state.fetcher_data.tile_addr];
            fetchPushBg(state, mmu);
        },
        .fetch_high_obj => {
            state.fetcher_data.second_bitplane = mmu.memory[state.fetcher_data.tile_addr];

            var pixels: [tile_size_x]FifoData = convert2bpp(state.fetcher_data, mem_map.obj_palettes_dmg);
            inline for(0..pixels.len) |i| {
                const current_pixel: FifoData = state.object_fifo.readItem() orelse transparent_pixel;
                pixels[i] = if(current_pixel.color_id == color_id_transparent) pixels[i] else current_pixel;
            }
            state.object_fifo.write(&pixels);

            if(nextObjectIsAtLcdX(state)) {
                // subtract penalty that will be applied by checkLcdX() again.
                const fifo_length: i9 = @intCast(state.background_fifo.length()); 
                state.line_penalty -= @max(0, 6 - fifo_length);
                checkLcdX(state, mmu);
            } else {
                state.uop_fifo.write(state.current_bg_window_uops);
                tryPushPixel(state, mmu);
            }
        },
        .fetch_push_bg => {
            fetchPushBg(state, mmu);
        },
        .fetch_tile_bg => {
            const tilemap_addr_type: TileMapAddress = lcd_control.bg_map_area;
            const scroll_x: u8 = mmu.memory[mem_map.scroll_x];
            const scroll_y: u8 = mmu.memory[mem_map.scroll_y];
            const overscan_x_tile_offset: u5 = tile_map_size_x - 1;
            state.fetcher_data = FetcherData{ 
                .tile_addr = getTileMapTileAddr(state, mmu, tilemap_addr_type, overscan_x_tile_offset, scroll_x, scroll_y),
            };
            tryPushPixel(state, mmu);
        },
        .fetch_tile_obj => {
            const current_object: FetcherData = state.oam_line_list.readItem() orelse unreachable;
            state.fetcher_data = current_object;

            // In double height mode you are allowed to use either an even tile_index or the next odd tile_index and draw the same object.
            const obj_tile_index_offset: u8 = @as(u8, @intFromEnum(lcd_control.obj_size)) * (current_object.obj_tile_index % 2);
            const obj_tile_index: u8 = current_object.obj_tile_index - obj_tile_index_offset;
            const obj_height_tile_offset: u2 = @intCast(current_object.obj_tile_row / tile_size_y);
            const tile_addr_offset: u16 = obj_tile_index + obj_height_tile_offset;
            const tile_addr: u16 = mem_map.tile_8000 + tile_addr_offset * tile_size_byte;
            const tile_line_addr: u16 = tile_addr + ((current_object.obj_tile_row % tile_size_y) * def.byte_per_line);
            state.fetcher_data.tile_addr = tile_line_addr;
        },
        .fetch_tile_window => {
            const tilemap_addr_type: TileMapAddress = lcd_control.window_map_area;
            const win_overscan_x: u16 = mmu.memory[mem_map.window_x] + 1;
            const win_y: u16 = mmu.memory[mem_map.window_y];
            // Note: this works because we use modulo later to get the tile map address and tile line address.
            const scroll_x: u16 = tile_map_pixel_size_x - win_overscan_x; 
            const scroll_y: u16 = tile_map_pixel_size_y - win_y;
            state.fetcher_data = FetcherData{ 
                .tile_addr = getTileMapTileAddr(state, mmu, tilemap_addr_type, 0, scroll_x, scroll_y),
            };
            tryPushPixel(state, mmu);
        },
        .halt => {
            state.uop_fifo.writeItem(.halt);
        },
        .nop => {
        },
        .nop_draw => {
            tryPushPixel(state, mmu);
        },
        .oam_check => {
            const object = Object.fromOAM(mmu, state.oam_scan_idx);
            const object_height: u8 = tile_size_y * (1 + @as(u8, @intFromEnum(lcd_control.obj_size)));
            const obj_pixel_y: i16 = @as(i16, state.lcd_y) + obj_double_height - @as(i16, object.y_position);
            if(obj_pixel_y >= 0 and  obj_pixel_y < object_height) {
                const object_flip: u8 = @intCast(if(object.flags.y_flip) object_height - 1 - obj_pixel_y  else obj_pixel_y);
                const tile_row: u4 = @intCast(object_flip % object_height);
                // after 10 objects, they will be discarded. We only need the first 10.
                state.oam_line_list.writeItemDiscardWhenFull(FetcherData{ 
                    .bg_prio = object.flags.priority,
                    .obj_flip_x = object.flags.x_flip,
                    .obj_pos_x = object.x_position, 
                    .obj_prio = state.oam_scan_idx, // CGB: OAM index, DMG: Unused
                    .obj_tile_index = object.tile_index, 
                    .obj_tile_row = tile_row,
                    .palette_index =  @intFromEnum(object.flags.dmg_palette),
                });
            }
            state.oam_scan_idx += 1;
        },
        else => { 
            std.debug.print("PPU_MICRO_OP_NOT_IMPLEMENTED: {any}\n", .{uop});
            unreachable;
        },
    }

    state.draw_cycles +%= 1;
    mmu.memory[mem_map.lcd_y] = state.lcd_y;
    lcd_stat.ly_is_lyc = state.lcd_y == mmu.memory[mem_map.lcd_y_compare];
    // TODO: Add support for stat interrupt.
    lcd_stat.toMem(mmu);
}

pub fn memory(_: *State, _: *def.MemoryRequest) void {

}

fn advanceBlank(state: *State, length: usize) void {
    state.lcd_y = (state.lcd_y + 1) % max_lcd_y;
    state.uop_fifo.write(blank[0..length]);
    const advance: MicroOp = if(state.lcd_y >= def.resolution_height) .advance_vblank else .advance_oam_scan;
    state.uop_fifo.writeItem(advance);
}

fn checkLcdX(state: *State, mmu: *MMU.State) void {
    const lcd_control = LcdControl.fromMem(mmu);

    const scroll_x: u8 = mmu.memory[mem_map.scroll_x];
    const scroll_overscan_x: u8 = tile_size_x - (scroll_x % tile_size_x);

    const win_x: u8 = mmu.memory[mem_map.window_x];
    const win_overscan_x: u8 = win_x + 1;
    const win_pos_y: u8 = mmu.memory[mem_map.window_y];

    const has_next_object = nextObjectIsAtLcdX(state);

    // End of line
    if(state.lcd_overscan_x == def.overscan_width) {
        state.uop_fifo.clear();
        state.uop_fifo.writeItem(.advance_hblank);
    // Encountered window
    } else if (state.lcd_y >= win_pos_y and state.lcd_overscan_x == win_overscan_x and lcd_control.window_enable and lcd_control.bg_window_enable) {
        state.current_bg_window_uops = &draw_window_tile;
        state.uop_fifo.clear();
        state.uop_fifo.write(state.current_bg_window_uops);
        state.background_fifo.clear();
        state.line_penalty += 6;
    // Background scrolling
    } else if (state.current_bg_window_uops[0] != draw_window_tile[0] and state.lcd_overscan_x == scroll_overscan_x)  {
        state.uop_fifo.clear();
        state.uop_fifo.write(&draw_bg_tile);
        state.background_fifo.clear();
        state.line_penalty += scroll_x % 8;
    // Found Object
    } else if((lcd_control.obj_enable or true) and has_next_object) {
        state.uop_fifo.clear();
        state.uop_fifo.write(&draw_object_tile);
        const fifo_length: i9 = @intCast(state.background_fifo.length()); 
        state.line_penalty += 6 + @max(0, 6 - fifo_length);
    }
}

fn convert2bpp(fetcher_data: FetcherData, palette_addr: u16) [tile_size_x]FifoData {
    var first_bitplane_var: u8 = if(fetcher_data.obj_flip_x) @bitReverse(fetcher_data.first_bitplane) else fetcher_data.first_bitplane;
    var second_bitplane_var: u8 = if(fetcher_data.obj_flip_x) @bitReverse(fetcher_data.second_bitplane) else fetcher_data.second_bitplane;

    var result: [tile_size_x]FifoData = undefined;
    inline for(0..tile_size_x) |i| {
        first_bitplane_var, const first_bit: u2 = @shlWithOverflow(first_bitplane_var, 1);
        second_bitplane_var, const second_bit: u2 = @shlWithOverflow(second_bitplane_var, 1);
        const color_id: u2 = first_bit + (second_bit << 1); // LSB first 

        result[i] = FifoData { 
            .color_id = color_id, .bg_prio = fetcher_data.bg_prio, 
            .palette_addr = palette_addr, .palette_index = fetcher_data.palette_index, 
            .obj_prio = fetcher_data.obj_prio 
        };
    }
    return result;
}

fn fetchPushBg(state: *State, mmu: *MMU.State) void {
    if(state.background_fifo.isEmpty()) { // push succeeded
        const pixels: [tile_size_x]FifoData = convert2bpp(state.fetcher_data, mem_map.bg_palette);
        state.background_fifo.write(&pixels);
        state.uop_fifo.write(state.current_bg_window_uops);
    } else { // push failed 
        state.uop_fifo.writeItem(.fetch_push_bg);
    }
    tryPushPixel(state, mmu);
}

fn getPalette(paletteByte: u8) [def.color_depth]u2 {
    // https://gbdev.io/pandocs/Palettes.html
    const color_id3: u2 = @intCast((paletteByte & (0b11 << 6)) >> 6);
    const color_id2: u2 = @intCast((paletteByte & (0b11 << 4)) >> 4);
    const color_id1: u2 = @intCast((paletteByte & (0b11 << 2)) >> 2);
    const color_id0: u2 = @intCast((paletteByte & (0b11 << 0)) >> 0);
    return [def.color_depth]u2{ color_id0, color_id1, color_id2, color_id3 };
}

fn getTileMapTileAddr(state: *State, mmu: *MMU.State, tilemap_addr_type: TileMapAddress, tile_x_offset: u5, scroll_x: u16, scroll_y: u16) u16 {
    const lcd_control = LcdControl.fromMem(mmu);

    const fifo_pixel_count: u3 = @intCast(state.background_fifo.length());
    const pixel_x: u16 = @as(u16, state.lcd_overscan_x) + fifo_pixel_count + scroll_x; 
    const pixel_y: u16 = @as(u16, state.lcd_y) + scroll_y; 

    const tilemap_x: u16 = ((pixel_x / tile_size_x) +% tile_x_offset) % tile_map_size_x;
    const tilemap_y: u16 = (pixel_y / tile_size_y) % tile_map_size_y;
    assert(tilemap_x < tile_map_size_x and tilemap_y < tile_map_size_y);

    const tilemap_base_addr: u16 = if(tilemap_addr_type == .map_9800) mem_map.tile_map_9800 else mem_map.tile_map_9C00;
    const tilemap_addr: u16 = tilemap_base_addr + tilemap_x + (tilemap_y * tile_map_size_y);

    const tile_base_addr: u16 = if(lcd_control.bg_window_tile_data == .tile_8800) mem_map.tile_8800 else mem_map.tile_8000;
    const tile_y = state.lcd_y +% scroll_y;

    const signed_mode: bool = tile_base_addr == mem_map.tile_8800;
    const tile_index: u16 = mmu.memory[tilemap_addr];
    const tile_addr_offset: u16 = if(signed_mode) (tile_index + 128) % 256 else tile_index;

    const tile_addr: u16 = tile_base_addr + tile_addr_offset * tile_size_byte;
    const tile_line_addr: u16 = tile_addr + ((tile_y % tile_size_y) * def.byte_per_line);

    return tile_line_addr;
} 

fn mixBackgroundAndObject(bg_pixel: FifoData, obj_pixel: FifoData) FifoData {
    if(obj_pixel.bg_prio == .obj_over_bg) {
        return if(obj_pixel.color_id == color_id_transparent) bg_pixel else obj_pixel;
    } else {
        return if(bg_pixel.color_id == color_id_transparent) obj_pixel else bg_pixel;
    }
}

fn nextObjectIsAtLcdX(state: *State) bool {
    if(state.oam_line_list.isEmpty()) {
        return false;
    }

    const object: FetcherData = state.oam_line_list.peekItem();
    return object.obj_pos_x == state.lcd_overscan_x;
}

fn tryPushPixel(state: *State, mmu: *MMU.State) void {
    if(state.background_fifo.isEmpty()) {
        return;
    }
    assert(state.lcd_overscan_x < def.overscan_width); // we tried to put a pixel outside of the screen.
    assert(state.lcd_y < def.resolution_height); // we tried to put a pixel outside of the screen.

    const obj_pixel: FifoData = state.object_fifo.readItem() orelse transparent_pixel;
    const bg_pixel: FifoData = state.background_fifo.readItem() orelse unreachable;

    const used_pixel: FifoData = mixBackgroundAndObject(bg_pixel, obj_pixel);
    const palette_addr: u16 = used_pixel.palette_addr + used_pixel.palette_index;
    const palette: [def.color_depth]u2 = getPalette(mmu.memory[palette_addr]);
    const color_id: u2 = palette[used_pixel.color_id];

    const color_index: u16 = state.lcd_overscan_x + @as(u16, def.overscan_width) * state.lcd_y;
    state.colorIds[color_index] = color_id;
    state.lcd_overscan_x += 1;
    checkLcdX(state, mmu);
}
