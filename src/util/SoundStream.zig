const std = @import("std");
const sf = struct {
    usingnamespace @import("sfml");
};

const Def = @import("../def.zig");
const DoubleBuffer = @import("DoubleBuffer.zig");

const Self = @This();

alloc: std.mem.Allocator,
samples: *DoubleBuffer = undefined,
soundStream: *sf.c.sfSoundStream = undefined,

pub fn init(alloc: std.mem.Allocator, comptime sample_size: usize, comptime sample_rate: usize, comptime num_channels: usize) !Self {
    var self = Self{ .alloc = alloc};

    self.samples = try alloc.create(DoubleBuffer);
    errdefer alloc.destroy(self.samples);

    self.samples.* = try DoubleBuffer.init(alloc, sample_size * num_channels);
    errdefer self.samples.deinit();

    const newStream = sf.c.sfSoundStream_create(soundStreamOnGetData, soundStreamOnSeek, num_channels, sample_rate, @ptrCast(self.samples));
    if (newStream) |stream| {
        self.soundStream = stream;
    } else return std.mem.Allocator.Error.OutOfMemory;

    sf.c.sfSoundStream_setVolume(self.soundStream, 5.0);
    sf.c.sfSoundStream_play(self.soundStream);

    // Test sine-wave
    // const freq: f32 = 700.0;
    // const period: f32 = 1.0 / freq;
    // var time: f32 = 0.0;
    // for(0..self.samples.read_buffer.len) |i| {
    //     time -= if (time > period) period else 0.0;
    //     const sine_sample: f32 = std.math.sin(2.0 * std.math.pi * time / period);
    //     const sine_int: i16 = @intFromFloat(0.5 * (((sine_sample + 1.0) / 2.0) * 65535.0 - 32768.0));
    //     time += 1.0 / @as(f32, @floatFromInt(Def.SAMPLE_RATE));
    //     self.samples.read_buffer[i] = sine_int;
    // }
    // self.samples.read_index = self.samples.read_buffer.len;

    return self;
}

pub fn deinit(self: *Self) void {
    self.samples.deinit();
    self.alloc.destroy(self.samples);
    sf.c.sfSoundStream_destroy(self.soundStream);
}

pub fn update(self: *Self) void {
    const soundStatus: sf.audio.SoundStatus = @enumFromInt(sf.c.sfSoundStream_getStatus(self.soundStream));
    if(soundStatus == .stopped or soundStatus == .paused) {
    }

    // TODO: This horrible hack forces the soundstream to play even though it says it is playing but it is not :/
    // sf.c.sfSoundStream_play(self.soundStream);
}

export fn soundStreamOnGetData(chunk: ?*sf.c.sfSoundStreamChunk, any: ?*anyopaque) sf.c.sfBool {
    const samples: *DoubleBuffer = if (any != null) @alignCast(@ptrCast(any.?)) else unreachable;
    if(chunk == null) unreachable;

    // TODO: For some reason, the sound stream no longer tries to get data after the first 3 times.
    samples.swap();
    chunk.?.samples = @ptrCast(samples.read_buffer.ptr);
    chunk.?.sampleCount = @intCast(samples.read_index);
    return @intFromBool(true);
}

export fn soundStreamOnSeek(_: sf.c.sfTime, _: ?*anyopaque) void {
    // Not needed.
}
