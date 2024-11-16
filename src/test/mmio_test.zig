
const std = @import("std");

const MMIO = @import("../mmio.zig");
const MMU = @import("../mmu.zig");
const MemMap = @import("../mem_map.zig");


pub fn runDividerTest() !void {
    const alloc = std.testing.allocator;

    var mmio = MMIO{};

    var mmu = try MMU.init(alloc, &mmio, null);
    defer mmu.deinit();

    var expectedDIV: u8 = 0;
    mmu.write8(MemMap.DIVIDER, 255);
    try std.testing.expectEqual(expectedDIV, mmu.read8(MemMap.DIVIDER));

    mmu.disableChecks = true;

    const DIV_FREQ = 256;
    for(0..300) |_| {
        for(0..DIV_FREQ) |_| {
            mmio.updateTimers(&mmu);
        }
        expectedDIV +%= 1;
        try std.testing.expectEqual(expectedDIV, mmu.read8(MemMap.DIVIDER));
    }
}

pub fn runTimerTest() !void {
    const alloc = std.testing.allocator;

    var mmio = MMIO{};

    var mmu = try MMU.init(alloc, &mmio, null);
    defer mmu.deinit();

    mmu.write8(MemMap.TIMER, 0x00);
    mmu.write8(MemMap.TIMER_MOD, 0x00);

    // 1024 cycles / increment
    mmu.write8(MemMap.TIMER_CONTROL, 0b0000_0100);
    for(0..1024) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x01, mmu.read8(MemMap.TIMER));

    // 16 cycles / increment
    mmu.write8(MemMap.TIMER_CONTROL, 0b0000_0101);
    for(0..16) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x02, mmu.read8(MemMap.TIMER));

    // 64 cycles / increment
    mmu.write8(MemMap.TIMER_CONTROL, 0b0000_0110);
    for(0..64) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x03, mmu.read8(MemMap.TIMER));

    // 256 cycles / increment
    mmu.write8(MemMap.TIMER_CONTROL, 0b0000_0111);
    for(0..256) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x04, mmu.read8(MemMap.TIMER));

    // overflow
    mmu.write8(MemMap.TIMER, 0xFF);
    for(0..256) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x00, mmu.read8(MemMap.TIMER));
}
