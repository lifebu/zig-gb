const std = @import("std");

const sf = struct {
    usingnamespace @import("sfml");
    usingnamespace sf.graphics;
};

pub const PPU = struct {
    const Self = @This();

    bla: u8 = 0,

    pub fn updatePixels(self: *Self, memory: *[]u8, pixels: *[]sf.Color) !void {
        memory.*[0] = self.bla;
        pixels.*[0] = sf.Color.Cyan;
    }
};
