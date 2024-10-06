const std = @import("std");

const CPU = struct {
    const Self = @This();

    const FlagRegister = packed union {
        F: u8,
        Flags: packed struct {
            zero: bool = false,
            nBCD: bool = false,
            halfBCD: bool = false,
            carry: bool = false,
            _: u4 = 0,
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
    registers: Registers = .{ .r16 = .{} },

    memory: []u8 = undefined,
    // Program counter
    pc: u16 = 0,
    // Stack pointer
    sp: u16 = 0,
    cycle: u32 = 0,
    // TODO: Maybe state flags?
    isRunning: bool = true,

    // Instruction Variants (Sets of instructions that do the same, but to different targets/source).
    const R8Variant = enum(u8) { B, C, D, E, H, L, HL, A, };
    pub fn getFromR8Variant(self: *Self, variant: R8Variant) *u8 {
        return switch (variant) {
            .A => &self.registers.r8.A,
            .B => &self.registers.r8.B,
            .C => &self.registers.r8.C,
            .D => &self.registers.r8.D,
            .E => &self.registers.r8.E,
            .H => &self.registers.r8.H,
            .L => &self.registers.r8.L,
            .HL => &self.memory[self.registers.r16.HL],
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
};

const Operation = struct {
    deltaPC: u8,
    cycles: u8,
};

const CPUError = error {
    OPERATION_NOT_IMPLEMENTED,
};

pub fn main() !void {
    var cpu = CPU{};

    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = allocator.allocator();
    defer _ = allocator.deinit();

    cpu.memory = try std.fs.cwd().readFileAlloc(alloc, "playground/Tetris.dump", std.math.maxInt(usize));
    defer alloc.free(cpu.memory);

    // From Tetris Registers.txt
    cpu.registers.r16.AF = 0x01B0;
    cpu.registers.r16.BC = 0x0013;
    cpu.registers.r16.DE = 0x00D8;
    cpu.registers.r16.HL = 0x014D;
    cpu.pc = 0x0100;
    cpu.sp = 0xFFFE;

    // TODO: implement cycle accuracy (with PPU!).
    while (cpu.isRunning) {
        const opcode: u8 = cpu.memory[cpu.pc];
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
                const source: *align(1) u16 = @ptrCast(&cpu.memory[cpu.pc + 1]);
                const destVar: CPU.R16Variant = @enumFromInt((opcode & 0b0011_0000) >> 4);
                const dest: *u16 = cpu.getFromR16Variant(destVar);
                dest.* = source.*;

                break: op Operation{ .deltaPC = 3, .cycles = 12 };
            },
            // LD r16mem, a
            0x02, 0x12, 0x22, 0x32 => op: {
                const sourceVar: CPU.R16MemVariant = @enumFromInt((opcode & 0b0011_0000) >> 4);
                const source: *u8 = cpu.getFromR16MemVariant(sourceVar);
                const dest: *u8 = &cpu.registers.r8.A;
                dest.* = source.*;

                break: op Operation{ .deltaPC =  1, .cycles = 8 };
            },
            // Inc r16
            0x03, 0x13, 0x23, 0x33 => op: {
                const sourceVar: CPU.R16Variant = @enumFromInt((opcode & 0b0011_0000) >> 4);
                const source: *u16 = cpu.getFromR16Variant(sourceVar);
                source.* += 1;

                cpu.registers.r8.F.Flags.zero = source.* == 0; 
                cpu.registers.r8.F.Flags.nBCD = false;
                // TODO: Maybe helper function?
                cpu.registers.r8.F.Flags.halfBCD = (source.* & 0b0000_1111) == 0; 

                break: op Operation{ .deltaPC = 1, .cycles = 8 };
            },
            // INC r8
            0x04, 0x14, 0x24, 0x34, 0x0C, 0x1C, 0x2C, 0x3C => op : {
                const sourceVar: CPU.R8Variant = @enumFromInt((opcode & 0b0011_1000) >> 3);
                const source: *u8 = cpu.getFromR8Variant(sourceVar);
                source.* +%= 1;

                cpu.registers.r8.F.Flags.zero = source.* == 0; 
                cpu.registers.r8.F.Flags.nBCD = false;
                // TODO: Maybe helper function?
                cpu.registers.r8.F.Flags.halfBCD = (source.* & 0b0000_1111) == 0; 

                break: op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 12 else 4 };
            },
            // DEC r8
            0x05, 0x15, 0x25, 0x35, 0x0D, 0x1D, 0x2D, 0x3D => op : {
                const sourceVar: CPU.R8Variant = @enumFromInt((opcode & 0b0011_1000) >> 3);
                const source: *u8 = cpu.getFromR8Variant(sourceVar);
                source.* -%= 1;

                cpu.registers.r8.F.Flags.zero = source.* == 0; 
                cpu.registers.r8.F.Flags.nBCD = false;
                // TODO: Helper function?
                cpu.registers.r8.F.Flags.halfBCD = (source.* & 0b0000_1111) == 0b1111; 

                break: op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 12 else 4 };
            },
            // LD r8, imm8
            0x06, 0x16, 0x26, 0x36, 0x0E, 0x1E, 0x2E, 0x3E => op: {
                const source: *u8 = &cpu.memory[cpu.pc + 1];
                const destVar: CPU.R8Variant = @enumFromInt((opcode & 0b0011_1000) >> 3);
                const dest: *u8 = cpu.getFromR8Variant(destVar);
                dest.* = source.*;

                break: op Operation{ .deltaPC = 2, .cycles = if (destVar == .HL) 12 else 8 };
            },
            // RRRA
            0x1F => op: {
                const A: *u8 = &cpu.registers.r8.A;
                const shiftedBit: bool = (A.* & 0b0000_0001) == 1;
                A.* >>= 1;

                const carry: u8 = @intFromBool(cpu.registers.r8.F.Flags.carry);
                A.* = A.* & (carry << 7);
                cpu.registers.r8.F.Flags.carry = shiftedBit;

                break: op Operation { .deltaPC = 1, .cycles = 4 };
            },
            // JR imm8
            0x20, 0x30, 0x28, 0x38 => op: {
                const condVar: CPU.CondVariant = @enumFromInt((opcode & 0b0001_1000) >> 4);
                const cond: bool = cpu.getFromCondVariant(condVar);
                // TODO: Out of memoery?
                const relDest: u8 = if(cond) cpu.memory[cpu.pc + 1] else 0;
                cpu.pc = cpu.pc + relDest;

                break: op Operation { .deltaPC = 0, .cycles =  if (cond) 12 else 8 };
            },
            // LD r8, r8
            0x40...0x7F => op: {
                // TODO: Break the range, this is not readable honestly!
                // HALT
                if(opcode == 0x76) {
                    // TODO: implement HALT Bug 
                    cpu.isRunning = false;
                    break :op Operation{ .deltaPC = 1, .cycles = 4 };
                }

                const sourceVar: CPU.R8Variant = @enumFromInt(opcode & 0b0000_0111);
                const source: *u8 = cpu.getFromR8Variant(sourceVar);
                const destVar: CPU.R8Variant = @enumFromInt((opcode & 0b0011_1000) >> 3);
                const dest: *u8 = cpu.getFromR8Variant(destVar);
                dest.* = source.*;

                break :op Operation{ .deltaPC = 1, .cycles = 4 };
            },
            // XOR a, r8
            0xA8...0xAF => op: {
                const sourceVar: CPU.R8Variant = @enumFromInt(opcode & 0b0000_0111);
                const source: *u8 = cpu.getFromR8Variant(sourceVar);
                const dest: *u8 = &cpu.registers.r8.A;
                dest.* ^= source.*;

                break :op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 8 else 4 };
            },
            // PUSH r16stk
            0xC5, 0xD5, 0xE5, 0xF5 => op: {
                const sourceVar: CPU.R16StkVariant = @enumFromInt(opcode & 0b0011_0000 >> 4);
                const source: *u16 = cpu.getFromR16StkVariant(sourceVar);
                const stack: *align(1) u16 = @ptrCast(&cpu.memory[cpu.sp]);
                stack.* = source.*;
                cpu.sp -= 2;

                break: op Operation{ .deltaPC = 3, .cycles = 12 };
            },
            // JP imm16
            0xC3 => op : {
                // TODO: Out of memoery? Crashes because if misalignment! => Helper function
                const target: *align(1) u16 = @ptrCast(&cpu.memory[cpu.pc + 1]);
                cpu.pc = target.*;

                break: op Operation { .deltaPC = 0, .cycles =  16 };
            },
            // ERROR!
            else => op: {
                std.debug.print("OPERATION_NOT_IMPLEMENTED: {x}\n", .{opcode});
                cpu.isRunning = false;
                break: op CPUError.OPERATION_NOT_IMPLEMENTED;
            }
        };

        cpu.pc += operation.deltaPC;
        cpu.cycle += operation.cycles;
    }
}
