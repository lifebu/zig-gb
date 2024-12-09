const std = @import("std");


const APU = @import("../apu.zig");
const CPU = @import("../cpu.zig");
const MMIO = @import("../mmio.zig");
const MMU = @import("../mmu.zig");
const MemMap = @import("../mem_map.zig");

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
    ram: [][]u16,
};

const TestType = struct {
    name: []u8,
    initial: CPUState,
    final: CPUState,
    cycles: [][]std.json.Value,
};

fn testOutput(cpu: *const CPU, mmu: *const MMU, testCase: *const TestType) !void {
    try std.testing.expectEqual(cpu.pc, testCase.final.pc);
    try std.testing.expectEqual(cpu.sp, testCase.final.sp);
    try std.testing.expectEqual(cpu.registers.r8.A, testCase.final.a);
    try std.testing.expectEqual(cpu.registers.r8.F.F, testCase.final.f);
    try std.testing.expectEqual(cpu.registers.r8.B, testCase.final.b);
    try std.testing.expectEqual(cpu.registers.r8.C, testCase.final.c);
    try std.testing.expectEqual(cpu.registers.r8.D, testCase.final.d);
    try std.testing.expectEqual(cpu.registers.r8.E, testCase.final.e);
    try std.testing.expectEqual(cpu.registers.r8.H, testCase.final.h);
    try std.testing.expectEqual(cpu.registers.r8.L, testCase.final.l);
    for (testCase.final.ram) |ramPair| {
        std.debug.assert(ramPair.len == 2);
        const address: u16 = ramPair[0];
        const value: u8 = @intCast(ramPair[1]);
        try std.testing.expectEqual(mmu.read8_sys(address), value);
    }

    const opcodeName: []u8 = testCase.name[0..2];
    if(std.mem.eql(u8, opcodeName, "76") or std.mem.eql(u8, opcodeName, "10")) {
        return; // Those tests have wrong cycle counts and divert from the actual documentation.
    }
    try std.testing.expectEqual(cpu.cycles_ahead, testCase.cycles.len * 4);
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

    var testDir: std.fs.Dir = try std.fs.cwd().openDir("test_data/SingleStepTests/v1/", .{ .iterate = true });
    defer testDir.close();

    var iter: std.fs.Dir.Iterator = testDir.iterate();
    var idx: u32 = 1;
    while(try iter.next()) |dirEntry| {
        std.debug.assert(dirEntry.kind == .file);
        std.debug.print("{d}: Testing: {s}\n", .{idx, dirEntry.name});
        idx += 1;

        const testFile: []u8 = try testDir.readFileAlloc(alloc, dirEntry.name, 1 * 1024 * 1024);
        defer alloc.free(testFile);

        const json = try std.json.parseFromSlice([]TestType, alloc, testFile, .{ .ignore_unknown_fields = true });
        defer json.deinit();

        var apu = APU{};
        var mmio = MMIO{};

        var mmu = try MMU.init(alloc, &apu, &mmio, null);
        defer mmu.deinit();

        var cpu = try CPU.init();
        defer cpu.deinit();

        const testConfig: []TestType = json.value;
        for(testConfig) |testCase| {
            cpu.pc = testCase.initial.pc;
            cpu.sp = testCase.initial.sp;
            cpu.registers.r8.A = testCase.initial.a;
            cpu.registers.r8.F.F = testCase.initial.f;
            cpu.registers.r8.B = testCase.initial.b;
            cpu.registers.r8.C = testCase.initial.c;
            cpu.registers.r8.D = testCase.initial.d;
            cpu.registers.r8.E = testCase.initial.e;
            cpu.registers.r8.H = testCase.initial.h;
            cpu.registers.r8.L = testCase.initial.l;
            for (testCase.initial.ram) |ramPair| {
                std.debug.assert(ramPair.len == 2);
                const address: u16 = ramPair[0];
                const value: u8 = @intCast(ramPair[1]);
                mmu.write8_sys(address, value);
            }
            cpu.isHalted = false;

            try cpu.step(&mmu);

            testOutput(&cpu, &mmu, &testCase) catch |err| {
                std.debug.print("Test Failed: {s}\n", .{ testCase.name });
                std.debug.print("Initial\n", .{});
                printTestCase(&testCase.initial);
                std.debug.print("Expected\n", .{});
                printTestCase(&testCase.final);
                std.debug.print("Cycles: {d}\n", .{testCase.cycles.len * 4});
                std.debug.print("\n", .{});

                std.debug.print("Got\n", .{});
                std.debug.print("A: {X:0>2} F: {s} {s} {s} {s} ", .{ cpu.registers.r8.A, 
                    if (cpu.registers.r8.F.Flags.zero) "Z" else "_",
                    if (cpu.registers.r8.F.Flags.nBCD) "N" else "_",
                    if (cpu.registers.r8.F.Flags.halfBCD) "H" else "_",
                    if (cpu.registers.r8.F.Flags.carry) "C" else "_",
                });
                std.debug.print("B: {X:0>2} C: {X:0>2} ", .{ cpu.registers.r8.B, cpu.registers.r8.C });
                std.debug.print("D: {X:0>2} E: {X:0>2} ", .{ cpu.registers.r8.D, cpu.registers.r8.E });
                std.debug.print("H: {X:0>2} L: {X:0>2} ", .{ cpu.registers.r8.H, cpu.registers.r8.L });
                std.debug.print("SP: {X:0>4} PC: {X:0>4}\n", .{ cpu.sp, cpu.pc });
                for (testCase.final.ram) |ramPair| {
                    std.debug.assert(ramPair.len == 2);
                    const address: u16 = ramPair[0];
                    const value: u8 = mmu.read8_sys(address);
                    std.debug.print("Addr: {X:0>4} val: {X:0>2} ", .{ address, value });
                }
                std.debug.print("\n", .{});
                std.debug.print("Cycles: {d}\n", .{cpu.cycles_ahead});

                return err;
            };
        }
    }
}

