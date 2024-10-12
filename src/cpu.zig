const std = @import("std");

// TODO: It would be nice to split some of this file into multiple files, maybe interrupts, executing opcodes?
pub const CPU = struct {
    const Self = @This();

    const FlagRegister = packed union {
        F: u8,
        Flags: packed struct {
            _: u4 = 0,
            carry: bool = false,
            halfBCD: bool = false,
            nBCD: bool = false,
            zero: bool = false,
        },
    };

    const Registers = packed union {
        r16: packed struct {
            AF: u16 = 0,
            BC: u16 = 0,
            DE: u16 = 0,
            HL: u16 = 0,
        },
        // gb and x86 are little-endian
        r8: packed struct {
            F: FlagRegister = . { .F = 0 },
            A: u8 = 0,
            C: u8 = 0,
            B: u8 = 0,
            E: u8 = 0,
            D: u8 = 0,
            L: u8 = 0,
            H: u8 = 0,
        },
    };

    const HIGH_PAGE: u16 = 0xFF00;
    const CYCLES_PER_FRAME: u32 = 70_226;

    registers: Registers = .{ .r16 = .{} },

    memory: []u8 = undefined,
    allocator: std.mem.Allocator,
    // Program counter
    pc: u16 = 0,
    // Stack pointer
    sp: u16 = 0,
    cycle: u32 = 0,
    // TODO: Maybe state flags?
    isStopped: bool = false,
    isHalted: bool = false,
    isPanicked: bool = false,

    pub fn init(alloc: std.mem.Allocator, gbFile: []const u8) !Self {
        var cpu = CPU{ .allocator = alloc };

        cpu.memory = try alloc.alloc(u8, 0x10000);
        errdefer alloc.free(cpu.memory);

        _ = try std.fs.cwd().readFile(gbFile, cpu.memory);

        cpu.registers.r16.AF = 0x01B0;
        cpu.registers.r16.BC = 0x0013;
        cpu.registers.r16.DE = 0x00D8;
        cpu.registers.r16.HL = 0x014D;
        cpu.pc = 0x0100;
        cpu.sp = 0xFFFE;
        return cpu;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.memory);
    }

    // Instruction Variants (Sets of instructions that do the same, but to different targets/source).
    const R8Variant = enum(u8) { B, C, D, E, H, L, HL, A, };
    pub fn getFromR8Variant(self: *Self, variant: R8Variant) *u8 {
        return switch (variant) {
            .B => &self.registers.r8.B,
            .C => &self.registers.r8.C,
            .D => &self.registers.r8.D,
            .E => &self.registers.r8.E,
            .H => &self.registers.r8.H,
            .L => &self.registers.r8.L,
            .HL => &self.memory[self.registers.r16.HL],
            .A => &self.registers.r8.A,
        };
    }

    const R16Variant = enum(u8) { BC, DE, HL, SP, };
    pub fn getFromR16Variant(self: *Self, variant: R16Variant) *u16 {
        return switch (variant) {
            .BC => &self.registers.r16.BC,
            .DE => &self.registers.r16.DE,
            .HL => &self.registers.r16.HL,
            .SP => &self.sp,
        };
    }

    const R16StkVariant = enum(u8) { BC, DE, HL, AF, };
    pub fn getFromR16StkVariant(self: *Self, variant: R16StkVariant) *u16 {
        return switch (variant) {
            .BC => &self.registers.r16.BC,
            .DE => &self.registers.r16.DE,
            .HL => &self.registers.r16.HL,
            .AF => &self.registers.r16.AF,
        };
    }

    const R16MemVariant = enum(u8) { BC, DE, HLinc, HLdec, };
    pub fn getFromR16MemVariant(self: *Self, variant: R16MemVariant) *u8 {
        return switch (variant) {
            .BC => &self.memory[self.registers.r16.BC],
            .DE => &self.memory[self.registers.r16.DE],
            .HLinc => blk: {
                const value: *u8 = &self.memory[self.registers.r16.HL];
                self.registers.r16.HL += 1;
                break: blk value;
            },
            .HLdec => blk: {
                const value: *u8 = &self.memory[self.registers.r16.HL];
                self.registers.r16.HL -= 1;
                break: blk value;
            },
        };
    }

    const CondVariant = enum(u8) { NZ, Z, NC, C, };
    pub fn getFromCondVariant(self: *Self, variant: CondVariant) bool {
        return switch (variant) {
            .NZ => !self.registers.r8.F.Flags.zero,
            .Z => self.registers.r8.F.Flags.zero,
            .NC => !self.registers.r8.F.Flags.carry,
            .C => self.registers.r8.F.Flags.carry,
        };
    }

    const Operation = struct {
        deltaPC: u8,
        cycles: u8,
    };

    const CPUError = error {
        OPERATION_NOT_IMPLEMENTED,
    };

    pub fn debugPrintState(self: *Self) void {
        // Debug printing copied from: https://github.com/Ryp/gb-emu-zig
        std.debug.print("PC {x:0>4} SP {x:0>4}", .{ self.pc, self.sp });
        std.debug.print(" A {x:0>2} Flags {s} {s} {s} {s}", .{
            self.registers.r8.A,
            if (self.registers.r8.F.Flags.zero) "Z" else "_",
            if (self.registers.r8.F.Flags.nBCD) "N" else "_",
            if (self.registers.r8.F.Flags.halfBCD) "H" else "_",
            if (self.registers.r8.F.Flags.carry) "C" else "_",
        });
        std.debug.print(" B {x:0>2} C {x:0>2}", .{ self.registers.r8.B, self.registers.r8.C });
        std.debug.print(" D {x:0>2} E {x:0>2}", .{ self.registers.r8.D, self.registers.r8.E });
        std.debug.print(" H {x:0>2} L {x:0>2}", .{ self.registers.r8.H, self.registers.r8.L });
        std.debug.print("| {x} | ", .{self.memory[self.pc]});
        std.debug.print("\n", .{});
    }

    pub fn frame(self: *Self) !void {
        self.cycle = 0;

        // TODO: implement cycle accuracy (with PPU!).
        while (!self.isHalted and !self.isStopped and !self.isPanicked and self.cycle < CYCLES_PER_FRAME) {
            self.debugPrintState();

            const opcode: u8 = self.memory[self.pc];
            // TODO: I need testing for this, that everything is set up correctly. Especially the cycle count can be wrong!
            const operation: Operation = try switch (opcode) {
                // NOOP
                0x00 => Operation{ .deltaPC = 1, .cycles = 4 },
                // LD r16, imm16
                0x01, 0x11, 0x21, 0x31 => op: {
                    // TODO: Maybe create a function that does a safety check if we access memory wrong? 
                    // If you have a 3 Byte instruction at the last byte of memory, this would break.
                    // TODO: I should wrap the ptrCast and alignCast in a function, as I need to do that a lot.
                    // TODO: And I need to do the elignment correctly everyhwere I access memory.
                    const source: *align(1) u16 = @ptrCast(&self.memory[self.pc + 1]);
                    const destVar: R16Variant = @enumFromInt((opcode & 0b0011_0000) >> 4);
                    const dest: *u16 = self.getFromR16Variant(destVar);
                    dest.* = source.*;

                    break: op Operation{ .deltaPC = 3, .cycles = 12 };
                },
                // LD r16mem, a
                0x02, 0x12, 0x22, 0x32 => op: {
                    const source: *u8 = &self.registers.r8.A;
                    const destVar: R16MemVariant = @enumFromInt((opcode & 0b0011_0000) >> 4);
                    const dest: *u8 = self.getFromR16MemVariant(destVar);
                    dest.* = source.*;

                    break: op Operation{ .deltaPC =  1, .cycles = 8 };
                },
                // Inc r16
                0x03, 0x13, 0x23, 0x33 => op: {
                    const sourceVar: R16Variant = @enumFromInt((opcode & 0b0011_0000) >> 4);
                    const source: *u16 = self.getFromR16Variant(sourceVar);
                    source.* += 1;

                    break: op Operation{ .deltaPC = 1, .cycles = 8 };
                },
                // INC r8
                0x04, 0x14, 0x24, 0x34, 0x0C, 0x1C, 0x2C, 0x3C => op : {
                    const sourceVar: R8Variant = @enumFromInt((opcode & 0b0011_1000) >> 3);
                    const source: *u8 = self.getFromR8Variant(sourceVar);
                    source.* +%= 1;

                    self.registers.r8.F.Flags.zero = source.* == 0; 
                    self.registers.r8.F.Flags.nBCD = false;
                    // TODO: Maybe helper function?
                    self.registers.r8.F.Flags.halfBCD = (source.* & 0b0000_1111) == 0; 

                    break: op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 12 else 4 };
                },
                // DEC r8
                0x05, 0x15, 0x25, 0x35, 0x0D, 0x1D, 0x2D, 0x3D => op : {
                    const sourceVar: R8Variant = @enumFromInt((opcode & 0b0011_1000) >> 3);
                    const source: *u8 = self.getFromR8Variant(sourceVar);
                    source.* -%= 1;

                    self.registers.r8.F.Flags.zero = source.* == 0; 
                    self.registers.r8.F.Flags.nBCD = true;
                    // TODO: Helper function?
                    self.registers.r8.F.Flags.halfBCD = (source.* & 0b0000_1111) == 0b1111; 

                    break: op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 12 else 4 };
                },
                // LD r8, imm8
                0x06, 0x16, 0x26, 0x36, 0x0E, 0x1E, 0x2E, 0x3E => op: {
                    const source: *u8 = &self.memory[self.pc + 1];
                    const destVar: R8Variant = @enumFromInt((opcode & 0b0011_1000) >> 3);
                    const dest: *u8 = self.getFromR8Variant(destVar);
                    dest.* = source.*;

                    break: op Operation{ .deltaPC = 2, .cycles = if (destVar == .HL) 12 else 8 };
                },
                // RLCA
                0x07 => op: {
                    const A: *u8 = &self.registers.r8.A;
                    const shiftedBit: bool = (A.* & 0b1000_0000) == 1;
                    A.* <<= 1;

                    self.registers.r8.F.Flags.carry = shiftedBit;
                    self.registers.r8.F.Flags.zero = A.* == 0;

                    break: op Operation { .deltaPC = 1, .cycles = 4 };
                },
                // LD (imm16),SP
                0x08 => op: {
                    const source: *align(1) u16 = @ptrCast(&self.memory[self.pc + 1]);
                    self.sp = source.*;

                    break: op Operation { .deltaPC = 3, .cycles = 20 };
                },
                // LD a, r16mem
                0x0A, 0x1A, 0x2A, 0x3A => op: {
                    const sourceVar: R16MemVariant = @enumFromInt((opcode & 0b0011_0000) >> 4);
                    const source: *u8 = self.getFromR16MemVariant(sourceVar);
                    const dest: *u8 = &self.registers.r8.A;
                    dest.* = source.*;

                    break: op Operation{ .deltaPC =  1, .cycles = 8 };
                }, 
                // Dec r16
                0x0B, 0x1B, 0x2B, 0x3B => op: {
                    const sourceVar: R16Variant = @enumFromInt((opcode & 0b0011_0000) >> 4);
                    const source: *u16 = self.getFromR16Variant(sourceVar);
                    source.* -= 1;

                    break: op Operation{ .deltaPC = 1, .cycles = 8 };
                },
                // ADD HL, R16
                0x09, 0x19, 0x29, 0x39 => op : {
                    const sourceVar: R16Variant = @enumFromInt((opcode & 0b0011_0000) >> 4);
                    const source: *u16 = self.getFromR16Variant(sourceVar);
                    self.registers.r16.HL += source.*;

                    self.registers.r8.F.Flags.nBCD = false;
                    self.registers.r8.F.Flags.halfBCD = false; // TODO: set if carry from bit 11 (12th).
                    self.registers.r8.F.Flags.carry = false; // TODO: set if carry from bit 15 (16th).

                    break: op Operation { .deltaPC = 1, .cycles = 8 };
                },
                // RRCA
                0x0F => op: {
                    const A: *u8 = &self.registers.r8.A;
                    const shiftedBit: bool = (A.* & 0b0000_0001) == 1;
                    A.* >>= 1;

                    self.registers.r8.F.Flags.carry = shiftedBit;
                    self.registers.r8.F.Flags.zero = A.* == 0;

                    break: op Operation { .deltaPC = 1, .cycles = 4 };
                },
                // STOP
                0x10 => op: {
                    self.isStopped = true;
                    break: op Operation { .deltaPC = 2, .cycles = 4};
                },
                // RLA
                0x17 => op: {
                    const A: *u8 = &self.registers.r8.A;
                    const shiftedBit: bool = (A.* & 0b1000_0000) == 1;
                    A.* <<= 1;

                    const carry: u8 = @intFromBool(self.registers.r8.F.Flags.carry);
                    A.* = A.* & carry;
                    self.registers.r8.F.Flags.carry = shiftedBit;
                    self.registers.r8.F.Flags.zero = A.* == 0;

                    break: op Operation { .deltaPC = 1, .cycles = 4 };
                },
                // JR r8
                0x18 => op: {
                    // TODO: Out of memoery?
                    // TODO: All this conversion smells like spaghetti, is there an easier way?
                    const relDest: i8 = @bitCast(self.memory[self.pc + 1]); 
                    var pcCast: i32 = self.pc;
                    pcCast += 2; // size of instruction.
                    pcCast += relDest;
                    self.pc = @intCast(pcCast); 

                    break: op Operation { .deltaPC = 0, .cycles =  12 };
                },
                // RRA
                0x1F => op: {
                    const A: *u8 = &self.registers.r8.A;
                    const shiftedBit: bool = (A.* & 0b0000_0001) == 1;
                    A.* >>= 1;

                    const carry: u8 = @intFromBool(self.registers.r8.F.Flags.carry);
                    A.* = A.* & (carry << 7);
                    self.registers.r8.F.Flags.carry = shiftedBit;
                    self.registers.r8.F.Flags.zero = A.* == 0;

                    break: op Operation { .deltaPC = 1, .cycles = 4 };
                },
                // JR cond imm8
                0x20, 0x30, 0x28, 0x38 => op: {
                    const condVar: CondVariant = @enumFromInt((opcode & 0b0001_1000) >> 3);
                    const cond: bool = self.getFromCondVariant(condVar);
                    // TODO: Out of memoery?
                    // TODO: All this conversion smells like spaghetti, is there an easier way?
                    const relDest: i8 = @bitCast(self.memory[self.pc + 1]); 
                    var pcCast: i32 = self.pc;
                    pcCast += 2; // size of instruction.
                    pcCast += if(cond) relDest else 0;
                    self.pc = @intCast(pcCast); 

                    break: op Operation { .deltaPC = 0, .cycles =  if (cond) 12 else 8 };
                },
                // DAA
                0x27 => op: {
                    // TODO: This feels like something i can skip for now (Decimal adjust register A (BCD)).
                    std.debug.print("OPERATION_NOT_IMPLEMENTED: DAA: 0x27\n", .{});
                    self.isPanicked = true;
                    break: op CPUError.OPERATION_NOT_IMPLEMENTED;
                },
                // CPL (complement A)
                0x2F => op: {
                    const A: *u8 = &self.registers.r8.A;
                    A.* = ~A.*;

                    self.registers.r8.F.Flags.nBCD = true;
                    self.registers.r8.F.Flags.halfBCD = true;

                    break: op Operation{ .deltaPC = 1, .cycles = 4 };
                },
                // LD r8, r8
                0x40...0x7F => op: {
                    // TODO: Break the range, this is not readable honestly!
                    // HALT
                    if(opcode == 0x76) {
                        // TODO: implement HALT Bug 
                        self.isHalted = true;
                        break :op Operation{ .deltaPC = 1, .cycles = 4 };
                    }

                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    const source: *u8 = self.getFromR8Variant(sourceVar);
                    const destVar: R8Variant = @enumFromInt((opcode & 0b0011_1000) >> 3);
                    const dest: *u8 = self.getFromR8Variant(destVar);
                    dest.* = source.*;

                    break :op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL or destVar == .HL) 8 else 4 };
                },
                // XOR a, r8
                0xA8...0xAF => op: {
                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    const source: *u8 = self.getFromR8Variant(sourceVar);
                    const dest: *u8 = &self.registers.r8.A;
                    dest.* ^= source.*;

                    self.registers.r8.F.Flags.zero = dest.* == 0;

                    break :op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 8 else 4 };
                },
                // OR a, r8
                0xB0...0xB7 => op: {
                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    const source: *u8 = self.getFromR8Variant(sourceVar);
                    const dest: *u8 = &self.registers.r8.A;
                    dest.* |= source.*;

                    self.registers.r8.F.Flags.zero = dest.* == 0;

                    break :op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 8 else 4 };
                },
                // CP a, r8
                0xB8...0xBF => op: {
                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    const source: *u8 = self.getFromR8Variant(sourceVar);
                    const A: *u8 = &self.registers.r8.A;

                    self.registers.r8.F.Flags.zero = A.* == source.*;
                    self.registers.r8.F.Flags.nBCD = true;
                    // True: Set if no borrow from bit 4
                    self.registers.r8.F.Flags.halfBCD = true;
                    self.registers.r8.F.Flags.carry = A.* < source.*;

                    break :op Operation{ .deltaPC = 2, .cycles = if (sourceVar == .HL) 8 else 4 };
                },
                // RET cond
                0xC0, 0xC8, 0xD0, 0xD8 => op: {
                    const condVar: CondVariant = @enumFromInt((opcode & 0b0001_1000) >> 3);
                    const cond: bool = self.getFromCondVariant(condVar);

                    if(cond) {
                        const retAddress: *align(1) u16 = @ptrCast(&self.memory[self.sp]);
                        self.pc = retAddress.*;
                        self.sp += 2;
                    }

                    break :op Operation{ .deltaPC = if (cond) 0 else 1, .cycles = if(cond) 20 else 8 };
                },
                // POP r16stk
                0xC1, 0xD1, 0xE1, 0xF1 => op: {
                    const destVar: R16StkVariant = @enumFromInt((opcode & 0b0011_0000) >> 4);
                    const dest: *u16 = self.getFromR16StkVariant(destVar);

                    const stack: *align(1) u16 = @ptrCast(&self.memory[self.sp]);
                    dest.* = stack.*;
                    self.sp += 2;

                    break: op Operation{ .deltaPC = 1, .cycles = 16 };
                },
                // PUSH r16stk
                0xC5, 0xD5, 0xE5, 0xF5 => op: {
                    const sourceVar: R16StkVariant = @enumFromInt(opcode & 0b0011_0000 >> 4);
                    const source: *u16 = self.getFromR16StkVariant(sourceVar);

                    self.sp -= 2;
                    const stack: *align(1) u16 = @ptrCast(&self.memory[self.sp]);
                    stack.* = source.*;

                    break: op Operation{ .deltaPC = 1, .cycles = 16 };
                },
                // JP imm16
                0xC3 => op : {
                    // TODO: Out of memory? Crashes because if misalignment! => Helper function
                    const target: *align(1) u16 = @ptrCast(&self.memory[self.pc + 1]);
                    self.pc = target.*;

                    break: op Operation { .deltaPC = 0, .cycles =  16 };
                },
                // CALL cond imm16
                0xC4, 0xCC, 0xD4, 0xDC => op : {
                    // TODO: It looks like all the variants use the same two bits mostly. Can this be used to make the code better?
                    // TODO: same code as unconditional call, combine the code!
                    const condVar: CondVariant = @enumFromInt((opcode & 0b0001_1000) >> 3);
                    const cond: bool = self.getFromCondVariant(condVar);

                    if(cond) {
                        // push next address onto stack.
                        self.sp -= 2;
                        const nextInstr: u16 = self.pc + 3;
                        const stack: *align(1) u16 = @ptrCast(&self.memory[self.sp]);
                        stack.* = nextInstr;

                        // TODO: Out of memory?
                        // jump to imm16
                        const target: *align(1) u16 = @ptrCast(&self.memory[self.pc + 1]);
                        self.pc = target.*;
                    }

                    break: op Operation { .deltaPC = if(cond) 0 else 3, .cycles = if(cond) 24 else 12 };
                },
                // RET
                0xC9 => op : {
                    // TODO: We have instructions for conditional calls/returns. Which are basically the same code as the unconditional returns.
                    // TODO: Can I compbine those? return and conditional return have the same opcode structure, they only differ by the first bit.
                    const retAddress: *align(1) u16 = @ptrCast(&self.memory[self.sp]);
                    self.pc = retAddress.*;
                    self.sp += 2;

                    break: op Operation { .deltaPC = 0, .cycles =  24 };
                },
                // CALL imm16
                0xCD => op : {
                    // TODO: We have instructions for conditional calls/returns. Which are basically the same code as the unconditional call.
                    // TODO: Can I compbine those? Call and conditional call have the same opcode structure, they only differ by the first bit.
                    // push next address onto stack.
                    self.sp -= 2;
                    const nextInstr: u16 = self.pc + 3;
                    const stack: *align(1) u16 = @ptrCast(&self.memory[self.sp]);
                    stack.* = nextInstr;

                    // TODO: Out of memory?
                    // jump to imm16
                    const target: *align(1) u16 = @ptrCast(&self.memory[self.pc + 1]);
                    self.pc = target.*;

                    break: op Operation { .deltaPC = 0, .cycles =  24 };
                },
                // LDH [imm8], a
                0xE0 => op: {
                    // TODO: Out of memory?
                    const source: *u8 = @ptrCast(&self.memory[self.pc + 1]);
                    self.memory[HIGH_PAGE + source.*] = self.registers.r8.A;

                    // TODO: If we create this thing first and you can only do that via a function in the self. 
                    // then you are able to check if with the requested delta pc you would be able to access out of memory!
                    break: op Operation { .deltaPC = 2, .cycles = 12 };
                },
                // LD [imm16], a
                0xEA => op: {
                    // TODO: Out of memory?
                    const source: *align(1) u16 = @ptrCast(&self.memory[self.pc + 1]);
                    self.memory[source.*] = self.registers.r8.A;

                    break: op Operation { .deltaPC = 3, .cycles = 16 };
                },
                // AND a, imm8
                0xE6 => op: {
                    // TODO: For add, adc, sub, sbc, and, xor, or, cp we have basically the same code and instruction.
                    // Difference is only if we use an immediate value or not. Can we make this a better re-use?
                    // The difference of the instructions is that the variant is HL + the 2nd bit is set (6th value).
                    // So I can change the mask to improve this! Cycle time is the same as HL!
                    const source: *u8 = &self.memory[self.pc + 1];
                    const A: *u8 = &self.registers.r8.A;
                    A.* &= source.*;

                    self.registers.r8.F.Flags.zero = A.* == 0;
                    self.registers.r8.F.Flags.nBCD = false;
                    self.registers.r8.F.Flags.halfBCD = true;
                    self.registers.r8.F.Flags.carry = false;

                    break :op Operation{ .deltaPC = 2, .cycles = 8 };
                },
                // LDH a, [imm8]
                0xF0 => op: {
                    // TODO: Out of memory?
                    const source: *u8 = @ptrCast(&self.memory[self.pc + 1]);
                    self.registers.r8.A = self.memory[HIGH_PAGE + source.*];

                    break: op Operation { .deltaPC = 3, .cycles = 16 };
                },
                // LD a, [imm16]
                0xFA => op: {
                    // TODO: Out of memory?
                    const source: *align(1) u16 = @ptrCast(&self.memory[self.pc + 1]);
                    self.registers.r8.A = self.memory[source.*];

                    break: op Operation { .deltaPC = 2, .cycles = 12 };
                },
                // DI (Disable Interrupts)
                0xF3 => op: {
                    // TODO: Implement interrupts (This requests to disable the interrupt, but this only happens next cycle). 
                    break: op Operation { .deltaPC = 1, .cycles =  4 };
                },
                // CP a, imm8
                0xFE => op: {
                    // TODO: For add, adc, sub, sbc, and, xor, or, cp we have basically the same code and instruction.
                    // Difference is only if we use an immediate value or not. Can we make this a better re-use?
                    // The difference of the instructions is that the variant is HL + the 2nd bit is set (6th value).
                    // So I can change the mask to improve this! Cycle time is the same as HL!
                    const source: *u8 = &self.memory[self.pc + 1];
                    const A: *u8 = &self.registers.r8.A;

                    self.registers.r8.F.Flags.zero = A.* == source.*;
                    self.registers.r8.F.Flags.nBCD = true;
                    // True: Set if no borrow from bit 4
                    self.registers.r8.F.Flags.halfBCD = true;
                    self.registers.r8.F.Flags.carry = A.* < source.*;

                    break :op Operation{ .deltaPC = 2, .cycles = 8 };
                },
                // ERROR!
                else => op: {
                    std.debug.print("OPERATION_NOT_IMPLEMENTED: {x}\n", .{opcode});
                    self.isPanicked = true;
                    break: op CPUError.OPERATION_NOT_IMPLEMENTED;
                }
            };

            self.pc += operation.deltaPC;
            self.cycle += operation.cycles;
        }
    }
};
