const std = @import("std");

const def = @import("defines.zig");

pub const State = struct {
    memory: [def.addr_space]u8 = [1]u8{0} ** def.addr_space,
};

pub fn init(state: *State) void {
    // Some test memory dump.
    const result = std.fs.cwd().readFile("playground/castlevania.dump", &state.memory) catch unreachable;
    std.debug.assert(result.len == state.memory.len);
}

pub fn cycle(_: *State) void {
}