pub fn runHaltTests() !void {
    const alloc = std.testing.allocator;

    var apu = APU{};
    var mmio = MMIO{};

    var mmu = try MMU.init(alloc, &apu, &mmio, null);
    defer mmu.deinit();

    var cpu = try CPU.init();
    defer cpu.deinit();

    // Halt stops cpu
    mmu.write8_sys(MemMap.WRAM_LOW, 0x76); // HALT
    mmu.write8_sys(MemMap.WRAM_LOW + 1, 0x03); // INC BC
    cpu.pc = MemMap.WRAM_LOW;
    for (0..2) |_| {
        try cpu.step(&mmu);
    }
    std.testing.expectEqual(MemMap.WRAM_LOW + 1, cpu.pc) catch |err| {
        std.debug.print("Failed: Halt stops the cpu.\n", .{});
        return err;
    };

    // IME set, no pending interrupt after halt => cpu still paused.
    cpu.isHalted = false;
    cpu.pc = MemMap.WRAM_LOW;
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    mmu.write8_sys(MemMap.INTERRUPT_ENABLE, 0x00);
    mmu.write8_sys(MemMap.WRAM_LOW, 0xFB); // EI => IME Set.
    mmu.write8_sys(MemMap.WRAM_LOW + 1, 0x00); // NOOP
    mmu.write8_sys(MemMap.WRAM_LOW + 2, 0x76); // HALT
    mmu.write8_sys(MemMap.WRAM_LOW + 3, 0x03); // INC BC
    for (0..4) |_| {
        try cpu.step(&mmu);
    }
    std.testing.expectEqual(MemMap.WRAM_LOW + 3, cpu.pc) catch |err| {
        std.debug.print("Failed: Halt: IME set, no pending interrupt after halt: cpu halted.\n", .{});
        return err;
    };

    // IME set, pending interrupt after halt => interrupt handled, cpu resumed.
    cpu.isHalted = false;
    cpu.pc = MemMap.WRAM_LOW;
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    mmu.write8_sys(MemMap.INTERRUPT_ENABLE, 0xFF);
    mmu.write8_sys(MemMap.WRAM_LOW, 0xFB); // EI => IME Set.
    mmu.write8_sys(MemMap.WRAM_LOW + 1, 0x00); // NOOP
    mmu.write8_sys(MemMap.WRAM_LOW + 2, 0x76); // HALT
    for (0..3) |_| {
        try cpu.step(&mmu);
    }
    // cpu is now halted (pc is on INC BC).
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0b0001_0000);
    try cpu.step(&mmu);
    std.testing.expectEqual(0x60, cpu.pc) catch |err| {
        std.debug.print("Failed: Halt: IME set, pending interrupt after halt: interrupt handled.\n", .{});
        return err;
    };
    std.testing.expectEqual(false, cpu.isHalted) catch |err| {
        std.debug.print("Failed: Halt: IME set, pending interrupt after halt: cpu resumed.\n", .{});
        return err;
    };

    // IME not set, no interrupt pending during halt => interrupt pending after halt => cpu resumes after halt, interrupt not handled.
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0x00);
    mmu.write8_sys(MemMap.INTERRUPT_ENABLE, 0xFF);
    cpu.pc = MemMap.WRAM_LOW;
    mmu.write8_sys(MemMap.WRAM_LOW, 0xF3); // DI => IME cleared.
    mmu.write8_sys(MemMap.WRAM_LOW + 1, 0x76); // HALT
    mmu.write8_sys(MemMap.WRAM_LOW + 2, 0x03); // INC BC
    for (0..2) |_| {
        try cpu.step(&mmu);
    }
    mmu.write8_sys(MemMap.INTERRUPT_FLAG, 0b0001_0000);
    try cpu.step(&mmu);
    std.testing.expectEqual(false, cpu.isHalted) catch |err| {
        std.debug.print("Failed: Halt: IME not set, no pending interrupt during halt, pending interrupt after halt: cpu resumes.\n", .{});
        return err;
    };
    std.testing.expectEqual(MemMap.WRAM_LOW + 2, cpu.pc) catch |err| {
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
}

// test "blargg" {
//     const testRoms =  [_][]const u8{
//         "test_data/blargg_roms/cpu_instrs/individual/01-special.gb", 
//         // "test_data/blargg_roms/cpu_instrs/individual/02-interrupts.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/03-op sh,hl.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/04-op r,imm.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/05-op rp.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/06-ld r,r.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/07-jr,jp,call.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/08-misc instrs.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/09-op r,r.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/10-bit ops.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/11-op a,(hl).gb", 
//     }; 
//
//     const alloc = std.testing.allocator;
//
//     for (testRoms, 0..) |testRom, i| {
//         std.debug.print("{d}: Testing: {s}\n", .{i, testRom});
//         var cpu = try _cpu.CPU.init(alloc, testRom);
//         defer cpu.deinit();
//
//         var lastPC: u16 = 0;
//         while (lastPC != cpu.pc) {
//             lastPC = cpu.pc;
//             try cpu.frame();
//         }
//
//         const output: std.ArrayList(u8) = try blargg.parseOutput(&cpu, alloc);
//         defer output.deinit();
//
//         const passed: bool = blargg.hasPassed(&output);
//         if (!passed) {
//             std.debug.print("{s}\n", .{output.items});
//         }
//         try std.testing.expect(passed);
//     }
// }
