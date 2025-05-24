const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const CPU = @import("../cpu.zig");
const mem_map = @import("../mem_map.zig");
const MMU = @import("../mmu.zig");

pub fn executeCPUFor(cpu: *CPU.State, mmu: *MMU.State, m_cycles: usize) void {
    cpu.uop_fifo.clear();
    // Load a nop instruction to fetch the required instruction.
    const opcode_bank = CPU.opcode_banks[CPU.opcode_bank_default];
    const uops = opcode_bank[0];
    cpu.uop_fifo.write(uops.slice());
    for(0..(def.t_cycles_per_m_cycle * m_cycles)) |_| {
        CPU.cycle(cpu, mmu);
        MMU.cycle(mmu);
    }
}

pub fn runInterruptTests() !void {
    var mmu: MMU.State = .{}; 
    var cpu: CPU.State = .{};
    CPU.init(&cpu);

    // IME is reset by DI.
    mmu.memory[mem_map.wram_low] = 0xF3; // DI
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = true;
    executeCPUFor(&cpu, &mmu, 2);
    std.testing.expectEqual(false, cpu.interrupt_master_enable) catch |err| {
        std.debug.print("Failed: DI disables IME.\n", .{});
        return err;
    };

    // IME is set by RETI
    mmu.memory[mem_map.wram_low] = 0xD9; // RETI
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.registers.r16.sp = mem_map.wram_high;
    cpu.interrupt_master_enable = false;
    executeCPUFor(&cpu, &mmu, 5);
    std.testing.expectEqual(true, cpu.interrupt_master_enable) catch |err| {
        std.debug.print("Failed: RETI enables IME.\n", .{});
        return err;
    };

    // IME is set by EI
    mmu.memory[mem_map.wram_low] = 0xFB; // EI
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = false;
    executeCPUFor(&cpu, &mmu, 2);
    std.testing.expectEqual(true, cpu.interrupt_master_enable) catch |err| {
        std.debug.print("Failed: EI enables IME after one instruction.\n", .{});
        return err;
    };
    
    // TODO: Implemenent instruction handler is not active after EI directly and is delayed.
    // executeCPUFor(&cpu, &mmu, 1);
    // std.testing.expectEqual(true, cpu.interrupt_master_enable) catch |err| {
    //     std.debug.print("Failed: EI enables IME after one instruction.\n", .{});
    //     return err;
    // };

    // CPU can write to IF.
    mmu.memory[mem_map.interrupt_flag] = 0b0000_0000;
    mmu.memory[mem_map.wram_low] = 0x77; // LD (HL), A
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.registers.r16.hl = mem_map.interrupt_flag;
    cpu.registers.r8.a = 0xFF;
    executeCPUFor(&cpu, &mmu, 2);
    std.testing.expectEqual(0xFF, mmu.memory[mem_map.interrupt_flag]) catch |err| {
        std.debug.print("Failed: CPU can write to IF.\n", .{});
        return err;
    };

    // IME is reset by the interrupt handler
    mmu.memory[mem_map.interrupt_flag] = 0b0001_0000;
    mmu.memory[mem_map.interrupt_enable] = 0xFF;
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = true;
    executeCPUFor(&cpu, &mmu, 5);
    std.testing.expectEqual(false, cpu.interrupt_master_enable) catch |err| {
        std.debug.print("Failed: CPU disables IME during interrupt handling.\n", .{});
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

    for(interruptTargetTests, 0..) |test_case, i| {
        if(i == 0) { // Change value to attach debugger.
            var val: u32 = 0;
            val += 1;
        }

        mmu.memory[mem_map.interrupt_flag] = test_case.interupt_flag;
        mmu.memory[mem_map.interrupt_enable] = 0xFF;
        cpu.registers.r16.pc = mem_map.wram_low;
        cpu.interrupt_master_enable = true;
        executeCPUFor(&cpu, &mmu, 6);
        std.testing.expectEqual(test_case.expected_pc, cpu.registers.r16.pc) catch |err| {
            std.debug.print("Failed Target Test {d}: {s}\n", .{ i, test_case.name });
            return err;
        };
    }

    // TODO: interrupt requests cannot be tested right now.
    // Interrupt request: Joypad: One bit of lower joypad nibble went from 1 to 0.
    // mmio.updateJoypad(&mmu, Def.InputState {
    //     .isDownPressed = false, .isUpPressed = false, .isLeftPressed = false, .isRightPressed = false,
    //     .isStartPressed = false, .isSelectPressed = false, .isBPressed = false, .isAPressed = false,
    // });
    // mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    // mmu.write8_sys(MemMap.JOYPAD, 0b1110_1111);
    // mmio.updateJoypad(&mmu, Def.InputState {
    //     .isDownPressed = true, .isUpPressed = false, .isLeftPressed = false, .isRightPressed = false,
    //     .isStartPressed = false, .isSelectPressed = false, .isBPressed = false, .isAPressed = false,
    // });
    // std.testing.expectEqual(0b0001_0000, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
    //     std.debug.print("Failed: Joypad requests interrupt.\n", .{});
    //     return err;
    // };
    //
    // // TODO: Interrupt request: Serial.
    //
    // // Interrupt request: Timer: TIMA overflows.
    // mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    // mmio.dividerCounter = 0;
    // mmu.write8_sys(MemMap.TIMER, 0xFF);
    // mmu.write8_sys(MemMap.TIMER_CONTROL, 0b0000_0101); // 16 cycles per increment.
    // for(0..16) |_| {
    //     mmio.updateTimers(&mmu);
    // }
    // std.testing.expectEqual(0b0000_0100, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
    //     std.debug.print("Failed: Joypad requests interrupt.\n", .{});
    //     return err;
    // };
    //
    // // Interrupt request: STAT: LY = LYC.
    // mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    // mmu.write8_sys(MemMap.LCD_STAT, 0b0100_0000); // Select LY = LYC.
    // ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    // mmu.write8_sys(MemMap.LCD_CONTROL, 0b1000_0000);
    // mmu.write8_sys(MemMap.LCD_Y, 9);
    // mmu.write8_sys(MemMap.LCD_Y_COMPARE, 10);
    // ppu.step(&mmu, &pixels);
    // std.testing.expectEqual(0b0000_0010, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
    //     std.debug.print("Failed: STAT for LY=LYC requests interrupt.\n", .{});
    //     return err;
    // };
    //
    // // Interrupt request: STAT: Mode 0
    // mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    // mmu.write8_sys(MemMap.LCD_STAT, 0b0000_1000); // Select Mode 0 (HBlank)
    // ppu.lyCounter = 0;
    // ppu.lastSTATLine = false;
    // mmu.write8_sys(MemMap.LCD_Y, 0);
    // while(mmu.read8_sys(MemMap.LCD_Y) == 0) {
    //     ppu.step(&mmu, &pixels);
    // }
    // std.testing.expectEqual(0b0000_0010, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
    //     std.debug.print("Failed: STAT for Mode 0 (HBlank) requests interrupt.\n", .{});
    //     return err;
    // };
    //
    // // Interrupt request: STAT: Mode 1
    // mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    // mmu.write8_sys(MemMap.LCD_STAT, 0b0001_0000); // Select Mode 1 (VBlank)
    // ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    // ppu.lastSTATLine = false;
    // mmu.write8_sys(MemMap.LCD_Y, Def.RESOLUTION_HEIGHT - 1);
    // ppu.step(&mmu, &pixels);
    // // Will trigger VBlank and STAT interrupt!
    // std.testing.expectEqual(0b0000_0011, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
    //     std.debug.print("Failed: STAT for Mode 1 (VBlank) requests interrupt.\n", .{});
    //     return err;
    // };
    //
    // // Interrupt request: STAT: Mode 2
    // mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    // mmu.write8_sys(MemMap.LCD_STAT, 0b0010_0000); // Select Mode 2 (OAMScan)
    // ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    // ppu.lastSTATLine = false;
    // mmu.write8_sys(MemMap.LCD_Y, 0);
    // ppu.step(&mmu, &pixels);
    // std.testing.expectEqual(0b0000_0010, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
    //     std.debug.print("Failed: STAT for Mode 2 (OAMScan) requests interrupt.\n", .{});
    //     return err;
    // };
    //
    // // Interrupt request: STAT: STAT Blocking.
    // mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    // mmu.write8_sys(MemMap.LCD_STAT, 0b0010_1000); // Select Mode 0 (HBlank) and Mode 2 (OAMScan)
    // ppu.lyCounter = 0;
    // mmu.write8_sys(MemMap.LCD_Y, 0);
    // while(mmu.read8_sys(MemMap.INTERRUPT_FLAG) == 0) { // Go until we have an HBlank interrupt.
    //     ppu.step(&mmu, &pixels);
    // }
    // // We now got a HBlank stat interrupt, clear it and try to get an OAMScan Stat interrupt.
    // mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    // while(mmu.read8_sys(MemMap.LCD_Y) == 0) { // Go until we are on the second line
    //     ppu.step(&mmu, &pixels);
    // }
    // std.testing.expectEqual(0b0000_0000, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
    //     std.debug.print("Failed: STAT interrupts are blocked for consecutive STAT sources.\n", .{});
    //     return err;
    // };
    //
    // // Interrupt request: VBlank: Reached VBlank
    // mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    // mmu.write8_sys(MemMap.LCD_STAT, 0b0000_0000); // Select no STAT interrupt
    // ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    // mmu.write8_sys(MemMap.LCD_Y, Def.RESOLUTION_HEIGHT - 1);
    // ppu.step(&mmu, &pixels);
    // std.testing.expectEqual(0b0000_0001, mmu.read8_sys(MemMap.INTERRUPT_FLAG)) catch |err| {
    //     std.debug.print("Failed: VBlank requests interrupt.\n", .{});
    //     return err;
    // };

    // Interrupt priorities: VBlank > LCD > Timer > Serial > Joypad
    mmu.memory[mem_map.interrupt_flag] = 0b0001_1111; // All interrupts are pending.
    mmu.memory[mem_map.interrupt_enable] = 0xFF;
    // Reenable IME for each interrupt vector.
    mmu.memory[mem_map.wram_low] = 0xF3; // DI
    mmu.memory[mem_map.wram_low + 1] = 0xFB; // EI
    mmu.memory[0x40] = 0xFB; // EI
    mmu.memory[0x48] = 0xFB; // EI
    mmu.memory[0x50] = 0xFB; // EI
    mmu.memory[0x58] = 0xFB; // EI
    mmu.memory[0x60] = 0xFB; // EI
    cpu.registers.r16.pc = mem_map.wram_low;
    executeCPUFor(&cpu, &mmu, 1);

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

    for(interruptPrioTests, 0..) |test_case, i| {
        executeCPUFor(&cpu, &mmu, 3);
        std.testing.expectEqual(test_case.expected_if, mmu.memory[mem_map.interrupt_flag]) catch |err| {
            std.debug.print("Failed Interrupt Priority Test {d}: {s}\n", .{ i, test_case.name });
            return err;
        };
    }

    // TODO: Missing Tests:
    // - Spurious Stat Interrupt (DMG Bug). (Only two games depend on this).

}
