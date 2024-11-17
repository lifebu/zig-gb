
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
    mmio.dividerCounter = 0;
    mmu.write8(MemMap.TIMER_MOD, 0x05);

    // 1024 cycles / increment
    mmio.dividerCounter = 0;
    mmu.write8(MemMap.TIMER_CONTROL, 0b0000_0100);
    for(0..1024) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x01, mmu.read8(MemMap.TIMER));

    // 16 cycles / increment
    mmio.dividerCounter = 0;
    mmu.write8(MemMap.TIMER_CONTROL, 0b0000_0101);
    for(0..16) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x02, mmu.read8(MemMap.TIMER));

    // 64 cycles / increment
    mmio.dividerCounter = 0;
    mmu.write8(MemMap.TIMER_CONTROL, 0b0000_0110);
    for(0..64) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x03, mmu.read8(MemMap.TIMER));

    // 256 cycles / increment
    mmio.dividerCounter = 0;
    mmu.write8(MemMap.TIMER_CONTROL, 0b0000_0111);
    for(0..256) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x04, mmu.read8(MemMap.TIMER));

    // overflow
    mmio.dividerCounter = 0;
    mmu.write8(MemMap.TIMER_MOD, 0x05);
    mmu.write8(MemMap.TIMER, 0xFF);
    mmu.write8(MemMap.INTERRUPT_FLAG, 0x00);
    for(0..256) |_| {
        mmio.updateTimers(&mmu);
    }
    // TIMA value is applied 4 cycles later.
    try std.testing.expectEqual(0x00, mmu.read8(MemMap.TIMER));
    try std.testing.expectEqual(false, mmu.testFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_TIMER));
    for(0..4) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x05, mmu.read8(MemMap.TIMER));
    try std.testing.expectEqual(true, mmu.testFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_TIMER));

    // disable can increment timer.
    mmio.dividerCounter = 0xFFFD;
    mmio.updateTimers(&mmu);
    try std.testing.expectEqual(0x05, mmu.read8(MemMap.TIMER));
    mmu.write8(MemMap.TIMER_CONTROL, 0b0000_0011);
    mmio.updateTimers(&mmu);
    try std.testing.expectEqual(0x06, mmu.read8(MemMap.TIMER));

    // overflow: cpu writes abort timer_mod
    mmio.dividerCounter = 0;
    mmu.write8(MemMap.TIMER_MOD, 0x05);
    mmu.write8(MemMap.TIMER, 0xFF);
    mmu.write8(MemMap.INTERRUPT_FLAG, 0x00);
    for(0..256) |_| {
        mmio.updateTimers(&mmu);
    }
    mmu.write8(MemMap.TIMER, 0x10);
    for(0..4) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x10, mmu.read8(MemMap.TIMER));
    try std.testing.expectEqual(false, mmu.testFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_TIMER));

    // overflow: cpu write TIMA on 4th cycle => write is ignored
    mmio.dividerCounter = 0;
    mmu.write8(MemMap.TIMER_MOD, 0x05);
    mmu.write8(MemMap.TIMER, 0xFF);
    mmu.write8(MemMap.INTERRUPT_FLAG, 0x00);
    for(0..(256 + 3)) |_| {
        mmio.updateTimers(&mmu);
    }
    mmu.write8(MemMap.TIMER, 0x33);
    mmio.updateTimers(&mmu);
    try std.testing.expectEqual(0x05, mmu.read8(MemMap.TIMER));

    // overflow: cpu write TMA on 4th cycle => new TMA value is used.
    mmio.dividerCounter = 0;
    mmu.write8(MemMap.TIMER_MOD, 0x05);
    mmu.write8(MemMap.TIMER, 0xFF);
    mmu.write8(MemMap.INTERRUPT_FLAG, 0x00);
    for(0..(256 + 3)) |_| {
        mmio.updateTimers(&mmu);
    }
    mmu.write8(MemMap.TIMER_MOD, 0x22);
    mmio.updateTimers(&mmu);
    try std.testing.expectEqual(0x22, mmu.read8(MemMap.TIMER));
}

pub fn runDMATest() !void {
    const alloc = std.testing.allocator;

    var mmio = MMIO{};

    var mmu = try MMU.init(alloc, &mmio, null);
    defer mmu.deinit();
    const rawMemory: *[]u8 = mmu.getRaw();
    for(0x0300..0x039F, 1..) |addr, i| {
        rawMemory.*[addr] = @truncate(i);
    }
    for(MemMap.OAM_LOW..MemMap.OAM_HIGH + 1) |addr| {
        rawMemory.*[addr] = 0;
    }

    // correct address calculation.
    mmu.write8(MemMap.DMA, 0x03);
    try std.testing.expectEqual(true, mmio.dmaIsRunning);
    try std.testing.expectEqual(0x0300, mmio.dmaStartAddr);
    try std.testing.expectEqual(0, mmio.dmaCurrentOffset);

    // first 4 cycles nothing happens.
    for(0..4) |_| {
        mmio.updateDMA(&mmu);
    }
    try std.testing.expectEqual(0, rawMemory.*[MemMap.OAM_LOW]);

    // every 4 cycles one byte is copied.
    for(0..160) |iByte| {
        for(0..4) |_| {
            mmio.updateDMA(&mmu);
        }
        try std.testing.expectEqual(rawMemory.*[mmio.dmaStartAddr + iByte], rawMemory.*[MemMap.OAM_LOW + iByte]);
        try std.testing.expectEqual(0, rawMemory.*[MemMap.OAM_LOW + iByte + 1]);
    }

    // dma is now done.
    try std.testing.expectEqual(false, mmio.dmaIsRunning);

    // TODO: Also test DMA bus conflicts and what the CPU/PPU could access.
    // https://hacktix.github.io/GBEDG/dma/
    // https://gbdev.io/pandocs/OAM_DMA_Transfer.html
}
