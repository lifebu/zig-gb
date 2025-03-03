const std = @import("std");

pub const State = struct {
    // TODO: For CLI it is better to that the user can define absolut or relative paths. This right now only supports absolute paths 
    // It would also be very convenient to have a config file where I can put CLI + configs (in this class?).
    dumpFile: ?[]const u8 = null,
};

// TODO: Consider using a zig cli library or try to create a simple one myself?
pub fn init(state: *State, alloc: std.mem.Allocator) void {
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    _ = args.next(); // The file itself, we don't need that
    state.dumpFile = args.next(); 
    if(state.dumpFile) |dumpFile| {
        state.dumpFile = std.fs.cwd().realpathAlloc(alloc, dumpFile) catch unreachable;
    }
}

pub fn deinit(state: *State, alloc: std.mem.Allocator) void {
    if(state.dumpFile) |dumpFile| {
        alloc.free(dumpFile);
    }
}
