const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const CPU = @import("../cpu.zig");
const mem_map = @import("../mem_map.zig");
const MMU = @import("../mmu.zig");

const CPUState = struct {
    pc: u16 = 0,
    sp: u16 = 0,
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
    // TODO: Can we define this array of arrays as an array of structs?
    ram: [][]u16, // address (u16), value (u8)
};

const TestType = struct {
    name: []u8,
    initial: CPUState,
    final: CPUState,
    // TODO: Need to figure out the actual type?
    // TODO: Check the CPU pins between each M-Cycle.
    // TODO: To check the pins, I need a simple mmu that gives the cpu the requested data before I test it.
    cycles: [][]std.json.Value,
};

// TODO: Need to rethink all of the functions and how they are structured. The code is pretty awfull.

fn initializeCpu(cpu: *CPU.State, memory: *[def.addr_space]u8, test_case: *const TestType) !void {
    cpu.registers.r16.pc = test_case.initial.pc;
    cpu.registers.r16.sp = test_case.initial.sp;
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

    cpu.uop_fifo.clear();
    // Load a nop instruction to fetch the required instruction.
    const opcode_bank = CPU.opcode_banks[CPU.opcode_bank_default];
    const uops = opcode_bank[0];
    cpu.uop_fifo.write(uops.slice());
}

fn testOutput(cpu: *const CPU.State, memory: *[def.addr_space]u8, test_case: *const TestType, not_enough_uops: bool, m_cycle_failed: bool) !void {
    try std.testing.expectEqual(false, not_enough_uops);
    try std.testing.expectEqual(false, m_cycle_failed);
    // Note: pc - 1, because we prefetch, the SingleStepTests don't implement that.
    try std.testing.expectEqual(test_case.final.pc, cpu.registers.r16.pc - 1);
    try std.testing.expectEqual(test_case.final.sp, cpu.registers.r16.sp);
    try std.testing.expectEqual(test_case.final.a, cpu.registers.r8.a);
    try std.testing.expectEqual(test_case.final.f, cpu.registers.r8.f.f);
    try std.testing.expectEqual(test_case.final.b, cpu.registers.r8.b);
    try std.testing.expectEqual(test_case.final.c, cpu.registers.r8.c);
    try std.testing.expectEqual(test_case.final.d, cpu.registers.r8.d);
    try std.testing.expectEqual(test_case.final.e, cpu.registers.r8.e);
    try std.testing.expectEqual(test_case.final.h, cpu.registers.r8.h);
    try std.testing.expectEqual(test_case.final.l, cpu.registers.r8.l);
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
    // TODO: We cannot this this like this because we prefetch the next instruction.
    // try std.testing.expectEqual(true, cpu.uop_fifo.isEmpty());
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
    std.debug.print("SP: {X:0>4} PC: {X:0>4}\n", .{ cpuState.sp, cpuState.pc });
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

        var cpu: CPU.State = .{};
        var mmu: MMU.State = .{}; 

        const test_config: []TestType = json.value;
        for(test_config) |test_case| {
            try initializeCpu(&cpu, &mmu.memory, &test_case);

            const num_m_cycles = 1 + test_case.cycles.len;

            // TODO: This is a pretty bad solution.
            var not_enough_uops: bool = false;
            // TODO: Should we also include the state of the cpu pins when we failed?
            const m_cycle_fail_index: usize = 0;
            const m_cycle_failed: bool = false;

            for(0..num_m_cycles) |_| {
                if(cpu.uop_fifo.length() < 4) {
                    not_enough_uops = true;
                    break;
                }

                inline for(0..4) |_| {
                    CPU.cycle(&cpu, &mmu);
                    MMU.cycle(&mmu);
                }
                
                // TODO: Ignore M-Cycle mmmu test for now. This does not work because the cpu is removing the request after it has been handled.
                // const m_cycle_values = test_case.cycles[m_cycle];
                // const expected_address: u16 = @intCast(m_cycle_values[0].integer);
                // const expected_dbus: u8 = @intCast(m_cycle_values[1].integer);
                // const expected_request: []const u8 = m_cycle_values[2].string;
                // 
                // const got_address: u16 = mmu.request.getAddress();
                //
                // if(expected_address != got_address 
                //         or expected_dbus != mmu.request.data 
                //         or std.mem.eql(u8, expected_request, mmu.request.print())) {
                //     m_cycle_failed = true;
                //     m_cycle_fail_index = m_cycle;
                //     break;
                // }
            }

            // TODO: Maybe instead of a giant block of text I can just print out the issues that I had?
            testOutput(&cpu, &mmu.memory, &test_case, not_enough_uops, m_cycle_failed) catch |err| {
                std.debug.print("Test Failed: {s}\n", .{ test_case.name });
                std.debug.print("Initial\n", .{});
                printTestCase(&test_case.initial);
                std.debug.print("\n", .{});
                std.debug.print("Expected\n", .{});
                printTestCase(&test_case.final);
                std.debug.print("Cycles: {d}\n", .{test_case.cycles.len * 4});
                // TODO: Print the M-Cycle data?
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
                // Note: pc - 1, because we prefetch, the SingleStepTests don't implement that.
                std.debug.print("SP: {X:0>4} PC: {X:0>4}\n", .{ cpu.registers.r16.sp, cpu.registers.r16.pc - 1 });
                for (test_case.final.ram) |ramPair| {
                    std.debug.assert(ramPair.len == 2);
                    const address: u16 = ramPair[0];
                    const value: u8 = mmu.memory[address];
                    std.debug.print("Addr: {X:0>4} val: {X:0>2} ", .{ address, value });
                }
                std.debug.print("\n", .{});
                std.debug.print("CPU had not enough uops: {any}\n", .{ not_enough_uops });
                // TODO: We cannot this this like this because we prefetch the next instruction.
                // std.debug.print("CPU uop fifo is empty: {any}\n", .{ cpu.uop_fifo.isEmpty() });
                std.debug.print("\n", .{});
                if(m_cycle_failed) {
                    std.debug.print("M-Cycle test failed\n", .{});
                    std.debug.print("Expected\n", .{});
                    const m_cycle_values = test_case.cycles[m_cycle_fail_index];
                    std.debug.print("addr: {X:0>4}, dbus: {X:0>2}, request: {s}\n", .{ 
                        m_cycle_values[0].integer, m_cycle_values[1].integer, m_cycle_values[2].string 
                    });

                    std.debug.print("Got\n", .{});
                    std.debug.print("addr: {X:0>4}, dbus: {X:0>2}, request: {s}\n", .{ 
                        mmu.request.getAddress(), mmu.request.data, mmu.request.print() 
                    });
                }

                return err;
            };
        }
    }
}
