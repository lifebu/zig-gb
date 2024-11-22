const std = @import("std");
const assert = std.debug.assert;

const MemMap = @import("mem_map.zig");
const MMU = @import("mmu.zig");
const RingBufferMT = @import("util/RingBufferMT.zig");

const Self = @This();

pub fn step(_: *Self, _: *MMU, samples: *RingBufferMT) void {
    var a: usize = 0;
    a += samples.len();
}
