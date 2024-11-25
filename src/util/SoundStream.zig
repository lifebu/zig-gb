const std = @import("std");
const sf = struct {
    usingnamespace @import("sfml");
};

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

    sf.c.sfSoundStream_setVolume(self.soundStream, 10.0);
    // sf.c.sfSoundStream_setLoop(self.soundStream, @intFromBool(true));

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
        // TODO: The sound stream is completly broken, at some point it just stops using the callback to get new data, but it is in the playing state.
        //sf.c.sfSoundStream_play(self.soundStream);
    }
}

export fn soundStreamOnGetData(chunk: ?*sf.c.sfSoundStreamChunk, any: ?*anyopaque) sf.c.sfBool {
    const samples: *DoubleBuffer = if (any != null) @alignCast(@ptrCast(any.?)) else unreachable;
    if(chunk == null) unreachable;

    samples.swap();
    chunk.?.samples = @ptrCast(&samples.read_buffer);
    chunk.?.sampleCount = @intCast(samples.read_index);

    if(samples.read_index == 0) {
        std.debug.print("Warning! Soundstream ran out of data!\n", .{});
        return @intFromBool(false);
    }
    else {
        std.debug.print("Soundstream got juicy data!\n", .{});
    }

    return @intFromBool(true);
}

export fn soundStreamOnSeek(_: sf.c.sfTime, _: ?*anyopaque) void {
    // Not needed.
}
