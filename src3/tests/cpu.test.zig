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
    ram: [][]u16, // address (u16), value (u8)
};

const TestType = struct {
    name: []u8,
    initial: CPUState,
    final: CPUState,
    // TODO: Check the CPU pins between each M-Cycle.
    cycles: [][]std.json.Value,
};

// TODO: Need to rethink all of the functions and how they are structured. The code is pretty awfull.

fn initializeCpu(cpu: *CPU.State, memory: *[def.addr_space]u8, test_case: *const TestType) !void {
    cpu.interrupt_master_enable = false;
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
    try std.testing.expectEqual(test_case.final.pc, cpu.registers.r16.pc -% 1);
    try std.testing.expectEqual(test_case.final.sp, cpu.registers.r16.sp);
    try std.testing.expectEqual(test_case.final.a, cpu.registers.r8.a);
    const expected_flags: CPU.FlagRegister = @bitCast(test_case.final.f); 
    try std.testing.expectEqual(expected_flags.flags.carry, cpu.registers.r8.f.flags.carry);
    try std.testing.expectEqual(expected_flags.flags.half_bcd, cpu.registers.r8.f.flags.half_bcd);
    try std.testing.expectEqual(expected_flags.flags.n_bcd, cpu.registers.r8.f.flags.n_bcd);
    try std.testing.expectEqual(expected_flags.flags.zero, cpu.registers.r8.f.flags.zero);
    try std.testing.expectEqual(0, cpu.registers.r8.p.pseudo.const_zero);
    try std.testing.expectEqual(1, cpu.registers.r8.p.pseudo.const_one);
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
    std.debug.print("A: {X:0>2} F {X:0>2}: {s} {s} {s} {s} ", .{ cpuState.a, cpuState.f,
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

// TODO: Some Ideas on how to improve testing:
// - It would be nice to generate a test for each instruction. Therefore I can rerun a single test.
// - Having a test for each instruction means I can parallelize running the tests, making the test run faster.
// - Allow me to run a certain category of tests (like only the single step tests for cpu) (with test filters?)
// - Run all the test and once all of them have run show all errors. Don't stop at the first error!
// => Apparrently I can write my own test runner to solve this!
pub fn runSingleStepTests() !void {
    const alloc = std.testing.allocator;

    // TODO: How could we create a test with an input parameter in zig testing?
    // It would be nice to define which of the instructions we want to test individually as well.
    // So that when I am fixing issues I can run a single test repeatadely.
    var test_dir: std.fs.Dir = try std.fs.cwd().openDir("test_data/SingleStepTests/v1/", .{ .iterate = true });
    defer test_dir.close();

    // Initialized once to only initialize the opcode banks once!
    var cpu: CPU.State = .{};
    CPU.init(&cpu);

    var iter: std.fs.Dir.Iterator = test_dir.iterate();
    var idx: u16 = 0;
    while(try iter.next()) |dir_entry| : (idx += 1) {
        std.debug.assert(dir_entry.kind == .file);
        std.debug.print("{d}: Testing: {s}\n", .{idx + 1, dir_entry.name});
        if(std.mem.eql(u8, dir_entry.name, "76.json")) {
            continue; // Skip testing halt. SingleStepTests are inaccurate for halt.
        }

        const test_file: []u8 = try test_dir.readFileAlloc(alloc, dir_entry.name, 1 * 1024 * 1024);
        defer alloc.free(test_file);

        const json = try std.json.parseFromSlice([]TestType, alloc, test_file, .{ .ignore_unknown_fields = true });
        defer json.deinit();

        var mmu: MMU.State = .{}; 

        const test_config: []TestType = json.value;
        for(test_config) |test_case| {
            if(std.mem.eql(u8, test_case.name, "CB 0F 0000")) {
                const a: u32 = 10;
                if(a == 10) {}
            }

            try initializeCpu(&cpu, &mmu.memory, &test_case);

            const num_m_cycles = 1 + test_case.cycles.len;

            // TODO: This is a pretty bad solution.
            // TODO: Would be so nice to disable pre-fetching
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
                std.debug.print("A: {X:0>2} F {X:0>2}: {s} {s} {s} {s} ", .{ cpu.registers.r8.a, cpu.registers.r8.f.f,
                    if (cpu.registers.r8.f.flags.zero == 1) "Z" else "_",
                    if (cpu.registers.r8.f.flags.n_bcd == 1) "N" else "_",
                    if (cpu.registers.r8.f.flags.half_bcd == 1) "H" else "_",
                    if (cpu.registers.r8.f.flags.carry == 1) "C" else "_",
                });
                std.debug.print("B: {X:0>2} C: {X:0>2} ", .{ cpu.registers.r8.b, cpu.registers.r8.c });
                std.debug.print("D: {X:0>2} E: {X:0>2} ", .{ cpu.registers.r8.d, cpu.registers.r8.e });
                std.debug.print("H: {X:0>2} L: {X:0>2} ", .{ cpu.registers.r8.h, cpu.registers.r8.l });
                // Note: pc - 1, because we prefetch, the SingleStepTests don't implement that.
                std.debug.print("SP: {X:0>4} PC: {X:0>4}\n", .{ cpu.registers.r16.sp, cpu.registers.r16.pc - 1 });
                std.debug.print("WZ: {X:0>4}\n", .{ cpu.registers.r16.wz });
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

// TODO: Also interrupt tests, do we create general helper class?
pub fn fetchInstruction(cpu: *CPU.State, mmu: *MMU.State) void {
    cpu.uop_fifo.clear();
    // Load a nop instruction to fetch the required instruction.
    const opcode_bank = CPU.opcode_banks[CPU.opcode_bank_default];
    const uops = opcode_bank[0];
    cpu.uop_fifo.write(uops.slice());
    for(0..(def.t_cycles_per_m_cycle)) |_| {
        CPU.cycle(cpu, mmu);
        MMU.cycle(mmu);
    }
}

// TODO: Also interrupt tests, do we create general helper class?
pub fn executeCPUFor(cpu: *CPU.State, mmu: *MMU.State, m_cycles: usize) void {
    for(0..(def.t_cycles_per_m_cycle * m_cycles)) |_| {
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

pub fn runHaltTests() !void {
    var mmu: MMU.State = .{}; 
    var cpu: CPU.State = .{};
    CPU.init(&cpu);

    // Halt stops cpu
    mmu.memory[mem_map.wram_low] = 0x76; // HALT
    mmu.memory[mem_map.wram_low + 1] = 0x03; // INC BC
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    mmu.memory[mem_map.interrupt_enable] = 0x00;
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = false;
    fetchInstruction(&cpu, &mmu);
    executeCPUFor(&cpu, &mmu, 2);
    std.testing.expectEqual(mem_map.wram_low + 1, cpu.registers.r16.pc) catch |err| {
        std.debug.print("Failed: Halt stops the cpu.\n", .{});
        return err;
    };

    // IME set, no pending interrupt after halt => cpu still paused.
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    mmu.memory[mem_map.interrupt_enable] = 0x00;
    mmu.memory[mem_map.wram_low] = 0x76; // HALT
    mmu.memory[mem_map.wram_low + 1] = 0x03; // INC BC
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = true;
    fetchInstruction(&cpu, &mmu);
    executeCPUFor(&cpu, &mmu, 1);
    std.testing.expectEqual(mem_map.wram_low + 1, cpu.registers.r16.pc) catch |err| {
        std.debug.print("Failed: Halt: IME set, no pending interrupt after halt: cpu halted.\n", .{});
        return err;
    };

    // IME set, pending interrupt after halt => interrupt handled, cpu resumed.
    cpu.registers.r16.pc = mem_map.wram_low;
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    mmu.memory[mem_map.interrupt_enable] = 0xFF;
    mmu.memory[mem_map.wram_low] = 0x76; // HALT
    mmu.memory[mem_map.wram_low + 1] = 0x03; // INC BC
    cpu.interrupt_master_enable = true;
    fetchInstruction(&cpu, &mmu);
    executeCPUFor(&cpu, &mmu, 1);
    // cpu is now halted (pc is on INC BC).
    mmu.memory[mem_map.interrupt_flag] = 0b0001_0000; // Joypad
    executeCPUFor(&cpu, &mmu, 1);
    std.testing.expectEqual(true, isFullInstructionLoaded(&cpu, CPU.opcode_bank_pseudo, 0x04)) catch |err| {
        std.debug.print("Failed: Halt: IME set, pending interrupt after halt: cpu has not loaded the instruction handler.\n", .{});
        return err;
    };

    // IME not set, no interrupt pending during halt => interrupt pending after halt => cpu resumes after halt, interrupt not handled.
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    mmu.memory[mem_map.interrupt_enable] = 0xFF;
    mmu.memory[mem_map.wram_low] = 0x76; // HALT
    mmu.memory[mem_map.wram_low + 1] = 0x03; // INC BC
    cpu.registers.r16.pc = mem_map.wram_low;
    cpu.interrupt_master_enable = true;
    fetchInstruction(&cpu, &mmu);
    executeCPUFor(&cpu, &mmu, 1);
    mmu.memory[mem_map.interrupt_flag] = 0b0001_0000;
    executeCPUFor(&cpu, &mmu, 1);
    // TODO: How to know if the cpu is in a halt state or not?
    // std.testing.expectEqual(false, cpu.isHalted) catch |err| {
    //     std.debug.print("Failed: Halt: IME not set, no pending interrupt during halt, pending interrupt after halt: cpu resumes.\n", .{});
    //     return err;
    // };
    std.testing.expectEqual(mem_map.wram_low + 2, cpu.registers.r16.pc) catch |err| {
        std.debug.print("Failed: Halt: IME not set, no pending interrupt during halt, pending interrupt after halt: cpu resumes after halt instruction.\n", .{});
        return err;
    };

    // TODO: Halt Bug => Could not be triggered by any released game => Not for now. 
    // IME not set, interrupt pending during halt => halt-bug
    // halt bug (does not affect gbc and gba):
        // Happens when: IME = 0 and IF & IE != 0 => assert that this never happens in real game?  
        // halt exists immediately, pc is not incremented. 
        // The byte after halt (next instruction) is read twice. 
        // Special cases (result of pc never being incremented). 
        // ei => halt. interrupt is serviced after halt. interrupt returns to halt (because pc was never incremented) => executes halt again.
        // halt => rst. rst instruction's return address will point at rst itself. ret would return to rst and execute it again.
        // ei => halt => rst: ei behaviour "wins".  
    // https://github.com/nitro2k01/little-things-gb/tree/main/double-halt-cancel
}
