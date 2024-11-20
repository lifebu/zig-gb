const std = @import("std");
const sf = struct {
    usingnamespace @import("sfml");
};

const Def = @import("../def.zig");

const Self = @This();

alloc: std.mem.Allocator,
samples: std.RingBuffer = undefined,
soundStream: ?*sf.c.sfSoundStream = null,

pub fn init(alloc: std.mem.Allocator) !Self {
    var self = Self{ .alloc = alloc };

    self.samples = try std.RingBuffer.init(alloc, Def.NUM_SAMPLES * Def.NUM_CHANNELS);
    errdefer self.samples.deinit();

    return self;
}

pub fn deinit(self: *Self) void {
    self.samples.deinit(self.alloc);
    if (self.soundStream) |stream| {
        sf.c.sfSoundStream_destroy(stream);
    }
}

pub fn play(self: *Self) std.mem.Allocator.Error!void {
    const newStream = sf.c.sfSoundStream_create(soundStreamOnGetData, soundStreamOnSeek, Def.NUM_CHANNELS, Def.NUM_SAMPLES, @ptrCast(self));

    if (newStream) |stream| {
        self.soundStream = stream;
    } else return std.mem.Allocator.Error.OutOfMemory;

    sf.c.sfSoundStream_play(self.soundStream);
}

export fn soundStreamOnGetData(_: ?*sf.c.sfSoundStreamChunk, any: ?*anyopaque) sf.c.sfBool {
    // TODO: Even though this is the correct address of self, I cannot read the data correctly.
    // I think because this is accessed from a different thread?
    const self: *align(1) Self = if (any != null) @ptrCast(any.?) else unreachable;
    std.debug.print("Audio wanted to have data: Read: {d}, Write: {d}, Len: {d}\n", .{ self.samples.read_index, self.samples.write_index, self.samples.len() });
    return @intFromBool(true);
}

export fn soundStreamOnSeek(_: sf.c.sfTime, _: ?*anyopaque) void {
    // Not needed.
}
