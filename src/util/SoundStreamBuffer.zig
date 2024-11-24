const std = @import("std");
const assert = std.debug.assert;

// TODO: Clean this up :/
const Self = @This();

alloc: std.mem.Allocator,
/// read_buffer contains the content of the last read.
read_buffer: []i16 = undefined,
buffer: []i16 = undefined,
read_index: usize = 0,
write_index: usize = 0,
/// protects the buffer, read_index and write_index
mutex: std.Thread.Mutex = std.Thread.Mutex{},

pub fn init(alloc: std.mem.Allocator, size: usize) !Self {
    const buffer_bytes = try alloc.alloc(i16, size);
    const read_buffer_bytes = try alloc.alloc(i16, size);
    return Self {
        .alloc = alloc,
        .buffer = buffer_bytes,
        .read_buffer = read_buffer_bytes,
    };
}

pub fn deinit(self: *Self) void {
    self.alloc.free(self.buffer);
    self.alloc.free(self.read_buffer);
}

pub fn isFull(self: *Self) bool {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.mask2(self.write_index + self.read_index) == self.read_index;
}

pub fn isEmpty(self: *Self) bool {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.write_index == self.read_index;
}

pub fn len(self: *Self) usize {
    self.mutex.lock();
    defer self.mutex.unlock();

    const wrap_offset = 2 * self.buffer.len * @intFromBool(self.write_index < self.read_index);
    const adjusted_write_index = self.write_index + wrap_offset;
    return adjusted_write_index - self.read_index;
}

pub fn fillReadBuffer(self: *Self) usize {
    self.mutex.lock();
    defer self.mutex.unlock();

    const length = self.len();

    const slice1_start = self.mask(self.read_index);
    const slice1_end = @min(self.buffer.len, slice1_start + length);
    const slice1: []i16 = self.buffer[slice1_start..slice1_end];
    const slice2: []i16 = self.buffer[0..length - slice1.len];

    @memcpy(self.read_buffer[0..slice1.len], slice1);
    @memcpy(self.read_buffer[slice1.len..][0..slice2.len], slice2);

    self.read_index = self.mask2(self.read_index + length);
    return length;
}

/// write `byte` into buffer. if the buffer is full, oldest byte is overwritten.
pub fn write(self: *Self, val: i16) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.buffer[self.mask(self.write_index)] = val;
    self.write_index = self.mask2(self.write_index + 1);
}

/// returns `index` modulo the length of the backing slice.
fn mask(self: Self, index: usize) usize {
    return index % self.buffer.len;
}

/// returns `index` modulo twice the length of the backing slice.
fn mask2(self: Self, index: usize) usize {
    return index % (2 * self.buffer.len);
}

