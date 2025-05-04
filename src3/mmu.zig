const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

const MemoryRequest = struct {
    read: ?u16 = null,
    write: ?u16 = null,
    data: u8 = 0,

    const Self = @This();
    pub fn print(self: *Self) []u8 {
        var buf: [3]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{s}{s}{s}", .{ 
            if(self.read == null) "-" else "R", 
            if(self.write == null) "-" else "W", 
            if(self.read == null and self.write == null) "-" else "M" 
        }) catch unreachable;
        return &buf;
    }
    pub fn getAddress(self: *Self) u16 {
        return if(self.read != null) self.read.? 
            else if(self.write != null) self.write.? 
            else 0;
    }
};

pub const State = struct {
    memory: [def.addr_space]u8 = [1]u8{0} ** def.addr_space,
    request: MemoryRequest = .{},
};

pub fn init(_: *State) void {
}

pub fn loadDump(state: *State, path: []const u8) void {
    // TODO: This should be handled in the cli itself. But this is easier for now :)
    var file_extension: []const u8 = undefined;
    var iter = std.mem.splitScalar(u8, path, '.');
    while(iter.peek() != null) {
        file_extension = iter.next().?;
    }

    if (std.mem.eql(u8, file_extension, "dump")) {
        const file = std.fs.openFileAbsolute(path, .{}) catch unreachable;
        const len = file.readAll(&state.memory) catch unreachable;
        std.debug.assert(len == state.memory.len);
    } else if (std.mem.eql(u8, file_extension, "gb")) {
        const file = std.fs.openFileAbsolute(path, .{}) catch unreachable;
        const len = file.readAll(state.memory[mem_map.rom_low..mem_map.rom_high]) catch unreachable;
        std.debug.assert(len == mem_map.rom_high - mem_map.rom_low);
    }
}

pub fn cycle(state: *State) void {
    if(state.request.read) |address| {
        state.request.data = state.memory[address];
    }
    if(state.request.write) |address| {
        state.memory[address] = state.request.data;
    }
}
