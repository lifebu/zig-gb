const std = @import("std");

const def = @import("defines.zig");

pub const State = struct {
    memory: [def.addr_space]u8 = [1]u8{0} ** def.addr_space,
};

pub fn init(_: *State) void {
}

pub fn loadDump(state: *State, path: []const u8) void {
    const file = std.fs.openFileAbsolute(path, .{}) catch unreachable;
    const len = file.readAll(&state.memory) catch unreachable;
    std.debug.assert(len == state.memory.len);
}

pub fn cycle(_: *State) void {
}
