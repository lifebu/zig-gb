
const std = @import("std");

const APU = @import("../apu.zig");
const Def = @import("../def.zig");
const MMIO = @import("../mmio.zig");
const MMU = @import("../mmu.zig");
const MemMap = @import("../mem_map.zig");


pub fn runDividerTest() !void {
    const alloc = std.testing.allocator;

    var apu = APU{};
    var mmio = MMIO{};
    var mmu = try MMU.init(alloc, &apu);
    defer mmu.deinit();

    var expectedDIV: u8 = 0;
    mmu.write8_usr(MemMap.DIVIDER, 255);
    mmio.onWrite(&mmu);
    try std.testing.expectEqual(expectedDIV, mmu.read8_sys(MemMap.DIVIDER));

    const DIV_FREQ = 256;
    for(0..300) |_| {
        for(0..DIV_FREQ) |_| {
            mmio.updateTimers(&mmu);
        }
        expectedDIV +%= 1;
        try std.testing.expectEqual(expectedDIV, mmu.read8_sys(MemMap.DIVIDER));
    }
}

pub fn runTimerTest() !void {
    const alloc = std.testing.allocator;

    var apu = APU{};
    var mmio = MMIO{};
    var mmu = try MMU.init(alloc, &apu);
    defer mmu.deinit();

    mmu.write8_sys(MemMap.TIMER, 0x00);
    mmio.dividerCounter = 0;
    mmu.write8_sys(MemMap.TIMER_MOD, 0x05);

    // 1024 cycles / increment
    mmio.dividerCounter = 0;
    mmu.write8_sys(MemMap.TIMER_CONTROL, 0b0000_0100);
    for(0..1024) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x01, mmu.read8_sys(MemMap.TIMER));

    // 16 cycles / increment
    mmio.dividerCounter = 0;
    mmu.write8_sys(MemMap.TIMER_CONTROL, 0b0000_0101);
    for(0..16) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x02, mmu.read8_sys(MemMap.TIMER));

    // 64 cycles / increment
    mmio.dividerCounter = 0;
    mmu.write8_sys(MemMap.TIMER_CONTROL, 0b0000_0110);
    for(0..64) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x03, mmu.read8_sys(MemMap.TIMER));

    // 256 cycles / increment
    mmio.dividerCounter = 0;
    mmu.write8_sys(MemMap.TIMER_CONTROL, 0b0000_0111);
    for(0..256) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x04, mmu.read8_sys(MemMap.TIMER));

    // overflow
    mmio.dividerCounter = 0;
    mmu.write8_sys(MemMap.TIMER_MOD, 0x05);
    mmu.write8_sys(MemMap.TIMER, 0xFF);
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    for(0..256) |_| {
        mmio.updateTimers(&mmu);
    }
    // TIMA value is applied 4 cycles later.
    try std.testing.expectEqual(0x00, mmu.read8_sys(MemMap.TIMER));
    try std.testing.expectEqual(false, mmu.testFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_TIMER));
    for(0..4) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x05, mmu.read8_sys(MemMap.TIMER));
    try std.testing.expectEqual(true, mmu.testFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_TIMER));

    // disable can increment timer.
    mmio.dividerCounter = 0xFFFD;
    mmio.updateTimers(&mmu);
    try std.testing.expectEqual(0x05, mmu.read8_sys(MemMap.TIMER));
    mmu.write8_sys(MemMap.TIMER_CONTROL, 0b0000_0011);
    mmio.updateTimers(&mmu);
    try std.testing.expectEqual(0x06, mmu.read8_sys(MemMap.TIMER));

    // overflow: cpu writes abort timer_mod
    mmio.dividerCounter = 0;
    mmu.write8_sys(MemMap.TIMER_MOD, 0x05);
    mmu.write8_sys(MemMap.TIMER, 0xFF);
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    for(0..256) |_| {
        mmio.updateTimers(&mmu);
    }
    mmu.write8_sys(MemMap.TIMER, 0x10);
    for(0..4) |_| {
        mmio.updateTimers(&mmu);
    }
    try std.testing.expectEqual(0x10, mmu.read8_sys(MemMap.TIMER));
    try std.testing.expectEqual(false, mmu.testFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_TIMER));

    // overflow: cpu write TIMA on 4th cycle => write is ignored
    mmio.dividerCounter = 0;
    mmu.write8_sys(MemMap.TIMER_MOD, 0x05);
    mmu.write8_sys(MemMap.TIMER, 0xFF);
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    for(0..(256 + 3)) |_| {
        mmio.updateTimers(&mmu);
    }
    mmu.write8_sys(MemMap.TIMER, 0x33);
    mmio.updateTimers(&mmu);
    try std.testing.expectEqual(0x05, mmu.read8_sys(MemMap.TIMER));

    // overflow: cpu write TMA on 4th cycle => new TMA value is used.
    mmio.dividerCounter = 0;
    mmu.write8_sys(MemMap.TIMER_MOD, 0x05);
    mmu.write8_sys(MemMap.TIMER, 0xFF);
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    for(0..(256 + 3)) |_| {
        mmio.updateTimers(&mmu);
    }
    mmu.write8_sys(MemMap.TIMER_MOD, 0x22);
    mmio.updateTimers(&mmu);
    try std.testing.expectEqual(0x22, mmu.read8_sys(MemMap.TIMER));
}

