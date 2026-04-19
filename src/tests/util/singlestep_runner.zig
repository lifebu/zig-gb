const std = @import("std");
const assert = std.debug.assert;

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../../defines.zig");
const CPU = @import("../../cpu.zig");
const cpu_helper = @import("cpu_helper.zig");

const CPUState = struct {
    pc: u16 = 0, sp: u16 = 0,
    a: u8 = 0, b: u8 = 0,
    c: u8 = 0, d: u8 = 0,
    e: u8 = 0, f: u8 = 0,
    h: u8 = 0, l: u8 = 0,
    ime: u1 = 0, ie: u1 = 0,
    ram: [][]u16, // address (u16), value (u8)

    fn toRegisterFile(self: CPUState) CPU.RegisterFile {
        return .{ .r8 = .{ 
            .c = self.c, .b = self.b,
            .e = self.e, .d = self.d,
            .l = self.l, .h = self.h,
            .z = 0, .w = 0,
            .pcl = @truncate(self.pc), .pch = @truncate(self.pc >> 8), 
            .spl = @truncate(self.sp), .sph = @truncate(self.sp >> 8), 
            .ir = 0, .dbus = 0,
            .f = @bitCast(self.f), .a = self.a,
            .p = .{}, .u = 0,
        }, };
    }
    pub fn format(self: CPUState, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const registers: CPU.RegisterFile = self.toRegisterFile();
        try writer.print("{f}", .{ registers });
        for (self.ram) |ramPair| {
            const value: u8 = @intCast(ramPair[1]);
            try writer.print("Addr: {X:0>4} ({s}), val: {X:0>2}; ", .{ ramPair[0], def.getMemoryRangeName(ramPair[0]), value });
        }
    }
};
const TestCase = struct {
    name: []u8,
    initial: CPUState,
    final: CPUState,
    // TODO: Check the CPU requests between each M-Cycle.
    cycles: [][]std.json.Value,
};

pub fn run(path: []const u8) !void {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    var cpu: CPU = .{};
    cpu.init(alloc, false);
    defer cpu.deinit(alloc);

    var memory_map: std.AutoHashMap(u16, u8) = .init(alloc);
    defer memory_map.deinit();

    const file_content: []u8 = std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited) catch unreachable;
    defer alloc.free(file_content);

    const json = try std.json.parseFromSlice([]TestCase, alloc, file_content, .{ .ignore_unknown_fields = true });
    defer json.deinit();

    for(json.value) |test_case| {
        memory_map.clearRetainingCapacity();
        for (test_case.initial.ram) |ramPair| {
            const value: u8 = @intCast(ramPair[1]);
            try memory_map.put(ramPair[0], value);
        }

        cpu.interrupt_master_enable = false;
        cpu.registers = test_case.initial.toRegisterFile();
        try cpu_helper.fetchInstruction(&cpu, &memory_map);

        var not_enough_uops: bool = false;
        for(test_case.cycles) |_| {
            if(cpu.uop_fifo.length() < def.t_cycles_per_m_cycle) {
                not_enough_uops = true;
                break;
            }
            try cpu_helper.executeCPUFor(&cpu, &memory_map, def.t_cycles_per_m_cycle);
        }

        errdefer {
            std.debug.print("Initial\n{f}\n\n", .{ test_case.initial });
            std.debug.print("Expected\n{f}\n", .{ test_case.final });
            std.debug.print("Cycles: {d}\n\n", .{test_case.cycles.len * def.t_cycles_per_m_cycle});

            // Note: pc - 1, because we prefetch, the SingleStepTests don't implement that.
            cpu.registers.r16.pc -%= 1;
            std.debug.print("Got\n{f}\n", .{ cpu.registers });
            for (test_case.final.ram) |ramPair| {
                std.debug.print("Addr: {X:0>4} ({s}), val: {X:0>2}; ", .{ ramPair[0], def.getMemoryRangeName(ramPair[0]), memory_map.get(ramPair[0]).? });
            }
            std.debug.print("\n", .{});
            std.debug.print("CPU had not enough uops: {any}\n", .{ not_enough_uops });
            std.debug.print("\n", .{});

            const prefix: u16 = test_case.initial.ram[0][1];
            const bank_idx: u3 = if(prefix == 0xCB) CPU.opcode_bank_prefix else CPU.opcode_bank_default;
            const opcode: u16 = if(prefix == 0xCB) (test_case.initial.ram[1][1]) else prefix;
            const micro_ops = cpu.opcode_banks[bank_idx][opcode];

            std.debug.print("MicroOps Op: [{}][{X:0>2}]\n", .{ bank_idx, opcode });
            for(micro_ops.items, 1..) |op, op_idx| {
                std.debug.print("{f}, ", .{ op });
                if ((op_idx % 4) == 0) {
                    std.debug.print("\n", .{});
                }
            }
            std.debug.print("\n", .{});
        }

        try std.testing.expectEqual(false, not_enough_uops);
        // Note: pc - 1, because we prefetch, the SingleStepTests don't implement that.
        try std.testing.expectEqual(test_case.final.pc, cpu.registers.r16.pc -% 1);
        try std.testing.expectEqual(test_case.final.sp, cpu.registers.r16.sp);
        try std.testing.expectEqual(test_case.final.a, cpu.registers.r8.a);
        const expected_flags: CPU.FlagRegister = @bitCast(test_case.final.f); 
        try std.testing.expectEqual(expected_flags.carry, cpu.registers.r8.f.carry);
        try std.testing.expectEqual(expected_flags.half_bcd, cpu.registers.r8.f.half_bcd);
        try std.testing.expectEqual(expected_flags.n_bcd, cpu.registers.r8.f.n_bcd);
        try std.testing.expectEqual(expected_flags.zero, cpu.registers.r8.f.zero);
        try std.testing.expectEqual(0, cpu.registers.r8.p.const_zero);
        try std.testing.expectEqual(1, cpu.registers.r8.p.const_one);
        try std.testing.expectEqual(test_case.final.b, cpu.registers.r8.b);
        try std.testing.expectEqual(test_case.final.c, cpu.registers.r8.c);
        try std.testing.expectEqual(test_case.final.d, cpu.registers.r8.d);
        try std.testing.expectEqual(test_case.final.e, cpu.registers.r8.e);
        try std.testing.expectEqual(test_case.final.h, cpu.registers.r8.h);
        try std.testing.expectEqual(test_case.final.l, cpu.registers.r8.l);
        try std.testing.expectEqual(0, cpu.registers.r8.p.const_zero);
        try std.testing.expectEqual(1, cpu.registers.r8.p.const_one);
        for (test_case.final.ram) |ramPair| {
            const value: u8 = @intCast(ramPair[1]);
            try std.testing.expectEqual(value, memory_map.get(ramPair[0]).?);
        }
    }
}

