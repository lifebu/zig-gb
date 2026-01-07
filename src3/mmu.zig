const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

pub const State = struct {
    memory: [def.addr_space]u8 = .{0} ** def.addr_space,
};

pub fn init(_: *State) void {
}

pub fn request(_: *State, req: *def.Request) void {
    switch (req.address) {
        mem_map.unused_low...(mem_map.unused_high - 1) => {
            req.reject();
        },
        else => {
            if (req.isValid()) std.log.warn("r/w lost: {f}", .{ req });
            req.reject();
        }
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

pub fn loadDump(state: *State, path: []const u8, file_type: def.FileType) void {
    switch(file_type) {
        .gameboy => {
            const file = std.fs.openFileAbsolute(path, .{}) catch unreachable;
            const len = file.readAll(state.memory[mem_map.rom_low..mem_map.rom_high]) catch unreachable;
            std.debug.assert(len == mem_map.rom_high - mem_map.rom_low);
        },
        .dump => {
            const file = std.fs.openFileAbsolute(path, .{}) catch unreachable;
            const len = file.readAll(&state.memory) catch unreachable;
            std.debug.assert(len == state.memory.len);
        },
        .unknown => {
        }
    }
}
