const std = @import("std");
const assert = std.debug.assert;

const Self = @This();

alloc: std.mem.Allocator,
mutex: std.Thread.Mutex = std.Thread.Mutex{},

read_buffer: []i16 = undefined,
read_index: usize = 0,
write_buffer: []i16 = undefined,
write_index: usize = 0,

pub const Error = error{ Full };

pub fn init(alloc: std.mem.Allocator, size: usize) !Self {
    return Self {
        .alloc = alloc,
        .write_buffer = try alloc.alloc(i16, size),
        .read_buffer = try alloc.alloc(i16, size),
    };
}

pub fn deinit(self: *Self) void {
    self.alloc.free(self.write_buffer);
    self.alloc.free(self.read_buffer);
}

pub fn isFull(self: *Self) bool {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.write_index >= self.write_buffer.len - 1;
}

pub fn isEmpty(self: *Self) bool {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.write_index == 0;
}

// override read_buffer with content of write_buffer. resets write_index.
pub fn swap(self: *Self) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.read_buffer = self.write_buffer[0..self.write_index];
    self.read_index = self.write_index;
    self.write_index = 0;
}

/// write `byte` into buffer. returns error when full.
pub fn write(self: *Self, val: i16) Error!void {
    self.mutex.lock();
    defer self.mutex.unlock();

    if(self.isFull()) {
        return Error.Full;
    }

    self.write_buffer[self.write_index] = val;
    self.write_index += 1;
}
