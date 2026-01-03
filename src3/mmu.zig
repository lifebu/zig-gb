const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

pub const State = struct {
    memory: [def.addr_space]u8 = [1]u8{0} ** def.addr_space,
};

pub fn init(state: *State) void {
    // TODO: Need to moved somewhere else once mmu is gone.
    state.memory[mem_map.serial_data] = 0xFF; // Stubbed.
    state.memory[mem_map.serial_control] = 0x7E; // Stubbed.
}

pub fn cycle(_: *State) void {
}

pub fn request(state: *State, req: *def.Request) void {
    req.apply(&state.memory[req.address]);
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
