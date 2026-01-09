const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const CPU = @import("../cpu.zig");
const mem_map = @import("../mem_map.zig");

pub fn fetchInstruction(cpu: *CPU, memory: *std.AutoHashMap(u16, u8)) !void {
    cpu.uop_fifo.clear();
    // Load a nop instruction to fetch the required instruction.
    const opcode_bank = CPU.opcode_banks[CPU.opcode_bank_default];
    const uops = opcode_bank[0];
    cpu.uop_fifo.write(uops.items);
    try executeCPUFor(cpu, memory, 4);
}

pub fn executeCPUFor(cpu: *CPU, memory: *std.AutoHashMap(u16, u8), t_cycles: usize) !void {
    for(0..t_cycles) |_| {
        var request: def.Request = .{};
        cpu.cycle(&request);

        const entry: std.AutoHashMap(u16, u8).GetOrPutResult = try memory.getOrPut(request.address);
        switch (request.value) {
            .read => |read| read.* = @bitCast(entry.value_ptr.*),
            .write => |write| entry.value_ptr.* = @bitCast(write),
        }
        if(request.isWrite()) {
            cpu.request(&request);
        }
    }
}

pub fn isFullInstructionLoaded(cpu: *CPU, bank: u2, opcode: u8) bool {
    const alloc = std.testing.allocator;

    const instruction = CPU.opcode_banks[bank][opcode].items;
    std.testing.expectEqual(instruction.len, cpu.uop_fifo.length()) catch {
        std.debug.print("Failed: uop fifo length does not match instruction: [{}][{X:0>2}]\n", .{ bank, opcode });
        return false;
    };

    // TODO: I don't like this buffer to save the read item. Do we add a function to peakContents that returns a slice to the entire array?
    var uop_match: bool = true;
    var uop_buffer = CPU.MicroOpArray{};
    defer uop_buffer.deinit(alloc);

    for(instruction) |instruction_uop| {
        const cpu_uop = cpu.uop_fifo.readItem().?;
        std.testing.expectEqual(instruction_uop.operation, cpu_uop.operation) catch {
            std.debug.print("Failed: cpu uop {} does not match instruction uop {}\n", .{ cpu_uop, instruction_uop });
            uop_match = false;
        };
        uop_buffer.append(alloc, cpu_uop) catch {
            return false; // If we run out of memory during a test we are screwed anyway.
        };
    }
    cpu.uop_fifo.write(uop_buffer.items);
    return uop_match;
}