pub fn runDMATest() !void {
    const alloc = std.testing.allocator;

    var apu = APU{};
    var mmio = MMIO{};
    var mmu = try MMU.init(alloc, &apu);
    defer mmu.deinit();

    for(0x0300..0x039F, 1..) |addr, i| {
        mmu.write8_sys(@intCast(addr), @truncate(i));
    }
    for(MemMap.OAM_LOW..MemMap.OAM_HIGH + 1) |addr| {
        mmu.write8_sys(@intCast(addr), 0);
    }

    // correct address calculation.
    mmu.write8_usr(MemMap.DMA, 0x03);
    try std.testing.expectEqual(true, mmio.dmaIsRunning);
    try std.testing.expectEqual(0x0300, mmio.dmaStartAddr);
    try std.testing.expectEqual(0, mmio.dmaCurrentOffset);

    // first 4 cycles nothing happens.
    for(0..4) |_| {
        mmio.updateDMA(&mmu);
    }
    try std.testing.expectEqual(0, mmu.read8_sys(MemMap.OAM_LOW));

    // every 4 cycles one byte is copied.
    for(0..160) |iByte| {
        for(0..4) |_| {
            mmio.updateDMA(&mmu);
        }
        try std.testing.expectEqual(mmu.memory[mmio.dmaStartAddr + iByte], mmu.memory[MemMap.OAM_LOW + iByte]);
        try std.testing.expectEqual(0, mmu.read8_sys(@intCast(MemMap.OAM_LOW + iByte + 1)));
    }

    // dma is now done.
    try std.testing.expectEqual(false, mmio.dmaIsRunning);

    // TODO: Also test DMA bus conflicts and what the CPU/PPU could access.
    // https://hacktix.github.io/GBEDG/dma/
    // https://gbdev.io/pandocs/OAM_DMA_Transfer.html
}

// TODO: Use this in the MMIO code?
/// The state of the joypad byte.
const JoyState = packed struct(u8) {
    const Self = @This();

    not_a_right: bool,
    not_b_left: bool,
    not_select_up: bool,
    not_start_down: bool,
    not_select_dpad: bool,
    not_select_buttons: bool,
    _: u2,

    // TODO: Maybe doing the casts in some functions in the packed structs makes the code way more cleaner?
    pub fn toByte(self: Self) u8 {
        return @bitCast(self);
    }

    // TODO: Maybe doing the casts in some functions in the packed structs makes the code way more cleaner?
    pub fn fromByte(self: Self, val: u8) void {
        self = @bitCast(val);
    }
};

