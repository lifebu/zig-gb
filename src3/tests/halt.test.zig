const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const CPU = @import("../cpu.zig");
const mem_map = @import("../mem_map.zig");

const cpu_helper = @import("cpu_helper.zig");

pub fn init(cpu: *CPU, memory: *std.AutoHashMap(u16, u8), wram: []const u8) !void {
    memory.clearRetainingCapacity();
    for (wram, 0..) |value, idx| {
        try memory.put(@intCast(mem_map.wram_low + idx), value);
    }
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.halt_again = false;
}

pub fn runHaltTests() !void {
    const alloc = std.testing.allocator;

    var memory: std.AutoHashMap(u16, u8) = .init(alloc);
    defer memory.deinit();

    var cpu: CPU = .{};
    cpu.init(alloc);
    defer cpu.deinit(alloc);

    // TODO: Can we combine the code from all of the cases?

    // Halt, IME set, No Interrupt => CPU is halted
    try init(&cpu, &memory, &.{ 0x76, 0x04 }); // HALT -> INC B
    cpu.interrupt_master_enable = true;
    cpu.interrupt_flag = .{ .bits = .{ .timer = false, .joypad = false, .lcd_stat = false, .serial = false, .v_blank = false } };
    cpu.interrupt_enable = .{ .bits = .{ .timer = true, .joypad = true, .lcd_stat = true, .serial = true, .v_blank = true } };
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_default, 0x76)) catch |err| {
        std.debug.print("Failed: Halt, IME set, No Interrupt => CPU is halted.\n", .{});
        return err;
    };

    // CPU is halted, IME set => Interrupt => ISR loaded.
    try init(&cpu, &memory, &.{ 0x76, 0x04 }); // HALT -> INC B
    cpu.interrupt_master_enable = true;
    cpu.interrupt_flag = .{ .bits = .{ .timer = false, .joypad = false, .lcd_stat = false, .serial = false, .v_blank = false } };
    cpu.interrupt_enable = .{ .bits = .{ .timer = true, .joypad = true, .lcd_stat = true, .serial = true, .v_blank = true } };
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    cpu.interrupt_flag = .{ .bits = .{ .timer = true, .joypad = false, .lcd_stat = false, .serial = false, .v_blank = false } };
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_pseudo, 0x04)) catch |err| {
        std.debug.print("Failed: CPU is halted, IME set => Interrupt => ISR loaded\n", .{});
        return err;
    };

    // Halt, IME set, Interrupt => ISR loaded immediately.
    try init(&cpu, &memory, &.{ 0x76, 0x04 }); // HALT -> INC B
    cpu.interrupt_master_enable = true;
    cpu.interrupt_flag = .{ .bits = .{ .timer = false, .joypad = false, .lcd_stat = false, .serial = false, .v_blank = false } };
    cpu.interrupt_enable = .{ .bits = .{ .timer = true, .joypad = true, .lcd_stat = true, .serial = true, .v_blank = true } };
    try cpu_helper.fetchInstruction(&cpu, &memory);
    cpu.interrupt_flag = .{ .bits = .{ .timer = true, .joypad = false, .lcd_stat = false, .serial = false, .v_blank = false } };
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_pseudo, 0x04)) catch |err| {
        std.debug.print("Failed: Halt, IME set, Interrupt => ISR loaded immediately.\n", .{});
        return err;
    };   

    // Halt, IME unset, No Interrupt => CPU is halted.
    try init(&cpu, &memory, &.{ 0x76, 0x04 }); // HALT -> INC B
    cpu.interrupt_master_enable = false;
    cpu.interrupt_flag = .{ .bits = .{ .timer = false, .joypad = false, .lcd_stat = false, .serial = false, .v_blank = false } };
    cpu.interrupt_enable = .{ .bits = .{ .timer = true, .joypad = true, .lcd_stat = true, .serial = true, .v_blank = true } };
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_default, 0x76)) catch |err| {
        std.debug.print("Failed: Halt, IME unset, No Interrupt => CPU is halted.\n", .{});
        return err;
    };

    // CPU is halted, IME unset => Interrupt => CPU resumes (no ISR).
    try init(&cpu, &memory, &.{ 0x76, 0x04 }); // HALT -> INC B
    cpu.interrupt_master_enable = false;
    cpu.interrupt_flag = .{ .bits = .{ .timer = false, .joypad = false, .lcd_stat = false, .serial = false, .v_blank = false } };
    cpu.interrupt_enable = .{ .bits = .{ .timer = true, .joypad = true, .lcd_stat = true, .serial = true, .v_blank = true } };
    try cpu_helper.fetchInstruction(&cpu, &memory);
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    cpu.interrupt_flag = .{ .bits = .{ .timer = true, .joypad = false, .lcd_stat = false, .serial = false, .v_blank = false } };
    try cpu_helper.executeCPUFor(&cpu, &memory, 1 * def.t_cycles_per_m_cycle);
    std.testing.expectEqual(true, cpu_helper.isFullInstructionLoaded(&cpu, CPU.opcode_bank_default, 0x04)) catch |err| {
        std.debug.print("Failed: CPU is halted, IME unset => Interrupt => CPU resumes (no ISR).\n", .{});
        return err;
    };

    // https://github.com/nitro2k01/little-things-gb/tree/main/double-halt-cancel
    // Halt, IME unset, Interrupt => Halt Bug
    // halt -> inc B => halt -> inc B, inc B
    try init(&cpu, &memory, &.{ 0x76, 0x04, 0x05 }); // HALT -> INC B -> DEC B
    cpu.interrupt_master_enable = false;
    cpu.interrupt_flag = .{ .bits = .{ .timer = false, .joypad = false, .lcd_stat = false, .serial = false, .v_blank = true } };
    cpu.interrupt_enable = .{ .bits = .{ .timer = true, .joypad = true, .lcd_stat = true, .serial = true, .v_blank = true } };
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
