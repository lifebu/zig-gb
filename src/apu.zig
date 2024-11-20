const std = @import("std");
const assert = std.debug.assert;

const MemMap = @import("mem_map.zig");
const MMU = @import("mmu.zig");

const Self = @This();

pub fn step(_: *Self, _: *MMU, buffer: *std.RingBuffer) void {
    var a: usize = 0;
    a += buffer.len();
}
