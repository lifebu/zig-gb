const std = @import("std");

const APU = @import("../apu.zig");
const CPU = @import("../cpu.zig");
const Def = @import("../def.zig");
const MMIO = @import("../mmio.zig");
const MMU = @import("../mmu.zig");
const MemMap = @import("../mem_map.zig");
const PPU = @import("../ppu.zig");

pub fn runInterruptTests() !void {
    const alloc = std.testing.allocator;

    var apu = APU{};
    var mmio = MMIO{};
    var mmu = try MMU.init(alloc, &apu);
    defer mmu.deinit();

    var cpu = try CPU.init();
    defer cpu.deinit();

    var ppu = PPU{};
    var pixels = try alloc.alloc(Def.Color, Def.RESOLUTION_WIDTH * Def.RESOLUTION_HEIGHT);
    defer alloc.free(pixels);

    // IME is reset by DI.
    mmu.write8_sys(MemMap.WRAM_LOW, 0xF3); // DI
    cpu.pc = MemMap.WRAM_LOW;
    cpu.ime = true;
    try cpu.step(&mmu);
    std.testing.expectEqual(false, cpu.ime) catch |err| {
        std.debug.print("Failed: DI disables IME.\n", .{});
        return err;
    };

    // IME is set by RETI
    mmu.write8_sys(MemMap.WRAM_LOW, 0xD9); // RETI
    cpu.pc = MemMap.WRAM_LOW;
    cpu.sp = MemMap.WRAM_HIGH;
    cpu.ime = false;
    try cpu.step(&mmu);
    std.testing.expectEqual(true, cpu.ime) catch |err| {
        std.debug.print("Failed: RETI enables IME.\n", .{});
        return err;
    };

    // IME is set by EI with 1 instruction delay
    mmu.write8_sys(MemMap.WRAM_LOW, 0xFB); // EI
    cpu.pc = MemMap.WRAM_LOW;
    cpu.ime = false;
    try cpu.step(&mmu);
    std.testing.expectEqual(false, cpu.ime) catch |err| {
        std.debug.print("Failed: EI enables IME after one instruction.\n", .{});
        return err;
    };
    try cpu.step(&mmu);
    std.testing.expectEqual(true, cpu.ime) catch |err| {
        std.debug.print("Failed: EI enables IME after one instruction.\n", .{});
        return err;
    };

    // IME is reset by the interrupt handler
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0b0001_0000);
    mmu.write8_sys(MemMap.INTERRUPT_ENABLE, 0xFF);
    cpu.pc = MemMap.WRAM_LOW;
    cpu.ime = true;
    try cpu.step(&mmu);
    std.testing.expectEqual(false, cpu.ime) catch |err| {
        std.debug.print("Failed: CPU disables IME during interrupt handling.\n", .{});
        return err;
    };

    // CPU can write to IF.
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    mmu.write8_sys(MemMap.WRAM_LOW, 0x77);  // LD (HL), A
    cpu.registers.r16.HL = MemMap.INTERRUPT_FLAG;
    cpu.registers.r8.A = 0xFF;
    cpu.pc = MemMap.WRAM_LOW;
    try cpu.step(&mmu);
    std.testing.expectEqual(0xFF, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
        std.debug.print("Failed: CPU can write to IF.\n", .{});
        return err;
    };

    // Interrupt targets
    const InterruptTargetTest = struct {
        name: []const u8,
        interupt_flag: u8,
        expected_pc: u16,
    };

    const interruptTargetTests = [_]InterruptTargetTest {
        InterruptTargetTest {
            .name = "CPU jumps to 0x60 for requested and enabled Joypad interrupt",
            .interupt_flag =  0b0001_0000,
            .expected_pc = 0x60,
        },
        InterruptTargetTest {
            .name = "CPU jumps to 0x58 for requested and enabled Serial interrupt",
            .interupt_flag =  0b0000_1000,
            .expected_pc = 0x58,
        },
        InterruptTargetTest {
            .name = "CPU jumps to 0x50 for requested and enabled Timer interrupt",
            .interupt_flag =  0b0000_0100,
            .expected_pc = 0x50,
        },
        InterruptTargetTest {
            .name = "CPU jumps to 0x48 for requested and enabled STAT interrupt",
            .interupt_flag =  0b0000_0010,
            .expected_pc = 0x48,
        },
        InterruptTargetTest {
            .name = "CPU jumps to 0x40 for requested and enabled STAT interrupt",
            .interupt_flag =  0b0000_0001,
            .expected_pc = 0x40,
        },
    };

    for(interruptTargetTests, 0..) |testCase, i| {
        if(i == 0) { // Change value to attach debugger.
            var val: u32 = 0;
            val += 1;
        }
        mmu.write8_sys(MemMap.INTERRUPT_FLAG, testCase.interupt_flag);
        mmu.write8_sys(MemMap.INTERRUPT_ENABLE, 0xFF);
        cpu.pc = MemMap.WRAM_LOW;
        cpu.ime = true;
        try cpu.step(&mmu);
        std.testing.expectEqual(testCase.expected_pc, cpu.pc) catch |err| {
            std.debug.print("Failed Target Test {d}: {s}\n", .{ i, testCase.name });
            return err;
        };
    }

    // Interrupt request: Joypad: One bit of lower joypad nibble went from 1 to 0.
    mmio.updateJoypad(&mmu, Def.InputState {
        .isDownPressed = false, .isUpPressed = false, .isLeftPressed = false, .isRightPressed = false,
        .isStartPressed = false, .isSelectPressed = false, .isBPressed = false, .isAPressed = false,
    });
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    mmu.write8_sys(MemMap.JOYPAD, 0b1110_1111);
    mmio.updateJoypad(&mmu, Def.InputState {
        .isDownPressed = true, .isUpPressed = false, .isLeftPressed = false, .isRightPressed = false,
        .isStartPressed = false, .isSelectPressed = false, .isBPressed = false, .isAPressed = false,
    });
    std.testing.expectEqual(0b0001_0000, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
        std.debug.print("Failed: Joypad requests interrupt.\n", .{});
        return err;
    };

    // TODO: Interrupt request: Serial.

    // Interrupt request: Timer: TIMA overflows.
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    mmio.dividerCounter = 0;
    mmu.write8_sys(MemMap.TIMER, 0xFF);
    mmu.write8_sys(MemMap.TIMER_CONTROL, 0b0000_0101); // 16 cycles per increment.
    for(0..16) |_| {
        mmio.updateTimers(&mmu);
    }
    std.testing.expectEqual(0b0000_0100, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
        std.debug.print("Failed: Joypad requests interrupt.\n", .{});
        return err;
    };

    // Interrupt request: STAT: LY = LYC.
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    mmu.write8_sys(MemMap.LCD_STAT, 0b0100_0000); // Select LY = LYC.
    ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    mmu.write8_sys(MemMap.LCD_CONTROL, 0b1000_0000);
    mmu.write8_sys(MemMap.LCD_Y, 9);
    mmu.write8_sys(MemMap.LCD_Y_COMPARE, 10);
    ppu.step(&mmu, &pixels);
    std.testing.expectEqual(0b0000_0010, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
        std.debug.print("Failed: STAT for LY=LYC requests interrupt.\n", .{});
        return err;
    };

    // Interrupt request: STAT: Mode 0
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    mmu.write8_sys(MemMap.LCD_STAT, 0b0000_1000); // Select Mode 0 (HBlank)
    ppu.lyCounter = 0;
    ppu.lastSTATLine = false;
    mmu.write8_sys(MemMap.LCD_Y, 0);
    while(mmu.read8_sys(MemMap.LCD_Y) == 0) {
        ppu.step(&mmu, &pixels);
    }
    std.testing.expectEqual(0b0000_0010, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
        std.debug.print("Failed: STAT for Mode 0 (HBlank) requests interrupt.\n", .{});
        return err;
    };

    // Interrupt request: STAT: Mode 1
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    mmu.write8_sys(MemMap.LCD_STAT, 0b0001_0000); // Select Mode 1 (VBlank)
    ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    ppu.lastSTATLine = false;
    mmu.write8_sys(MemMap.LCD_Y, Def.RESOLUTION_HEIGHT - 1);
    ppu.step(&mmu, &pixels);
    // Will trigger VBlank and STAT interrupt!
    std.testing.expectEqual(0b0000_0011, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
        std.debug.print("Failed: STAT for Mode 1 (VBlank) requests interrupt.\n", .{});
        return err;
    };

    // Interrupt request: STAT: Mode 2
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    mmu.write8_sys(MemMap.LCD_STAT, 0b0010_0000); // Select Mode 2 (OAMScan)
    ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    ppu.lastSTATLine = false;
    mmu.write8_sys(MemMap.LCD_Y, 0);
    ppu.step(&mmu, &pixels);
    std.testing.expectEqual(0b0000_0010, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
        std.debug.print("Failed: STAT for Mode 2 (OAMScan) requests interrupt.\n", .{});
        return err;
    };

    // Interrupt request: STAT: STAT Blocking.
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    mmu.write8_sys(MemMap.LCD_STAT, 0b0010_1000); // Select Mode 0 (HBlank) and Mode 2 (OAMScan)
    ppu.lyCounter = 0;
    mmu.write8_sys(MemMap.LCD_Y, 0);
    while(mmu.read8_sys(MemMap.INTERRUPT_FLAG) == 0) { // Go until we have an HBlank interrupt.
        ppu.step(&mmu, &pixels);
    }
    // We now got a HBlank stat interrupt, clear it and try to get an OAMScan Stat interrupt.
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    while(mmu.read8_sys(MemMap.LCD_Y) == 0) { // Go until we are on the second line
        ppu.step(&mmu, &pixels);
    }
    std.testing.expectEqual(0b0000_0000, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
        std.debug.print("Failed: STAT interrupts are blocked for consecutive STAT sources.\n", .{});
        return err;
    };

    // Interrupt request: VBlank: Reached VBlank
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    mmu.write8_sys(MemMap.LCD_STAT, 0b0000_0000); // Select no STAT interrupt
    ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    mmu.write8_sys(MemMap.LCD_Y, Def.RESOLUTION_HEIGHT - 1);
    ppu.step(&mmu, &pixels);
    std.testing.expectEqual(0b0000_0001, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
        std.debug.print("Failed: VBlank requests interrupt.\n", .{});
        return err;
    };

    // Interrupt priorities: VBlank > LCD > Timer > Serial > Joypad
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0b0001_1111); // All interupts are pending.
    mmu.write8_sys(MemMap.INTERRUPT_ENABLE, 0xFF);
    cpu.pc = MemMap.WRAM_LOW;
    // Reenable IME for each interrupt vector.
    mmu.write8_sys(MemMap.WRAM_LOW, 0xF3); // DI
    mmu.write8_sys(MemMap.WRAM_LOW + 1, 0xFB); // EI
    mmu.write8_sys(0x40, 0xFB); // EI
    mmu.write8_sys(0x48, 0xFB); // EI
    mmu.write8_sys(0x50, 0xFB); // EI
    mmu.write8_sys(0x58, 0xFB); // EI
    mmu.write8_sys(0x60, 0xFB); // EI
    try cpu.step(&mmu);

    const InterruptPrioTest = struct {
        name: []const u8,
        expected_if: u8,
    };
    const interruptPrioTests = [_]InterruptPrioTest {
        InterruptPrioTest {
            .name = "VBlank handled first",
            .expected_if = 0b0001_1110,
        },
        InterruptPrioTest {
            .name = "LCD handled second",
            .expected_if = 0b0001_1100,
        },
        InterruptPrioTest {
            .name = "Timer handled third",
            .expected_if = 0b0001_1000,
        },
        InterruptPrioTest {
            .name = "Serial handled fourth",
            .expected_if = 0b0001_0000,
        },
        InterruptPrioTest {
            .name = "Joypad handled fifth",
            .expected_if = 0b0000_0000,
        },
    };

    for(interruptPrioTests, 0..) |testCase, i| {
        try cpu.step(&mmu); // EI
        try cpu.step(&mmu); // NOP
        try cpu.step(&mmu); // Interrupt!
        std.testing.expectEqual(testCase.expected_if, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
            std.debug.print("Failed Interrupt Priority Test {d}: {s}\n", .{ i, testCase.name });
            return err;
        };
    }

    // TODO: Missing Tests:
    // - Spurious Stat Interrupt (DMG Bug). (Only two games depend on this).
}
