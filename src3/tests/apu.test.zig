const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const MMU = @import("../mmu.zig");
const def = @import("../defines.zig");
const APU = @import("../apu.zig");
const Platform = @import("../platform.zig");
const mem_map = @import("../mem_map.zig");

pub fn runApuSamplerTests() !void {
    var mmu: MMU.State = .{}; 

    // Initialize with test memory.
    for(0x0300..0x039F, 1..) |addr, i| {
        mmu.memory[@intCast(addr)] = @truncate(i);
    }
    for(mem_map.oam_low..mem_map.oam_high + 1) |addr| {
        mmu.memory[@intCast(addr)] = 0;
    }

    try std.testing.expectEqual(true, true);
}

pub fn runApuOutputTest() !void {
    var mmu: MMU.State = .{}; 

    // Initialize with test memory.
    for(0x0300..0x039F, 1..) |addr, i| {
        mmu.memory[@intCast(addr)] = @truncate(i);
    }
    for(mem_map.oam_low..mem_map.oam_high + 1) |addr| {
        mmu.memory[@intCast(addr)] = 0;
    }

    try std.testing.expectEqual(true, true);
}
