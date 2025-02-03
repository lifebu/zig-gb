const std = @import("std");

const def = @import("defines.zig");
const Platform = @import("platform.zig");

const PPUMode = enum(u2) {
    H_BLANK,
    V_BLANK,
    OAM_SCAN,
    DRAW,

    pub fn advance(self: *PPUMode, lcd_y: u8) void {
        self.* = switch (self.*) {
            .H_BLANK => if(lcd_y < def.RESOLUTION_HEIGHT - 1) .OAM_SCAN else .V_BLANK,
            .OAM_SCAN => .DRAW,
            .DRAW => .H_BLANK,
            .V_BLANK => .OAM_SCAN,
        };
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

pub fn PixelFifo(comptime T: type) type {
   return struct {
        const Self = @This();

        const FIFO_LENGTH = def.TILE_WIDTH * 2;
        pixels: [FIFO_LENGTH]T = undefined,
        write_idx: usize = 0,
        read_idx: usize = 0,

        pub fn pop(self: *Self) T {
            std.debug.assert(self.read_idx != self.write_idx);

            const value = self.pixels[self.read_idx];
            self.read_idx = (self.read_idx + 1) % FIFO_LENGTH;
            return value;
        }

        pub fn tryPush8(self: *Self, pixels: [def.TILE_WIDTH]T) bool {
            const offset = FIFO_LENGTH * @as(usize, @intFromBool(self.write_idx < self.read_idx));
            const length = self.write_idx + offset - self.read_idx;
            if(length + pixels.len > FIFO_LENGTH) {
                return false;
            }

            inline for(0..pixels.len) |i| {
                self.pixels[self.write_idx] = pixels[i];
                self.write_idx = (self.write_idx + 1) % FIFO_LENGTH;
            }
            return true;
        }
    };
}

const state = struct {
    var platform: Platform.State = .{};

    // MMU
    var memory: [def.ADDR_SPACE]u8 = [1]u8{0} ** def.ADDR_SPACE;

    // APU
    var gb_sample_buffer: [def.NUM_GB_SAMPLES]f32 = [1]f32{ 0.0 } ** def.NUM_GB_SAMPLES;

    // PPU
    var background_fifo: PixelFifo(BackgroundFifoPixel) = .{}; 
    var object_fifo: PixelFifo(ObjectFifoPixel) = .{};
    var ppu_mode: PPUMode = .OAM_SCAN;
    var color2bpp: [def.NUM_2BPP]u8 = [40]u8{  
        0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 16, 16, 17, 17, 18, 18, 19, 19, 
    } ** 144;
};

export fn init() void {
    Platform.init(&state.platform);

    // Some test memory dump.
    const result = std.fs.cwd().readFile("playground/castlevania.dump", &state.memory) catch unreachable;
    std.debug.assert(result.len == state.memory.len);
}

export fn frame() void {
    const T_CYCLES_IN_60FPS = def.SYSTEM_FREQ / 60; // 60FPS
    for(0..T_CYCLES_IN_60FPS) |_| {
        switch(state.ppu_mode) {
            .OAM_SCAN => {},
            .DRAW => {},
            .H_BLANK => {},
            .V_BLANK => {},
        }
        // start pixel fetcher and 
        // ppu pixel fetcher in state 3.

        // changing ppu state:
        const lcd_y = 0;
        state.ppu_mode.advance(lcd_y);

        // H_BLANK = 00, V_BLANK = 01, OAM_SCAN = 10, DRAW = 11
        // =>
        // OAM_SCAN -> DRAW: + 1
        // DRAW -> H_BLANK: +% 1
        // H_BLANK -> OAM_SCAN/V_BLANK: @intFromBool(lcdY < 143) + 1
        // V_BLANK -> OAM_SCAN: + 1 

    }

    Platform.frame(&state.platform, state.color2bpp, state.gb_sample_buffer);
}

export fn cleanup() void {
    Platform.cleanup();
}

pub fn main() void {
    Platform.run(init, frame, cleanup);
}
