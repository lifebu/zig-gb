const std = @import("std");
const sf = struct {
    usingnamespace @import("sfml");
};

const DoubleBuffer = @import("DoubleBuffer.zig");

const Self = @This();

alloc: std.mem.Allocator,
samples: *DoubleBuffer = undefined,
soundStream: *sf.c.sfSoundStream = undefined,

/// sfml soundstreams require a minimum amount of samples to give them. If we return less samples, the thread might crash.
const MIN_SAMPLES_MS = 15;

pub fn init(alloc: std.mem.Allocator, comptime sample_rate: usize, comptime num_channels: usize) !Self {
    var self = Self{ .alloc = alloc};

    self.samples = try alloc.create(DoubleBuffer);
    errdefer alloc.destroy(self.samples);

    const min_samples = MIN_SAMPLES_MS * ((sample_rate * num_channels) / 1_000);
    self.samples.* = try DoubleBuffer.init(alloc, min_samples, min_samples * 4);
    errdefer self.samples.deinit();

    const newStream = sf.c.sfSoundStream_create(soundStreamOnGetData, soundStreamOnSeek, num_channels, sample_rate, @ptrCast(self.samples));
    if (newStream) |stream| {
        self.soundStream = stream;
    } else return std.mem.Allocator.Error.OutOfMemory;

    sf.c.sfSoundStream_setVolume(self.soundStream, 5.0);
    sf.c.sfSoundStream_play(self.soundStream);

    return self;
}

pub fn deinit(self: *Self) void {
    self.samples.deinit();
    self.alloc.destroy(self.samples);
    sf.c.sfSoundStream_destroy(self.soundStream);
}

pub fn isPlaying(self: Self) bool {
    const soundStatus: sf.audio.SoundStatus = @enumFromInt(sf.c.sfSoundStream_getStatus(self.soundStream));
    return soundStatus == .playing;
}

export fn soundStreamOnGetData(chunk: ?*sf.c.sfSoundStreamChunk, any: ?*anyopaque) sf.c.sfBool {
    const samples: *DoubleBuffer = if (any != null) @alignCast(@ptrCast(any.?)) else unreachable;
    if(chunk == null) unreachable;

    samples.swap();
    chunk.?.samples = @ptrCast(samples.read_buffer.ptr);
    chunk.?.sampleCount = @intCast(samples.read_buffer.len);
    return @intFromBool(true);
}

export fn soundStreamOnSeek(_: sf.c.sfTime, _: ?*anyopaque) void {
    // Not needed.
}