pub fn runJoypadTests() !void {
    const alloc = std.testing.allocator;

    var apu = APU{};
    var mmio = MMIO{};
    var mmu = try MMU.init(alloc, &apu);
    defer mmu.deinit();

    const TestCase = struct {
        name: []const u8,
        write: u8,
        expected: u8,
        input: Def.InputState,
    };

    // TODO: Move those testcases to json?
    const testCases = [_]TestCase {
        TestCase {
            .name = "Nothing selected but have pressed button/dpad",
            .write = 0b1111_1111,
            .expected = 0b1111_1111,
            .input = Def.InputState {
                .isDownPressed = true, .isUpPressed = false, .isLeftPressed = true, .isRightPressed = false,
                .isStartPressed = false, .isSelectPressed = true, .isBPressed = false, .isAPressed = true,
            },
        },
        TestCase {
            .name = "Select dpad and nothing pressed",
            .write = 0b1110_1111,
            .expected = 0b1110_1111,
            .input = Def.InputState {
                .isDownPressed = false, .isUpPressed = false, .isLeftPressed = false, .isRightPressed = false,
                .isStartPressed = false, .isSelectPressed = false, .isBPressed = false, .isAPressed = false,
            },
        },
        TestCase {
            .name = "Select dpad and down pressed.",
            .write = 0b1110_1111,
            .expected = 0b1110_0111,
            .input = Def.InputState {
                .isDownPressed = true, .isUpPressed = false, .isLeftPressed = false, .isRightPressed = false,
                .isStartPressed = false, .isSelectPressed = false, .isBPressed = false, .isAPressed = false,
            },
        },
        TestCase {
            .name = "Select dpad and up pressed.",
            .write = 0b1110_1111,
            .expected = 0b1110_1011,
            .input = Def.InputState {
                .isDownPressed = false, .isUpPressed = true, .isLeftPressed = false, .isRightPressed = false,
                .isStartPressed = false, .isSelectPressed = false, .isBPressed = false, .isAPressed = false,
            },
        },
        TestCase {
            .name = "Select dpad and left pressed.",
            .write = 0b1110_1111,
            .expected = 0b1110_1101,
            .input = Def.InputState {
                .isDownPressed = false, .isUpPressed = false, .isLeftPressed = true, .isRightPressed = false,
                .isStartPressed = false, .isSelectPressed = false, .isBPressed = false, .isAPressed = false,
            },
        },
        TestCase {
            .name = "Select dpad and right pressed.",
            .write = 0b1110_1111,
            .expected = 0b1110_1110,
            .input = Def.InputState {
                .isDownPressed = false, .isUpPressed = false, .isLeftPressed = false, .isRightPressed = true,
                .isStartPressed = false, .isSelectPressed = false, .isBPressed = false, .isAPressed = false,
            },
        },
        TestCase {
            .name = "Select dpad and left,right,up,down pressed (impossible inputs).",
            .write = 0b1110_1111,
            .expected = 0b1110_1111,
            .input = Def.InputState {
                .isDownPressed = true, .isUpPressed = true, .isLeftPressed = true, .isRightPressed = true,
                .isStartPressed = false, .isSelectPressed = false, .isBPressed = false, .isAPressed = false,
            },
        },
        TestCase {
            .name = "Select button and nothing pressed",
            .write = 0b1101_1111,
            .expected = 0b1101_1111,
            .input = Def.InputState {
                .isDownPressed = false, .isUpPressed = false, .isLeftPressed = false, .isRightPressed = false,
                .isStartPressed = false, .isSelectPressed = false, .isBPressed = false, .isAPressed = false,
            },
        },
        TestCase {
            .name = "Select button and start pressed.",
            .write = 0b1101_1111,
            .expected = 0b1101_0111,
            .input = Def.InputState {
                .isDownPressed = false, .isUpPressed = false, .isLeftPressed = false, .isRightPressed = false,
                .isStartPressed = true, .isSelectPressed = false, .isBPressed = false, .isAPressed = false,
            },
        },
        TestCase {
            .name = "Select button and select pressed.",
            .write = 0b1101_1111,
            .expected = 0b1101_1011,
            .input = Def.InputState {
                .isDownPressed = false, .isUpPressed = false, .isLeftPressed = false, .isRightPressed = false,
                .isStartPressed = false, .isSelectPressed = true, .isBPressed = false, .isAPressed = false,
            },
        },
        TestCase {
            .name = "Select button and b pressed.",
            .write = 0b1101_1111,
            .expected = 0b1101_1101,
            .input = Def.InputState {
                .isDownPressed = false, .isUpPressed = false, .isLeftPressed = false, .isRightPressed = false,
                .isStartPressed = false, .isSelectPressed = false, .isBPressed = true, .isAPressed = false,
            },
        },
        TestCase {
            .name = "Select button and a pressed.",
            .write = 0b1101_1111,
            .expected = 0b1101_1110,
            .input = Def.InputState {
                .isDownPressed = false, .isUpPressed = false, .isLeftPressed = false, .isRightPressed = false,
                .isStartPressed = false, .isSelectPressed = false, .isBPressed = false, .isAPressed = true,
            },
        },
        TestCase {
            .name = "Select buttons and dpad and some inputs pressed. Expecting output and of dpad and buttons.",
            .write = 0b1100_1111,
            .expected = 0b1100_0001,
            .input = Def.InputState {
                .isDownPressed = true, .isUpPressed = false, .isLeftPressed = true, .isRightPressed = false,
                .isStartPressed = true, .isSelectPressed = true, .isBPressed = false, .isAPressed = false,
            },
        },
    };

    for(testCases, 0..) |testCase, i| {
        if(i == 0) { // Change value to attach debugger.
            var val: u32 = 0;
            val += 1;
        }
        mmu.write8_sys(MemMap.JOYPAD, testCase.write);
        mmio.updateJoypad(&mmu, testCase.input);
        std.testing.expectEqual(testCase.expected, mmu.read8_sys(MemMap.JOYPAD)) catch |err| {
            std.debug.print("Failed {d}: {s}\n", .{ i, testCase.name });
            return err;
        };
    }

    // Lower nibble is read-only to cpu.
    mmu.write8_sys(MemMap.JOYPAD, 0b1111_1111);
    mmu.write8_usr(MemMap.JOYPAD, 0b1111_0000);
    std.testing.expectEqual(0b1111_1111, mmu.read8_sys(MemMap.JOYPAD)) catch |err| {
        std.debug.print("Failed {d}: {s}\n", .{ testCases.len, "Lower nibble is ready-only to cpu" });
        return err;
    };
}
