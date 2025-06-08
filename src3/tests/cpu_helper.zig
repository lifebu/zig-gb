const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const CPU = @import("../cpu.zig");
const mem_map = @import("../mem_map.zig");
const MMU = @import("../mmu.zig");

pub fn fetchInstruction(cpu: *CPU.State, mmu: *MMU.State) void {
    cpu.uop_fifo.clear();
    // Load a nop instruction to fetch the required instruction.
    const opcode_bank = CPU.opcode_banks[CPU.opcode_bank_default];
    const uops = opcode_bank[0];
    cpu.uop_fifo.write(uops.slice());
    executeCPUFor(cpu, mmu, 4);
}

pub fn executeCPUFor(cpu: *CPU.State, mmu: *MMU.State, t_cycles: usize) void {
    for(0..t_cycles) |_| {
        CPU.cycle(cpu, mmu);
        MMU.cycle(mmu);
    }
}

pub fn isFullInstructionLoaded(cpu: *CPU.State, bank: u2, opcode: u8) bool {
    const instruction = CPU.opcode_banks[bank][opcode].slice();
    std.testing.expectEqual(instruction.len, cpu.uop_fifo.length()) catch {
        std.debug.print("Failed: uop fifo length does not match instruction: [{}][{X:0>2}]\n", .{ bank, opcode });
        return false;
    };
    for(instruction) |instruction_uop| {
        const cpu_uop = cpu.uop_fifo.readItem().?;
        std.testing.expectEqual(instruction_uop.operation, cpu_uop.operation) catch {
            std.debug.print("Failed: cpu uop {} does not match instruction uop {}\n", .{ cpu_uop, instruction_uop });
            return false;
        };
    }
    return true;
}
