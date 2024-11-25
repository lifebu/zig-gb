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
    const self = Self{ 
        .alloc = alloc,
        .write_buffer = try alloc.alloc(i16, size),
        .read_buffer = try alloc.alloc(i16, size),
    };
    @memset(self.write_buffer, 0);
    @memset(self.read_buffer, 0);

    return self;
}

pub fn deinit(self: *Self) void {
    self.alloc.free(self.write_buffer);
    self.alloc.free(self.read_buffer);
}

pub fn isFull(self: *Self) bool {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.write_index >= self.write_buffer.len;
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

    if(self.write_index == 0) {
        std.debug.print("buffer is empty, no swapping!\n", .{});
        self.read_index = 0;
        return;
    }

    self.read_buffer = self.write_buffer[0..self.write_index - 1];
    self.read_index = self.write_index;
    self.write_index = 0;

    // var num_zero: u32 = 0;
    // var num_non_zero: u32 = 0;
    // for(self.read_buffer[0..self.read_index - 1]) |val| {
    //     if(val == 0) {
    //         num_zero += 1;
    //     } else {
    //         num_non_zero += 1;
    //     }
    //     std.debug.print("{d}, ", .{val});
    // }
    // std.debug.print("\n", .{});
    //
    // std.debug.print("non-zeroes: {d}\n", .{num_non_zero});
}

/// write slice into buffer. returns error when full.
pub fn write(self: *Self, values: []const i16) Error!void {
    //std.debug.print("Wrote samples!\n", .{});
    self.mutex.lock();
    defer self.mutex.unlock();

    // TODO: We need an easier to understand way to describe when the buffer is full.
    // len + 1 leads to so many places where I need - 1.
    if(self.write_index + values.len >= self.write_buffer.len + 1) {
        return Error.Full;
    }

    @memcpy(self.write_buffer[self.write_index..(self.write_index + values.len)], values[0..values.len]);
    self.write_index += values.len;
}
