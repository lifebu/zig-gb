const std = @import("std");

const def = @import("defines.zig");
const Platform = @import("platform.zig");

const state = struct {
    var platform: Platform.State = .{};

    var color2bpp: [def.NUM_2BPP]u8 = [40]u8{  
        0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 16, 16, 17, 17, 18, 18, 19, 19, 
    } ** 144;
};

export fn init() void {
    Platform.init(&state.platform);
}

export fn frame() void {
    Platform.frame(&state.platform, state.color2bpp);
}

export fn cleanup() void {
    Platform.cleanup();
}

pub fn main() void {
    Platform.run(init, frame, cleanup);
}
