const std = @import("std");

const def = @import("defines.zig");

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

pub fn getFileType(path: []const u8) def.FileType {
    // TODO: This should be handled in the cli itself. But this is easier for now :)
    var file_extension: []const u8 = undefined;
    var iter = std.mem.splitScalar(u8, path, '.');
    while(iter.peek() != null) {
        file_extension = iter.next().?;
    }

    if (std.mem.eql(u8, file_extension, "dump")) {
        return .dump;
    } else if (std.mem.eql(u8, file_extension, "gb")) {
        return .gameboy;
    }
    return .unknown;
}
