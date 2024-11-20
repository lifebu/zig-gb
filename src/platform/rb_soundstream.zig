const std = @import("std");
const sf = struct {
    usingnamespace @import("sfml");
};

const Def = @import("../def.zig");

const Self = @This();

alloc: std.mem.Allocator,
samples: *std.RingBuffer = undefined,
soundStream: ?*sf.c.sfSoundStream = null,

pub fn init(alloc: std.mem.Allocator) !Self {
    var self = Self{ .alloc = alloc };

    self.samples = try alloc.create(std.RingBuffer);
    errdefer alloc.destroy(self.samples);

    self.samples.* = try std.RingBuffer.init(alloc, Def.NUM_SAMPLES * Def.NUM_CHANNELS);

    const newStream = sf.c.sfSoundStream_create(soundStreamOnGetData, soundStreamOnSeek, Def.NUM_CHANNELS, Def.NUM_SAMPLES, @ptrCast(self.samples));

    if (newStream) |stream| {
        self.soundStream = stream;
    } else return std.mem.Allocator.Error.OutOfMemory;

    return self;
}

pub fn deinit(self: *Self) void {
    self.samples.deinit(self.alloc);
    self.alloc.destroy(self.samples);

    if (self.soundStream) |stream| {
        sf.c.sfSoundStream_destroy(stream);
    }
}

pub fn play(self: *Self) void {
    sf.c.sfSoundStream_play(self.soundStream);
}

export fn soundStreamOnGetData(_: ?*sf.c.sfSoundStreamChunk, any: ?*anyopaque) sf.c.sfBool {
    // TODO: This is not threadsafe!
    const samples: *align(1) std.RingBuffer = if (any != null) @ptrCast(any.?) else unreachable;
    std.debug.print("Audio wanted to have data: Read: {d}, Write: {d}, Len: {d}\n", .{ samples.read_index, samples.write_index, samples.data.len });
    return @intFromBool(true);
}

export fn soundStreamOnSeek(_: sf.c.sfTime, _: ?*anyopaque) void {
    // Not needed.
}
