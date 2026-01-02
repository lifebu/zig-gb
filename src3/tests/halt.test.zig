const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const CPU = @import("../cpu.zig");
const mem_map = @import("../mem_map.zig");

const cpu_helper = @import("cpu_helper.zig");

pub fn runHaltTests() !void {
    const alloc = std.testing.allocator;

    var memory: std.AutoHashMap(u16, u8) = .init(alloc);
    defer memory.deinit();

    var cpu: CPU.State = .{};
    CPU.init(&cpu, alloc);
    defer CPU.deinit(&cpu, alloc);

    // TODO: Can we combine the code from all of the cases?

    // Halt, IME set, No Interrupt => CPU is halted
    try memory.put(mem_map.wram_low, 0x76); // HALT
    try memory.put(mem_map.wram_low + 1, 0x04); // INC B
    try memory.put(mem_map.interrupt_flag, 0b0000_0000);
    try memory.put(mem_map.interrupt_enable, 0xFF);
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = true;
    cpu.halt_again = false;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_default, 0x76)) catch |err| {
        std.debug.print("Failed: Halt, IME set, No Interrupt => CPU is halted.\n", .{});
        return err;
    };

    // CPU is halted, IME set => Interrupt => ISR loaded.
    try memory.put(mem_map.wram_low, 0x76); // HALT
    try memory.put(mem_map.wram_low + 1, 0x04); // INC B
    try memory.put(mem_map.interrupt_flag, 0b0000_0000);
    try memory.put(mem_map.interrupt_enable, 0xFF);
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = true;
    cpu.halt_again = false;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    // CPU is now halted (as per above test).
    try memory.put(mem_map.interrupt_flag, 0b0001_0000);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_pseudo, 0x04)) catch |err| {
        std.debug.print("Failed: CPU is halted, IME set => Interrupt => ISR loaded\n", .{});
        return err;
    };

    // Halt, IME set, Interrupt => ISR loaded immediately.
    try memory.put(mem_map.wram_low, 0x76); // HALT
    try memory.put(mem_map.wram_low + 1, 0x04); // INC B
    try memory.put(mem_map.interrupt_flag, 0b0000_0000);
    try memory.put(mem_map.interrupt_enable, 0xFF);
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = true;
    cpu.halt_again = false;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try memory.put(mem_map.interrupt_flag, 0b0001_0000);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_pseudo, 0x04)) catch |err| {
        std.debug.print("Failed: Halt, IME set, Interrupt => ISR loaded immediately.\n", .{});
        return err;
    };   

    // Halt, IME unset, No Interrupt => CPU is halted.
    try memory.put(mem_map.wram_low, 0x76); // HALT
    try memory.put(mem_map.wram_low + 1, 0x04); // INC B
    try memory.put(mem_map.interrupt_flag, 0b0000_0000);
    try memory.put(mem_map.interrupt_enable, 0xFF);
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = false;
    cpu.halt_again = false;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_default, 0x76)) catch |err| {
        std.debug.print("Failed: Halt, IME unset, No Interrupt => CPU is halted.\n", .{});
        return err;
    };

    // CPU is halted, IME unset => Interrupt => CPU resumes (no ISR).
    try memory.put(mem_map.wram_low, 0x76); // HALT
    try memory.put(mem_map.wram_low + 1, 0x04); // INC B
    try memory.put(mem_map.interrupt_flag, 0b0000_0000);
    try memory.put(mem_map.interrupt_enable, 0xFF);
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = false;
    cpu.halt_again = false;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    // CPU is now halted (as per above test).
    try memory.put(mem_map.interrupt_flag, 0b0001_0000);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_default, 0x04)) catch |err| {
        std.debug.print("Failed: CPU is halted, IME unset => Interrupt => CPU resumes (no ISR).\n", .{});
        return err;
    };

    // https://github.com/nitro2k01/little-things-gb/tree/main/double-halt-cancel
    // Halt, IME unset, Interrupt => Halt Bug
    // halt -> inc B => halt -> inc B, inc B
    try memory.put(mem_map.wram_low, 0x76); // HALT
    try memory.put(mem_map.wram_low + 1, 0x04); // INC B
    try memory.put(mem_map.wram_low + 2, 0x05); // DEC B
    try memory.put(mem_map.interrupt_flag, 0b0001_0000);
    try memory.put(mem_map.interrupt_enable, 0xFF);
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = false;
    cpu.halt_again = false;
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_default, 0x04)) catch |err| {
        std.debug.print("Failed: Halt, IME unset, Interrupt => Halt Bug. Halt -> inc B. INC B not loaded.\n", .{});
        return err;
    };
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_default, 0x04)) catch |err| {
        std.debug.print("Failed: Halt, IME unset, Interrupt => Halt Bug. Halt -> inc B. INC B not loaded twice.\n", .{});
        return err;
    };
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_default, 0x05)) catch |err| {
        std.debug.print("Failed: Halt, IME unset, Interrupt => Halt Bug. Halt -> inc B. Third time dec b is loaded.\n", .{});
        return err;
    };

    // TODO: More Halt bug tests:
    // Halt, IME unset, Interrupt => Halt Bug
    // halt -> ld B,4 => halt -> ld B,6 -> inc B

    // Halt, IME unset, Interrupt => Halt Bug
    // halt -> rst => rst pushes it's own address on the stack. 

    // Halt, IME unset, Interrupt => Halt Bug
    // halt -> halt => Infinite loop.

    // Halt, IME unset, Interrupt => Halt Bug
    // ei -> halt => ei -> halt -> halt (waits for another interrupt).

    // Halt-Bug: halt -> inc B; halt -> ld B,4; halt -> rst; halt -> halt; ei -> halt
}
