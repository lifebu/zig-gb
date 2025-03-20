const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const CPU = @import("../cpu.zig");
const mem_map = @import("../mem_map.zig");

const CPUState = struct {
    program_counter: u16 = 0,
    stack_pointer: u16 = 0,
    a: u8 = 0,
    b: u8 = 0,
    c: u8 = 0,
    d: u8 = 0,
    e: u8 = 0,
    f: u8 = 0,
    h: u8 = 0,
    l: u8 = 0,
    ime: u1 = 0,
    ie: u1 = 0,
    ram: [][]u16, // address (u16), value (u8)
};

const TestType = struct {
    name: []u8,
    initial: CPUState,
    final: CPUState,
    // TODO: Need to figure out the actual type?
    // TODO: Check the CPU pins between each M-Cycle.
    cycles: [][]std.json.Value,
};

fn initializeCpu(cpu: *CPU.State, memory: *[def.addr_space]u8, test_case: *const TestType) !void {
    cpu.program_counter = test_case.initial.program_counter;
    cpu.stack_pointer = test_case.initial.stack_pointer;
    cpu.registers.r8.a = test_case.initial.a;
    cpu.registers.r8.f.f = test_case.initial.f;
    cpu.registers.r8.b = test_case.initial.b;
    cpu.registers.r8.c = test_case.initial.c;
    cpu.registers.r8.d = test_case.initial.d;
    cpu.registers.r8.e = test_case.initial.e;
    cpu.registers.r8.h = test_case.initial.h;
    cpu.registers.r8.l = test_case.initial.l;
    for (test_case.initial.ram) |ramPair| {
        std.debug.assert(ramPair.len == 2);
        const address: u16 = ramPair[0];
        const value: u8 = @intCast(ramPair[1]);
        memory[address] = value;
    }

    // Execute a nop instruction to load the first instruction.
    cpu.uop_fifo.write(CPU.instruction_set[@intFromEnum(CPU.OpCodes.nop)].slice());
    inline for (0..4) |_| {
        CPU.cycle(cpu, memory);
    }
}

fn testOutput(cpu: *const CPU.State, memory: *[def.addr_space]u8, test_case: *const TestType, not_enough_uops: bool) !void {
    try std.testing.expectEqual(false, not_enough_uops);
    try std.testing.expectEqual(cpu.program_counter, test_case.final.program_counter);
    try std.testing.expectEqual(cpu.stack_pointer, test_case.final.stack_pointer);
    try std.testing.expectEqual(cpu.registers.r8.a, test_case.final.a);
    try std.testing.expectEqual(cpu.registers.r8.f.f, test_case.final.f);
    try std.testing.expectEqual(cpu.registers.r8.b, test_case.final.b);
    try std.testing.expectEqual(cpu.registers.r8.c, test_case.final.c);
    try std.testing.expectEqual(cpu.registers.r8.d, test_case.final.d);
    try std.testing.expectEqual(cpu.registers.r8.e, test_case.final.e);
    try std.testing.expectEqual(cpu.registers.r8.h, test_case.final.h);
    try std.testing.expectEqual(cpu.registers.r8.l, test_case.final.l);
    for (test_case.final.ram) |ramPair| {
        std.debug.assert(ramPair.len == 2);
        const address: u16 = ramPair[0];
        const value: u8 = @intCast(ramPair[1]);
        try std.testing.expectEqual(memory[address], value);
    }

    const opcode_name: []u8 = test_case.name[0..2];
    if(std.mem.eql(u8, opcode_name, "76") or std.mem.eql(u8, opcode_name, "10")) {
        return; // Those tests have wrong cycle counts and divert from the actual documentation.
    }
    try std.testing.expectEqual(true, cpu.uop_fifo.isEmpty());
}

