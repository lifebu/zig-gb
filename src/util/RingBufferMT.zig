//! Simple variant of std.RingBuffer that is threadsafe by using a mutex before each call.

const std = @import("std");

const Self = @This();

alloc: std.mem.Allocator,
buffer: std.RingBuffer = undefined,
mutex: std.Thread.Mutex = std.Thread.Mutex{},

/// Allocate a new `RingBuffer`; `deinit()` should be called to free the buffer.
pub fn init(alloc: std.mem.Allocator, capacity: usize) !Self {
    var self = Self{ .alloc = alloc };

    self.buffer = try std.RingBuffer.init(alloc, capacity);
    errdefer self.buffer.deinit(self.alloc);

    return self;
}

/// Free the data backing a `RingBuffer`; must be passed the same `Allocator` as
/// `init()`.
pub fn deinit(self: *Self) void {
    self.buffer.deinit(self.alloc);
}

/// Returns `index` modulo the length of the backing slice.
pub fn mask(self: *Self, index: usize) usize {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.mask(index);
}

/// Returns `index` modulo twice the length of the backing slice.
pub fn mask2(self: *Self, index: usize) usize {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.mask2(index);
}

/// Write `byte` into the ring buffer. Returns `error.Full` if the ring
/// buffer is full.
pub fn write(self: *Self, byte: u8) std.RingBuffer.Error!void {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.write(byte);
}

/// Write `byte` into the ring buffer. If the ring buffer is full, the
/// oldest byte is overwritten.
pub fn writeAssumeCapacity(self: *Self, byte: u8) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.writeAssumeCapacity(byte);
}

/// Write `bytes` into the ring buffer. Returns `error.Full` if the ring
/// buffer does not have enough space, without writing any data.
/// Uses memcpy and so `bytes` must not overlap ring buffer data.
pub fn writeSlice(self: *Self, bytes: []const u8) std.RingBuffer.Error!void {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.writeSlice(bytes);
}

/// Write `bytes` into the ring buffer. If there is not enough space, older
/// bytes will be overwritten.
/// Uses memcpy and so `bytes` must not overlap ring buffer data.
pub fn writeSliceAssumeCapacity(self: *Self, bytes: []const u8) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.writeSliceAssumeCapacity(bytes);
}

/// Write `bytes` into the ring buffer. Returns `error.Full` if the ring
/// buffer does not have enough space, without writing any data.
/// Uses copyForwards and can write slices from this RingBuffer into itself.
pub fn writeSliceForwards(self: *Self, bytes: []const u8) std.RingBuffer.Error!void {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.writeSliceForwards(bytes);
}

/// Write `bytes` into the ring buffer. If there is not enough space, older
/// bytes will be overwritten.
/// Uses copyForwards and can write slices from this RingBuffer into itself.
pub fn writeSliceForwardsAssumeCapacity(self: *Self, bytes: []const u8) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.writeSliceForwardsAssumeCapacity(bytes);
}

/// Consume a byte from the ring buffer and return it. Returns `null` if the
/// ring buffer is empty.
pub fn read(self: *Self) ?u8 {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.read();
}

/// Consume a byte from the ring buffer and return it; asserts that the buffer
/// is not empty.
pub fn readAssumeLength(self: *Self) u8 {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.readAssumeLength();
}

/// Reads first `length` bytes written to the ring buffer into `dest`; Returns
/// Error.ReadLengthInvalid if length greater than ring or dest length
/// Uses memcpy and so `dest` must not overlap ring buffer data.
pub fn readFirst(self: *Self, dest: []u8, length: usize) std.RingBuffer.Error!void {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.readFirst(dest, length);
}

/// Reads first `length` bytes written to the ring buffer into `dest`;
/// Asserts that length not greater than ring buffer or dest length
/// Uses memcpy and so `dest` must not overlap ring buffer data.
pub fn readFirstAssumeLength(self: *Self, dest: []u8, length: usize) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.readFirstAssumeLength(dest, length);
}

/// Reads last `length` bytes written to the ring buffer into `dest`; Returns
/// Error.ReadLengthInvalid if length greater than ring or dest length
/// Uses memcpy and so `dest` must not overlap ring buffer data.
/// Reduces write index by `length`.
pub fn readLast(self: *Self, dest: []u8, length: usize) std.RingBuffer.Error!void {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.readLast(dest, length);
}

/// Reads last `length` bytes written to the ring buffer into `dest`;
/// Asserts that length not greater than ring buffer or dest length
/// Uses memcpy and so `dest` must not overlap ring buffer data.
/// Reduces write index by `length`.
pub fn readLastAssumeLength(self: *Self, dest: []u8, length: usize) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.readLastAssumeLength(dest, length);
}

/// Returns `true` if the ring buffer is empty and `false` otherwise.
pub fn isEmpty(self: *Self) bool {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.isEmpty();
}

/// Returns `true` if the ring buffer is full and `false` otherwise.
pub fn isFull(self: *Self) bool {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.isFull();
}

/// Returns the length of data available for reading
pub fn len(self: *Self) usize {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.len();
}

/// Returns a `Slice` for the region of the ring buffer starting at
/// `self.mask(start_unmasked)` with the specified length.
pub fn sliceAt(self: *Self, start_unmasked: usize, length: usize) std.RingBuffer.Slice {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.sliceAt(start_unmasked, length);
}

/// Returns a `Slice` for the last `length` bytes written to the ring buffer.
/// Does not check that any bytes have been written into the region.
pub fn sliceLast(self: *Self, length: usize) std.RingBuffer.Slice {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.buffer.sliceLast(length);
}
