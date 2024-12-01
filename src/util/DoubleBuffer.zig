const std = @import("std");
const assert = std.debug.assert;

const Def = @import("../def.zig");

const Self = @This();

alloc: std.mem.Allocator,
mutex: std.Thread.Mutex = std.Thread.Mutex{},

read_buffer: []i16 = undefined,
write_buffer: []i16 = undefined,
write_index: usize = 0,

test_time: f32 = 0,

pub const Error = error{ Full };

const TEST_SINE_WAVE = false;

pub fn init(alloc: std.mem.Allocator, read_size: usize, write_size: usize) !Self {
    assert(read_size <= write_size);

    const write_data = try alloc.alloc(i16, write_size);
    errdefer alloc.free(write_data);

    const read_data = try alloc.alloc(i16, read_size);
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

pub fn isGettingFull(self: *Self) bool {
    self.mutex.lock();
    defer self.mutex.unlock();

    const fullFactor: f32 = 0.50;
    const fillIndexFloat: f32 = fullFactor * @as(f32, @floatFromInt(self.write_buffer.len));
    const fullIndex: usize = @intFromFloat(fillIndexFloat);

    return self.write_index >= fullIndex;
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

    var fillPercent: f32 = @as(f32, @floatFromInt(self.write_index)) / @as(f32, @floatFromInt(self.write_buffer.len)) * 100.0;
    // std.debug.print("DoubleBuffer: Fill before: {d:.3}%.\n", .{fillPercent});

    // Test sine-wave
    if(TEST_SINE_WAVE) {
        const freq: f32 = 150.0;
        const period: f32 = 1.0 / freq;
        // std.debug.print("DoubleBuffer: Got sine wave!\n", .{});
        for(0..self.read_buffer.len) |i| {
            self.test_time -= if (self.test_time > period) period else 0.0;
            const sine_sample: f32 = std.math.sin(2.0 * std.math.pi * self.test_time / period);
            const sine_int: i16 = @intFromFloat(0.5 * (((sine_sample + 1.0) / 2.0) * 65535.0 - 32768.0));
            self.test_time += 1.0 / @as(f32, @floatFromInt(Def.SAMPLE_RATE));
            self.read_buffer[i] = sine_int;
        }
        return;
    }

    // not enough samples yet.
    if(self.write_index < self.read_buffer.len) {
        // std.debug.print("DoubleBuffer: Not enough samples yet.\n", .{});
        @memset(self.read_buffer, 1);
    }
    else {
        // std.debug.print("DoubleBuffer: Enough samples.\n", .{});
        for(0..self.read_buffer.len) |i| {
            self.read_buffer[i] = self.write_buffer[i];
        }
        // TODO: We need to do this copy, because we are reading the oldest samples in the write_buffer, and by subtracting the write_index would otherwise overwrite valid samples.
        // Better use a ring buffer.
        for((self.read_buffer.len + 1)..self.write_index) |i| {
            self.write_buffer[i] = self.write_buffer[i - self.read_buffer.len - 1];
        } 
        self.write_index -= self.read_buffer.len;


        fillPercent = @as(f32, @floatFromInt(self.write_index)) / @as(f32, @floatFromInt(self.write_buffer.len)) * 100.0;
        // std.debug.print("DoubleBuffer: Fill after: {d:.3}%.\n", .{fillPercent});
    }

    // for(0..self.read_buffer.len) |i| {
    //     std.debug.print("{d}, ", .{self.read_buffer[i]});
    // }

    // TOOD: Just print out the audio data but don't play it!
    // @memset(self.read_buffer, 0);
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
