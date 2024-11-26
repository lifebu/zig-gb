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

const NUM_ZERO_SAMPLES = 10;

pub fn init(alloc: std.mem.Allocator, size: usize) !Self {
    const write_data = try alloc.alloc(i16, size);
    errdefer alloc.free(write_data);

    const read_data = try alloc.alloc(i16, size);
    errdefer alloc.free(read_data);

    @memset(write_data, 0);
    @memset(read_data, 0);

    const self = Self{ 
        .alloc = alloc,
        .write_buffer = write_data,
        .read_buffer = read_data,
    };
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
        std.debug.print("buffer is empty, returning empty!\n", .{});
        // TODO: Can this be done with some std function?
        for (0..NUM_ZERO_SAMPLES) |i| {
            self.read_buffer[i] = 0;
        }
        self.read_index = NUM_ZERO_SAMPLES;
        return;
    }

    std.debug.print("buffer had juicy data!\n", .{});
    // TODO: Can this be done with some std function?
    for(0..self.write_index) |i| {
        self.read_buffer[i] = self.write_buffer[i];
    }
    self.read_index = self.write_index;
    self.write_index = 0;
}

/// write slice into buffer. returns error when full.
pub fn write(self: *Self, values: []const i16) Error!void {
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
