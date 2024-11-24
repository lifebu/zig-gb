const std = @import("std");
const sf = struct {
    usingnamespace @import("sfml");
};

const SoundStreamBuffer = @import("SoundStreamBuffer.zig");

const Self = @This();

alloc: std.mem.Allocator,
samples: *SoundStreamBuffer = undefined,
soundStream: *sf.c.sfSoundStream = undefined,

pub fn init(alloc: std.mem.Allocator, comptime sample_size: usize, comptime num_channels: usize) !Self {
    var self = Self{ .alloc = alloc};

    self.samples = try alloc.create(SoundStreamBuffer);
    errdefer alloc.destroy(self.samples);
    self.samples.* = try SoundStreamBuffer.init(alloc, sample_size * num_channels);
    errdefer self.samples.deinit();

    const newStream = sf.c.sfSoundStream_create(soundStreamOnGetData, soundStreamOnSeek, num_channels, sample_size, @ptrCast(self.samples));
    if (newStream) |stream| {
        self.soundStream = stream;
    } else return std.mem.Allocator.Error.OutOfMemory;

    return self;
}

pub fn deinit(self: *Self) void {
    self.samples.deinit();
    self.alloc.destroy(self.samples);
    sf.c.sfSoundStream_destroy(self.soundStream);
}

pub fn update(self: *Self) void {
    // restart the sound stream if it ran out, if we have some samples again.
    if(self.samples.isEmpty()) {
        return;
    }

    const soundStatus: sf.audio.SoundStatus = @enumFromInt(sf.c.sfSoundStream_getStatus(self.soundStream));
    if(soundStatus == .stopped or soundStatus == .paused) {
        sf.c.sfSoundStream_play(self.soundStream);
    }
}

export fn soundStreamOnGetData(chunk: ?*sf.c.sfSoundStreamChunk, any: ?*anyopaque) sf.c.sfBool {
    const samples: *SoundStreamBuffer = if (any != null) @alignCast(@ptrCast(any.?)) else unreachable;
    if(chunk == null) unreachable;

    const length = samples.fillReadBuffer();
    chunk.?.samples = @ptrCast(&samples.read_buffer);
    chunk.?.sampleCount = @intCast(length);

    if(length == 0) {
        std.debug.print("Warning! Soundstream ran out of data!\n", .{});
        return @intFromBool(false);
    }

    return @intFromBool(true);
}

export fn soundStreamOnSeek(_: sf.c.sfTime, _: ?*anyopaque) void {
    // Not needed.
}
