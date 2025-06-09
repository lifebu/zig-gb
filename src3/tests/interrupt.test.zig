const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const CPU = @import("../cpu.zig");
const mem_map = @import("../mem_map.zig");
const MMU = @import("../mmu.zig");

const cpu_helper = @import("cpu_helper.zig");

pub fn runInterruptTests() !void {
    var mmu: MMU.State = .{}; 
    var cpu: CPU.State = .{};
    CPU.init(&cpu);

    // CPU can write to IF.
    mmu.memory[mem_map.interrupt_flag] = 0b0000_0000;
    mmu.memory[mem_map.wram_low] = 0x77; // LD (HL), A
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.registers.r16.hl = mem_map.interrupt_flag;
    cpu.registers.r8.a = 0xFF;
    cpu_helper.fetchInstruction(&cpu, &mmu);
    cpu_helper.executeCPUFor(&cpu, &mmu, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(0xFF, mmu.memory[mem_map.interrupt_flag]) catch |err| {
        std.debug.print("Failed: CPU can write to IF.\n", .{});
        return err;
    };

    // IME is reset by DI.
    mmu.memory[mem_map.wram_low] = 0xF3; // DI
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = true;
    cpu_helper.fetchInstruction(&cpu, &mmu);
    cpu_helper.executeCPUFor(&cpu, &mmu, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(false, cpu.interrupt_master_enable) catch |err| {
        std.debug.print("Failed: DI disables IME.\n", .{});
        return err;
    };

    // IME is set by RETI
    mmu.memory[mem_map.wram_low] = 0xD9; // RETI
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.registers.r16.sp = mem_map.wram_high;
    cpu.interrupt_master_enable = false;
    cpu_helper.fetchInstruction(&cpu, &mmu);
    cpu_helper.executeCPUFor(&cpu, &mmu, 4 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu.interrupt_master_enable) catch |err| {
        std.debug.print("Failed: RETI enables IME.\n", .{});
        return err;
    };

    // IME is set by EI
    mmu.memory[mem_map.wram_low] = 0xFB; // EI
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = false;
    cpu_helper.fetchInstruction(&cpu, &mmu);
    cpu_helper.executeCPUFor(&cpu, &mmu, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu.interrupt_master_enable) catch |err| {
        std.debug.print("Failed: EI enabled IME.\n", .{});
        return err;
    };

    // Effect of EI is delayed.
    mmu.memory[mem_map.interrupt_flag] = 0b0001_0000;
    mmu.memory[mem_map.interrupt_enable] = 0xFF;
    mmu.memory[mem_map.wram_low] = 0xFB; // EI
    mmu.memory[mem_map.wram_low + 1] = 0x04; // INC B
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = false;
    cpu_helper.fetchInstruction(&cpu, &mmu);
    cpu_helper.executeCPUFor(&cpu, &mmu, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_default, 0x04)) catch |err| {
        std.debug.print("Failed: Effect of EI is delayed: Interrupt immediately handled.\n", .{});
        return err;
    };
    cpu_helper.executeCPUFor(&cpu, &mmu, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_pseudo, 0x04)) catch |err| {
        std.debug.print("Failed: Effect of EI is delayed: Interrupt handler not loaded.\n", .{});
        return err;
    };

    // IME is reset by the interrupt handler
    mmu.memory[mem_map.interrupt_flag] = 0b0001_0000;
    mmu.memory[mem_map.interrupt_enable] = 0xFF;
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = true;
    cpu_helper.fetchInstruction(&cpu, &mmu);
    cpu_helper.executeCPUFor(&cpu, &mmu, 5 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(false, cpu.interrupt_master_enable) catch |err| {
        std.debug.print("Failed: CPU disables IME during interrupt handling.\n", .{});
        return err;
    };

    // Interrupts are executed immediately and not delayed
    mmu.memory[mem_map.interrupt_flag] = 0b0000_0000;
    mmu.memory[mem_map.interrupt_enable] = 0xFF;
    mmu.memory[mem_map.wram_low] = 0x04; // INC B
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = true;
    cpu_helper.fetchInstruction(&cpu, &mmu);
    cpu_helper.executeCPUFor(&cpu, &mmu, 2);
    mmu.memory[mem_map.interrupt_flag] = 0b0001_0000;
    cpu_helper.executeCPUFor(&cpu, &mmu, 2);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_pseudo, 0x04)) catch |err| {
        std.debug.print("Failed: Interrupts are handled immediately and not delayed.\n", .{});
        return err;
    };

    // After the instruction handler, the instruction after the target is loaded.
    mmu.memory[mem_map.interrupt_flag] = 0b0001_0000;
    mmu.memory[mem_map.interrupt_enable] = 0xFF;
    mmu.memory[0x60] = 0x04; // INC B
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = true;
    cpu_helper.fetchInstruction(&cpu, &mmu);
    cpu_helper.executeCPUFor(&cpu, &mmu, 5 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_default, 0x04)) catch |err| {
        std.debug.print("Failed: After the interrupt hander, the next instruction after the target is loaded.\n", .{});
        return err;
    };

    // The pc of the next instruction is saved to the stack by the ISR.
    mmu.memory[mem_map.interrupt_flag] = 0b0000_0000;
    mmu.memory[mem_map.interrupt_enable] = 0xFF;
    mmu.memory[mem_map.wram_low] = 0x04; // INC B
    mmu.memory[mem_map.wram_low + 1] = 0x04; // INC B
    mmu.memory[mem_map.wram_low + 2] = 0x04; // INC B
    mmu.memory[mem_map.wram_low + 3] = 0x04; // INC B
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.registers.r16.sp = mem_map.hram_high;
    cpu.interrupt_master_enable = true;
    cpu_helper.fetchInstruction(&cpu, &mmu);
    cpu_helper.executeCPUFor(&cpu, &mmu, 1 * def.t_cycles_per_m_cycle); // execute: wram_low
    mmu.memory[mem_map.interrupt_flag] = 0b0001_0000;
    cpu_helper.executeCPUFor(&cpu, &mmu, 1 * def.t_cycles_per_m_cycle); // execute: wram_low + 1 
    cpu_helper.executeCPUFor(&cpu, &mmu, 5 * def.t_cycles_per_m_cycle); // execute: ISR
    const pch: u16 = mmu.memory[mem_map.hram_high - 1]; 
    const pcl: u16 = mmu.memory[mem_map.hram_high - 2]; 
    const written_pc: u16 = pch << 8 | pcl;
    const expected_pc: u16 = mem_map.wram_low + 2;
    std.testing.expectEqual(expected_pc, written_pc) catch |err| {
        std.debug.print("Failed: The pc of the next instruction is saved to the stack by the ISR..\n", .{});
        return err;
    };

    // Interrupt targets
    const InterruptTargetTest = struct {
        name: []const u8,
        interupt_flag: u8,
        expected_pc: u16,
    };
    const interruptTargetTests = [_]InterruptTargetTest {
        .{ .name = "Joypad interrupt target: 0x60", .interupt_flag = 0b0001_0000, .expected_pc = 0x60 },
        .{ .name = "Serial interrupt target: 0x58", .interupt_flag = 0b0000_1000, .expected_pc = 0x58 },
        .{ .name = "Timer interrupt target: 0x50", .interupt_flag = 0b0000_0100, .expected_pc = 0x50 },
        .{ .name = "STAT interrupt target: 0x48", .interupt_flag = 0b0000_0010, .expected_pc = 0x48 },
        .{ .name = "VBlank interrupt target: 0x40", .interupt_flag = 0b0000_0001, .expected_pc = 0x40 },
    };
    for(interruptTargetTests, 0..) |test_case, i| {
        mmu.memory[mem_map.interrupt_flag] = test_case.interupt_flag;
        mmu.memory[mem_map.interrupt_enable] = 0xFF;
        cpu.registers.r16.pc = mem_map.wram_low;
        cpu.interrupt_master_enable = true;
        cpu_helper.fetchInstruction(&cpu, &mmu);
        cpu_helper.executeCPUFor(&cpu, &mmu, 5 * def.t_cycles_per_m_cycle);
        std.testing.expectEqual(test_case.expected_pc + 1, cpu.registers.r16.pc) catch |err| {
            std.debug.print("Failed Target Test {d}: {s}\n", .{ i, test_case.name });
            std.debug.print("Expected PC: {X:0>4}\n", .{ test_case.expected_pc });
            std.debug.print("Result   PC: {X:0>4}\n", .{ cpu.registers.r16.pc });
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
    cpu.interrupt_master_enable = true;

    const InterruptPrioTest = struct {
        name: []const u8,
        expected_if: u8,
    };
    const interruptPrioTests = [_]InterruptPrioTest {
        .{ .name = "VBlank handled first", .expected_if = 0b0001_1110 },
        .{ .name = "LCD handled second", .expected_if = 0b0001_1100 },
        .{ .name = "Timer handled third", .expected_if = 0b0001_1000 },
        .{ .name = "Serial handled fourth", .expected_if = 0b0001_0000 },
        .{ .name = "Joypad handled fifth", .expected_if = 0b0000_0000 },
    };
    for(interruptPrioTests, 0..) |test_case, i| {
        cpu_helper.fetchInstruction(&cpu, &mmu);
        std.testing.expectEqual(test_case.expected_if, mmu.memory[mem_map.interrupt_flag]) catch |err| {
            std.debug.print("Failed Interrupt Priority Test {d}: {s}\n", .{ i, test_case.name });
            std.debug.print("Expected IF: {b}\n", .{ test_case.expected_if });
            std.debug.print("Result   IF: {b}\n", .{ mmu.memory[mem_map.interrupt_flag] });
            return err;
        };
    }

    // TODO: Missing Tests:
    // - Spurious Stat Interrupt (DMG Bug). (Only two games depend on this).
    // https://gbdev.io/pandocs/STAT.html?highlight=STAT#ff41--stat-lcd-status
}
