const std = @import("std");

const Self = @This();

memory: []u8 = undefined,
allocator: std.mem.Allocator,

pub fn init(alloc: std.mem.Allocator, gbFile: ?[]const u8) !Self {
    var self = Self{ .allocator = alloc };

    self.memory = try alloc.alloc(u8, 0x10000);
    errdefer alloc.free(self.memory);
    @memset(self.memory, 0);
    if (gbFile) |file| {
        _ = try std.fs.cwd().readFile(file, self.memory);
    }

    return self;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.memory);
}

// TODO: How can I support the current way the cpu wants to read/write?
pub fn read8(self: *Self, addr: u16) u8 {
   return self.memory[addr];
}

pub fn write8(self: *Self, addr: u16, val: u8) void {
   self.memory[addr] = val; 
}

pub fn read16(self: *Self, addr: u16) u16 {
   return self.memory[addr];
}

pub fn write16(self: *Self, addr: u16, val: u16) void {
   self.memory[addr] = val; 
}