fn printTestCase(cpuState: *const CPUState) void {
    std.debug.print("A: {X:0>2} F: {s} {s} {s} {s} ", .{ cpuState.a, 
        if ((cpuState.f & 0x80) == 0x80) "Z" else "_",
        if ((cpuState.f & 0x40) == 0x40) "N" else "_",
        if ((cpuState.f & 0x20) == 0x20) "H" else "_",
        if ((cpuState.f & 0x10) == 0x10) "C" else "_",
    });
    std.debug.print("B: {X:0>2} C: {X:0>2} ", .{ cpuState.b, cpuState.c });
    std.debug.print("D: {X:0>2} E: {X:0>2} ", .{ cpuState.d, cpuState.e });
    std.debug.print("H: {X:0>2} L: {X:0>2} ", .{ cpuState.h, cpuState.l });
    std.debug.print("SP: {X:0>4} PC: {X:0>4}\n", .{ cpuState.stack_pointer, cpuState.program_counter });
    for (cpuState.ram) |ramPair| {
        std.debug.assert(ramPair.len == 2);
        const address: u16 = ramPair[0];
        const value: u8 = @intCast(ramPair[1]);
        std.debug.print("Addr: {X:0>4} val: {X:0>2} ", .{ address, value });
    }
    std.debug.print("\n", .{});
}

pub fn runSingleStepTests() !void {
    const alloc = std.testing.allocator;

    var test_dir: std.fs.Dir = try std.fs.cwd().openDir("test_data/SingleStepTests/v1/", .{ .iterate = true });
    defer test_dir.close();

    var iter: std.fs.Dir.Iterator = test_dir.iterate();
    var idx: u16 = 0;
    while(try iter.next()) |dir_entry| : (idx += 1) {
        std.debug.assert(dir_entry.kind == .file);
        std.debug.print("{d}: Testing: {s}\n", .{idx + 1, dir_entry.name});

        const test_file: []u8 = try test_dir.readFileAlloc(alloc, dir_entry.name, 1 * 1024 * 1024);
        defer alloc.free(test_file);

        const json = try std.json.parseFromSlice([]TestType, alloc, test_file, .{ .ignore_unknown_fields = true });
        defer json.deinit();

        var memory: [def.addr_space]u8 = [1]u8{0} ** def.addr_space;
        var cpu: CPU.State = .{};

        const test_config: []TestType = json.value;
        for(test_config) |test_case| {
            try initializeCpu(&cpu, &memory, &test_case);

            var not_enough_uops: bool = false;
            for(test_case.cycles.len) |_| {
                if(cpu.uop_fifo.isEmpty()) {
                    not_enough_uops = true;
                    break;
                }
                CPU.cycle(&cpu, &memory);
            }

            testOutput(&cpu, &memory, &test_case, not_enough_uops) catch |err| {
                std.debug.print("Test Failed: {s}\n", .{ test_case.name });
                std.debug.print("Initial\n", .{});
                printTestCase(&test_case.initial);
                std.debug.print("\n", .{});
                std.debug.print("Expected\n", .{});
                printTestCase(&test_case.final);
                std.debug.print("Cycles: {d}\n", .{test_case.cycles.len * 4});
                std.debug.print("\n", .{});

                std.debug.print("Got\n", .{});
                std.debug.print("A: {X:0>2} F: {s} {s} {s} {s} ", .{ cpu.registers.r8.a, 
                    if (cpu.registers.r8.f.flags.zero) "Z" else "_",
                    if (cpu.registers.r8.f.flags.n_bcd) "N" else "_",
                    if (cpu.registers.r8.f.flags.half_bcd) "H" else "_",
                    if (cpu.registers.r8.f.flags.carry) "C" else "_",
                });
                std.debug.print("B: {X:0>2} C: {X:0>2} ", .{ cpu.registers.r8.b, cpu.registers.r8.c });
                std.debug.print("D: {X:0>2} E: {X:0>2} ", .{ cpu.registers.r8.d, cpu.registers.r8.e });
                std.debug.print("H: {X:0>2} L: {X:0>2} ", .{ cpu.registers.r8.h, cpu.registers.r8.l });
                std.debug.print("SP: {X:0>4} PC: {X:0>4}\n", .{ cpu.stack_pointer, cpu.program_counter });
                for (test_case.final.ram) |ramPair| {
                    std.debug.assert(ramPair.len == 2);
                    const address: u16 = ramPair[0];
                    const value: u8 = memory[address];
                    std.debug.print("Addr: {X:0>4} val: {X:0>2} ", .{ address, value });
                }
                std.debug.print("\n", .{});
                std.debug.print("CPU had not enough uops: {any}\n", .{ not_enough_uops });
                std.debug.print("CPU uop fifo is empty: {any}\n", .{ cpu.uop_fifo.isEmpty() });
                std.debug.print("\n", .{});

                return err;
            };
        }
    }
}
