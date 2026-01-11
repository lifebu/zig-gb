///! GB PPU Void
///! The void ppu reports the state of the ppu with hardcoded timings.
///! This allows isolate ppu issues from the rest of the system.

const std = @import("std");
const assert = std.debug.assert;

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

const Self = @This();

const dots_per_line: u16 = 456;
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
    lcd_enable: bool = false,
};
pub const LcdStat = packed struct {
    mode: enum(u2) {
        h_blank,
        v_blank,
        oam_scan,
        draw,
    } = .h_blank,
    ly_is_lyc: bool = false,
    mode_0_select: bool = false,
    mode_1_select: bool = false,
    mode_2_select: bool = false,
    lyc_select: bool = false,
    _: u1 = 0,
};

lcd_control: LcdControl = .{},
lcd_stat: LcdStat = .{},
lcd_y_compare: u8 = 0,
lcd_y: u8 = 0, 

ly_counter: u16 = 0,

// TODO: Make this array of u2 instead?
// TODO: rename to color_ids (naming convention)
colorIds: [def.overscan_resolution]u8 = def.default_color_ids,

pub fn init(self: *Self) void {
    self.* = .{};
}

pub fn cycle(self: *Self, _: *[def.addr_space]u8) struct{ bool, bool } {
    var irq_stat: bool = false;
    var irq_vblank: bool = false;

    if(!self.lcd_control.lcd_enable) {
        return .{ irq_vblank, irq_stat };
    }

    self.ly_counter += 1;
    if(self.ly_counter >= dots_per_line) {
        self.ly_counter = 0;

        self.lcd_y = (self.lcd_y + 1) % max_lcd_y;
        irq_vblank = self.lcd_y == 144;
    }

    const old_mode = self.lcd_stat.mode;
    if(self.lcd_y > 143) {
        self.lcd_stat.mode = .v_blank;
        if(self.lcd_stat.mode != old_mode) {
            irq_stat |= self.lcd_stat.mode_1_select;
        }
    } else if (self.ly_counter <= 80) {
        self.lcd_stat.mode = .oam_scan;
        if(self.lcd_stat.mode != old_mode) {
            irq_stat |= self.lcd_stat.mode_2_select;
        }
    } else if (self.ly_counter > 80 and self.ly_counter <= 252) {
        self.lcd_stat.mode = .draw;
    } else if (self.ly_counter > 252) {
        self.lcd_stat.mode = .h_blank;
        if(self.lcd_stat.mode != old_mode) {
            irq_stat |= self.lcd_stat.mode_0_select;
        }
    }

    self.lcd_stat.ly_is_lyc = self.lcd_y == self.lcd_y_compare;
    const lyc_stat: bool = self.lcd_stat.lyc_select and self.lcd_stat.ly_is_lyc;
    irq_stat |= lyc_stat;

    return .{ irq_vblank, irq_stat };
}

pub fn request(self: *Self, memory: *[def.addr_space]u8, req: *def.Request) void {
    switch(req.address) {
        mem_map.lcd_control => {
            req.apply(&self.lcd_control);
            if(req.isWrite()) {
                if(!self.lcd_control.lcd_enable) {
                    self.lcd_stat.mode = .h_blank;
                    self.lcd_y = 0;
                }
            }
        },
        mem_map.lcd_stat => {
            req.applyAllowedRW(&self.lcd_stat, 0xFF, 0xF8);
        },
        mem_map.lcd_y => {
            req.applyAllowedRW(&self.lcd_y, 0xFF, 0x00);
        },
        mem_map.lcd_y_compare => {
            req.apply(&self.lcd_y_compare);
        },
        mem_map.scroll_x => {
            req.apply(&memory[req.address]);
        },
        mem_map.scroll_y => {
            req.apply(&memory[req.address]);
        },
        mem_map.window_x => {
            req.apply(&memory[req.address]);
        },
        mem_map.window_y => {
            req.apply(&memory[req.address]);
        },
        mem_map.oam_low...(mem_map.oam_high - 1) => {
            const mask: u8 = if(self.lcd_stat.mode == .oam_scan or self.lcd_stat.mode == .draw) 0x00 else 0xFF;
            if(mask == 0x00) {
                std.log.warn("OAM access denied: visual glitches will occur (Mode: {}, Line: {}). {f}", .{ self.lcd_stat.mode, self.lcd_y, req });
            }
            req.applyAllowedRW(&memory[req.address], mask, mask);
        },
        mem_map.vram_low...(mem_map.vram_high - 1) => {
            const mask: u8 = if(self.lcd_stat.mode == .draw) 0x00 else 0xFF;
            if(mask == 0x00) {
                std.log.warn("VRAM access denied: visual glitches will occur (Mode: {}, Line: {}). {f}", .{ self.lcd_stat.mode, self.lcd_y, req });
            }
            req.applyAllowedRW(&memory[req.address], mask, mask);
        },
        mem_map.bg_palette => {
            req.apply(&memory[req.address]);
        },
        mem_map.obj_palette_0 => {
            req.apply(&memory[req.address]);
        },
        mem_map.obj_palette_1 => {
            req.apply(&memory[req.address]);
        },
        else => {},
    }
}
