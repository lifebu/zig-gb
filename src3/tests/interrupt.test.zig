const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const CPU = @import("../cpu.zig");
const mem_map = @import("../mem_map.zig");

const cpu_helper = @import("cpu_helper.zig");

pub fn runInterruptTests() !void {
    const alloc = std.testing.allocator;

    var memory: std.AutoHashMap(u16, u8) = .init(alloc);
    defer memory.deinit();

    var cpu: CPU.State = .{};
    CPU.init(&cpu, alloc);
    defer CPU.deinit(&cpu, alloc);

    // CPU can write to IF.
    try memory.put(mem_map.wram_low, 0x77); // LD (HL), A
    cpu.interrupt_flag.value = 0b0000_0000;
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.registers.r16.hl = mem_map.interrupt_flag;
    cpu.registers.r8.a = 0xFF;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(0xFF, cpu.interrupt_flag.value) catch |err| {
        std.debug.print("Failed: CPU can write to IF.\n", .{});
        return err;
    };

    // IME is reset by DI.
    try memory.put(mem_map.wram_low, 0xF3); // DI
    cpu.interrupt_master_enable = true;
    cpu.registers.r16.pc = mem_map.wram_low;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(false, cpu.interrupt_master_enable) catch |err| {
        std.debug.print("Failed: DI disables IME.\n", .{});
        return err;
    };

    // IME is set by RETI
    try memory.put(mem_map.wram_low, 0xD9); // RETI
    cpu.interrupt_master_enable = false;
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.registers.r16.sp = mem_map.wram_high;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 4 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu.interrupt_master_enable) catch |err| {
        std.debug.print("Failed: RETI enables IME.\n", .{});
        return err;
    };

    // IME is set by EI
    try memory.put(mem_map.wram_low, 0xFB); // EI
    cpu.interrupt_master_enable = false;
    cpu.registers.r16.pc = mem_map.wram_low;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu.interrupt_master_enable) catch |err| {
        std.debug.print("Failed: EI enabled IME.\n", .{});
        return err;
    };

    // Effect of EI is delayed.
    try memory.put(mem_map.wram_low, 0xFB); // EI
    try memory.put(mem_map.wram_low + 1, 0x04); // INC B
    cpu.interrupt_flag.value = 0b0001_0000;
    cpu.interrupt_enable.value = 0xFF;
    cpu.interrupt_master_enable = false;
    cpu.registers.r16.pc = mem_map.wram_low;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_default, 0x04)) catch |err| {
        std.debug.print("Failed: Effect of EI is delayed: Interrupt immediately handled.\n", .{});
        return err;
    };
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_pseudo, 0x04)) catch |err| {
        std.debug.print("Failed: Effect of EI is delayed: Interrupt handler not loaded.\n", .{});
        return err;
    };

    // IME is reset by the interrupt handler
    cpu.interrupt_flag.value = 0b0001_0000;
    cpu.interrupt_enable.value = 0xFF;
    cpu.interrupt_master_enable = true;
    cpu.registers.r16.pc = mem_map.wram_low;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 5 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(false, cpu.interrupt_master_enable) catch |err| {
        std.debug.print("Failed: CPU disables IME during interrupt handling.\n", .{});
        return err;
    };

    // Interrupts are executed immediately and not delayed
    try memory.put(mem_map.wram_low, 0x04); // INC B
    cpu.interrupt_flag.value = 0b0000_0000;
    cpu.interrupt_enable.value = 0xFF;
    cpu.interrupt_master_enable = true;
    cpu.registers.r16.pc = mem_map.wram_low;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 2);
    cpu.interrupt_flag.value = 0b0001_0000;
    try cpu_helper.executeCPUFor(&cpu, &memory, 2);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_pseudo, 0x04)) catch |err| {
        std.debug.print("Failed: Interrupts are handled immediately and not delayed.\n", .{});
        return err;
    };

    // After the instruction handler, the instruction after the target is loaded.
    try memory.put(0x60, 0x04); // INC B
    cpu.interrupt_flag.value = 0b0001_0000;
    cpu.interrupt_enable.value = 0xFF;
    cpu.interrupt_master_enable = true;
    cpu.registers.r16.pc = mem_map.wram_low;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 5 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_default, 0x04)) catch |err| {
        std.debug.print("Failed: After the interrupt hander, the next instruction after the target is loaded.\n", .{});
        return err;
    };

    // The pc of the next instruction is saved to the stack by the ISR.
    try memory.put(mem_map.wram_low, 0x04); // INC B
    try memory.put(mem_map.wram_low + 1, 0x04); // INC B
    try memory.put(mem_map.wram_low + 2, 0x04); // INC B
    try memory.put(mem_map.wram_low + 3, 0x04); // INC B
    cpu.interrupt_flag.value = 0b0000_0000;
    cpu.interrupt_enable.value = 0xFF;
    cpu.interrupt_master_enable = true;
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.registers.r16.sp = mem_map.hram_high;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle); // execute: wram_low
    cpu.interrupt_flag.value = 0b0001_0000;
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle); // execute: wram_low + 1 
    try cpu_helper.executeCPUFor(&cpu, &memory, 5 * def.t_cycles_per_m_cycle); // execute: ISR
    const pch: u16 = cpu.hram[(mem_map.hram_high - 1) - mem_map.hram_low]; 
    const pcl: u16 = cpu.hram[(mem_map.hram_high - 2) - mem_map.hram_low]; 
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
        cpu.registers.r16.pc = mem_map.wram_low;
        cpu.interrupt_flag.value = test_case.interupt_flag;
        cpu.interrupt_enable.value = 0xFF;
        cpu.interrupt_master_enable = true;
        try cpu_helper.fetchInstruction(&cpu, &memory);
        try cpu_helper.executeCPUFor(&cpu, &memory, 5 * def.t_cycles_per_m_cycle);
        std.testing.expectEqual(test_case.expected_pc + 1, cpu.registers.r16.pc) catch |err| {
            std.debug.print("Failed Target Test {d}: {s}\n", .{ i, test_case.name });
            std.debug.print("Expected PC: {X:0>4}\n", .{ test_case.expected_pc });
            std.debug.print("Result   PC: {X:0>4}\n", .{ cpu.registers.r16.pc });
            return err;
        };
    }

    // Interrupt priorities: VBlank > LCD > Timer > Serial > Joypad
    cpu.interrupt_flag.value = 0b0001_1111; // ALl interrupts are pending.
    cpu.interrupt_enable.value = 0xFF;
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
        try cpu_helper.fetchInstruction(&cpu, &memory);
        std.testing.expectEqual(test_case.expected_if, cpu.interrupt_flag.value) catch |err| {
            std.debug.print("Failed Interrupt Priority Test {d}: {s}\n", .{ i, test_case.name });
            std.debug.print("Expected IF: {b}\n", .{ test_case.expected_if });
            std.debug.print("Result   IF: {b}\n", .{ cpu.interrupt_flag.value });
            return err;
        };
    }

    // TODO: Missing Tests:
    // - Spurious Stat Interrupt (DMG Bug). (Only two games depend on this).
    // https://gbdev.io/pandocs/STAT.html?highlight=STAT#ff41--stat-lcd-status
}
