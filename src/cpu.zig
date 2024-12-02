const std = @import("std");

const MemMap = @import("mem_map.zig");
const MMU = @import("mmu.zig");

const Self = @This();

const FlagRegister = packed union {
    F: u8,
    Flags: packed struct {
        _: u4 = 0,
        // TODO: consider to use u1 instead of bool so I have less conversions!
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

registers: Registers = .{ .r16 = .{} },

// Program counter
pc: u16 = 0,
// Stack pointer
sp: u16 = 0,
// How many cycles the cpu is now ahead of the rest of the system.
cycles_ahead: u8 = 0,
ime: bool = false,
// The effect of EI is delayed by one instruction.
ime_requested: bool = false,
// TODO: Maybe state flags?
// TODO: How to handle stopped state of cpu?
isStopped: bool = false,
isHalted: bool = false,

pub fn init() !Self {
    var cpu = Self{};

    // state after DMG Boot rom has run.
    // https://gbdev.io/pandocs/Power_Up_Sequence.html#cpu-registers
    cpu.registers.r16.AF = 0x01B0;
    cpu.registers.r16.BC = 0x0013;
    cpu.registers.r16.DE = 0x00D8;
    cpu.registers.r16.HL = 0x014D;
    cpu.pc = 0x0100;
    cpu.sp = 0xFFFE;

    return cpu;
}

pub fn deinit(_: *Self) void {
}

// Instruction Variants (Sets of instructions that do the same, but to different targets/source).
const R8Variant = enum(u8) { B, C, D, E, H, L, HL, A, };
pub fn getFromR8Variant(self: *Self, variant: R8Variant, mmu: *MMU) u8 {
    return switch (variant) {
        .B => self.registers.r8.B,
        .C => self.registers.r8.C,
        .D => self.registers.r8.D,
        .E => self.registers.r8.E,
        .H => self.registers.r8.H,
        .L => self.registers.r8.L,
        .HL => mmu.read8(self.registers.r16.HL),
        .A => self.registers.r8.A,
    };
}

// TODO: I hate that I have to split it this into get and set.
// A solution would be to put the registers into echo ram. This is a range that the actual emulated system does not actually use.
// Then it does not matter wheter i access a register or memory location, all of them are addresses into the memory block.
// So all the Variants can work just like the getFromR16MemVariant() that returns an address of the thing into the memory block.
pub fn setFromR8Variant(self: *Self, variant: R8Variant, mmu: *MMU, val: u8) void {
    return switch (variant) {
        .B => self.registers.r8.B = val,
        .C => self.registers.r8.C = val,
        .D => self.registers.r8.D = val,
        .E => self.registers.r8.E = val,
        .H => self.registers.r8.H = val,
        .L => self.registers.r8.L = val,
        .HL =>  mmu.write8(self.registers.r16.HL, val),
        .A => self.registers.r8.A = val,
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
pub fn getFromR16MemVariant(self: *Self, variant: R16MemVariant) u16 {
    return switch (variant) {
        .BC => self.registers.r16.BC,
        .DE => self.registers.r16.DE,
        .HLinc => blk: {
            const addr: u16 = self.registers.r16.HL;
            self.registers.r16.HL +%= 1;
            break: blk addr;
        },
        .HLdec => blk: {
            const addr: u16 = self.registers.r16.HL;
            self.registers.r16.HL -%= 1;
            break: blk addr;
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

fn debugPrintState(self: *Self, mmu: *MMU) void {
    std.debug.print("A: {X:0>2} F: {X:0>2} ", .{ self.registers.r8.A, self.registers.r8.F.F });
    std.debug.print("B: {X:0>2} C: {X:0>2} ", .{ self.registers.r8.B, self.registers.r8.C });
    std.debug.print("D: {X:0>2} E: {X:0>2} ", .{ self.registers.r8.D, self.registers.r8.E });
    std.debug.print("H: {X:0>2} L: {X:0>2} ", .{ self.registers.r8.H, self.registers.r8.L });
    std.debug.print("SP: {X:0>4} PC: 00:{X:0>4} ", .{ self.sp, self.pc });
    std.debug.print("({X:0>2} {X:0>2} {X:0>2} {X:0>2})", .{
        mmu.read8(self.pc), mmu.read8(self.pc +% 1), 
        mmu.read8(self.pc +% 2), mmu.read8(self.pc +% 3), 
    });
    std.debug.print("\n", .{});
}

// TODO: Where does the interrupt handler code live?
    // a) Have a fixed position in memory where I save cpu code that is the interrupt handler. It is saved in unused memory range.
    // To do that I would have to have two pc. one normal one and one interrupt_pc.
    // When you detect an interrupt => set the interrupt_pc to the current pc.  
    // b) Maybe we can "memory map" the interrupt handler to the current programm counter position (using the mmu)?
    // It overlays the normal code. 
    // I mean I already require this behaviour for the BootROM? 
    // The actual routine lives in a range of memory that is usually inacessible by the gameboy (unused or echo ram).

const interruptVector = [_]u16{ 0x40, 0x48, 0x50, 0x58, 0x60 };
// returns true if we handled an interrupt.
pub fn tryInterrupt(self: *Self, mmu: *MMU) bool {
    // TODO: Implement this without conditions!
    if(!self.ime) {
        return false;
    }

    const enable = mmu.read8(MemMap.INTERRUPT_ENABLE);
    const flag = mmu.read8(MemMap.INTERRUPT_FLAG);
    var currFlag = MemMap.INTERRUPT_VBLANK;
    // TODO: Can I calculate this from the current flag?
    var flagIndex: u8 = 0;
    while (currFlag > 0) : (currFlag <<= 1) {
        const hasInterrupt: bool = ((enable & flag) & currFlag) == currFlag;
        if(!hasInterrupt) {
            flagIndex += 1;
            continue;
        }

        self.isHalted = false;
        self.ime = false;
        const mask: u8 = ~currFlag;
        mmu.write8(MemMap.INTERRUPT_FLAG, flag & mask);
        self.sp -= 2;
        mmu.write16(self.sp, self.pc);
        self.pc = interruptVector[flagIndex];
        self.cycles_ahead = 20;
        return true;
    }

    return false;
}


pub fn step(self: *Self, mmu: *MMU) !void {
    if(self.tryInterrupt(mmu)) {
        return;
    }

    // TODO: Do this without a super late check?
    // Maybe I can solve this similar to the interrupt handler living somewhere in memory?
    if(self.isHalted) {
        self.cycles_ahead = 4;
        return;
    }

    // TODO: I would like an implementation without a super late bool check, okay for now.
    if(self.ime_requested) {
        self.ime_requested = false;
        self.ime = true;
    }

    // TODO: Check if we can actually implement most of the instructions without all the pointers?
    var opcode: u8 = mmu.read8(self.pc);
    const operation: Operation = try switch (opcode) {
        // NOOP
        0x00 => Operation{ .deltaPC = 1, .cycles = 4 },
        // LD r16, imm16
        0x01, 0x11, 0x21, 0x31 => op: {
            const source: u16 = mmu.read16((self.pc +% 1));
            const destVar: R16Variant = @enumFromInt((opcode & 0b0011_0000) >> 4);
            const dest: *u16 = self.getFromR16Variant(destVar);
            dest.* = source;

            break: op Operation{ .deltaPC = 3, .cycles = 12 };
        },
        // LD r16mem, a
        0x02, 0x12, 0x22, 0x32 => op: {
            const destVar: R16MemVariant = @enumFromInt((opcode & 0b0011_0000) >> 4);
            const dest: u16 = self.getFromR16MemVariant(destVar);
            mmu.write8(dest, self.registers.r8.A);

            break: op Operation{ .deltaPC =  1, .cycles = 8 };
        },
        // Inc r16
        0x03, 0x13, 0x23, 0x33 => op: {
            const sourceVar: R16Variant = @enumFromInt((opcode & 0b0011_0000) >> 4);
            const source: *u16 = self.getFromR16Variant(sourceVar);
            source.* +%= 1;

            break: op Operation{ .deltaPC = 1, .cycles = 8 };
        },
        // INC r8
        0x04, 0x14, 0x24, 0x34, 0x0C, 0x1C, 0x2C, 0x3C => op : {
            const sourceVar: R8Variant = @enumFromInt((opcode & 0b0011_1000) >> 3);
            const source: u8 = self.getFromR8Variant(sourceVar, mmu);
            const result: u8 = source +% 1;

            self.registers.r8.F.Flags.zero = result == 0; 
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = (((source & 0x0F) +% 1) & 0x10) == 0x10; 

            self.setFromR8Variant(sourceVar, mmu, result);
            break: op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 12 else 4 };
        },
        // DEC r8
        0x05, 0x15, 0x25, 0x35, 0x0D, 0x1D, 0x2D, 0x3D => op : {
            const sourceVar: R8Variant = @enumFromInt((opcode & 0b0011_1000) >> 3);
            const source: u8 = self.getFromR8Variant(sourceVar, mmu);
            const result: u8 = source -% 1;

            self.registers.r8.F.Flags.zero = result == 0; 
            self.registers.r8.F.Flags.nBCD = true;
            self.registers.r8.F.Flags.halfBCD = (((source & 0x0F) -% 1) & 0x10) == 0x10; 

            self.setFromR8Variant(sourceVar, mmu, result);
            break: op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 12 else 4 };
        },
        // LD r8, imm8
        0x06, 0x16, 0x26, 0x36, 0x0E, 0x1E, 0x2E, 0x3E => op: {
            const source: u8 =  mmu.read8(self.pc +% 1);
            const destVar: R8Variant = @enumFromInt((opcode & 0b0011_1000) >> 3);
            self.setFromR8Variant(destVar, mmu, source);

            break: op Operation{ .deltaPC = 2, .cycles = if (destVar == .HL) 12 else 8 };
        },
        // RLCA
        0x07 => op: {
            const A: *u8 = &self.registers.r8.A;
            const shiftedBit: u8 = (A.* & 0x80);
            A.* <<= 1;

            A.* |= (shiftedBit >> 7);
            self.registers.r8.F.Flags.carry = shiftedBit == 0x80;
            self.registers.r8.F.Flags.zero = false;
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = false; 

            break: op Operation { .deltaPC = 1, .cycles = 4 };
        },
        // LD (imm16),SP
        0x08 => op: {
            const source: u16 = mmu.read16(self.pc +% 1);
            mmu.write16(source, self.sp);

            break: op Operation { .deltaPC = 3, .cycles = 20 };
        },
        // LD a, r16mem
        0x0A, 0x1A, 0x2A, 0x3A => op: {
            const sourceVar: R16MemVariant = @enumFromInt((opcode & 0b0011_0000) >> 4);
            const source: u16 = self.getFromR16MemVariant(sourceVar);
            self.registers.r8.A = mmu.read8(source);

            break: op Operation{ .deltaPC =  1, .cycles = 8 };
        }, 
        // DEC r16
        0x0B, 0x1B, 0x2B, 0x3B => op: {
            const sourceVar: R16Variant = @enumFromInt((opcode & 0b0011_0000) >> 4);
            const source: *u16 = self.getFromR16Variant(sourceVar);
            source.* -%= 1;

            break: op Operation{ .deltaPC = 1, .cycles = 8 };
        },
        // ADD HL, R16
        0x09, 0x19, 0x29, 0x39 => op : {
            const sourceVar: R16Variant = @enumFromInt((opcode & 0b0011_0000) >> 4);
            const source: *u16 = self.getFromR16Variant(sourceVar);
            const result, const overflow = @addWithOverflow(self.registers.r16.HL, source.*);

            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = (((self.registers.r16.HL & 0xFFF) + (source.* & 0xFFF)) & 0x1000) ==  0x1000;
            self.registers.r8.F.Flags.carry = overflow == 1;

            self.registers.r16.HL = result;
            break: op Operation { .deltaPC = 1, .cycles = 8 };
        },
        // RRCA
        0x0F => op: {
            const A: *u8 = &self.registers.r8.A;
            const shiftedBit: u8 = A.* & 0x01;
            A.* >>= 1;

            A.* |= (shiftedBit << 7);
            self.registers.r8.F.Flags.carry = shiftedBit == 1;
            self.registers.r8.F.Flags.zero = false;
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = false;

            break: op Operation { .deltaPC = 1, .cycles = 4 };
        },
        // STOP
        0x10 => op: {
            self.isStopped = true;
            break: op Operation { .deltaPC = 1, .cycles = 4};
        },
        // RLA
        0x17 => op: {
            const A: *u8 = &self.registers.r8.A;
            const shiftedBit: bool = (A.* & 0x80) == 0x80;
            A.* <<= 1;

            const carry: u8 = @intFromBool(self.registers.r8.F.Flags.carry);
            A.* |= carry;
            self.registers.r8.F.Flags.carry = shiftedBit;
            self.registers.r8.F.Flags.zero = false;
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = false;

            break: op Operation { .deltaPC = 1, .cycles = 4 };
        },
        // JR r8
        0x18 => op: {
            const relDest: i8 = mmu.readi8(self.pc +% 1);
            self.pc +%= @as(u16, @bitCast(@as(i16, relDest))); 
            self.pc +%= 2; // size of instruction 

            break: op Operation { .deltaPC = 0, .cycles =  12 };
        },
        // RRA
        0x1F => op: {
            const A: *u8 = &self.registers.r8.A;
            const shiftedBit: bool = (A.* & 0x01) == 0x01;
            A.* >>= 1;

            const carry: u8 = @intFromBool(self.registers.r8.F.Flags.carry);
            A.* |= (carry << 7);
            self.registers.r8.F.Flags.carry = shiftedBit;
            self.registers.r8.F.Flags.zero = false;
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = false;

            break: op Operation { .deltaPC = 1, .cycles = 4 };
        },
        // JR cond imm8
        0x20, 0x30, 0x28, 0x38 => op: {
            const condVar: CondVariant = @enumFromInt((opcode & 0b0001_1000) >> 3);
            const cond: bool = self.getFromCondVariant(condVar);

            const relDest: i8 = mmu.readi8(self.pc +% 1);
            self.pc +%= if (cond) @as(u16, @bitCast(@as(i16, relDest))) else 0;
            self.pc +%= 2; // size of instruction 

            break: op Operation { .deltaPC = 0, .cycles =  if (cond) 12 else 8 };
        },
        // DAA
        0x27 => op: {
            const a: u8 = self.registers.r8.A;
            const halfBCD = self.registers.r8.F.Flags.halfBCD;
            const carry = self.registers.r8.F.Flags.carry;
            const subtract = self.registers.r8.F.Flags.nBCD;

            var offset: u8 = 0;
            var shouldCarry: bool = false;

            if((!subtract and ((a & 0xF) > 0x09)) or halfBCD) {
                offset |= 0x06;
            }

            if((!subtract and (a > 0x99)) or carry) {
                offset |= 0x60;
                shouldCarry = true;
            }

            const result = if (subtract) a -% offset else a +% offset;
            self.registers.r8.A = result;

            self.registers.r8.F.Flags.carry = shouldCarry;
            self.registers.r8.F.Flags.zero = result == 0;
            self.registers.r8.F.Flags.halfBCD = false;

            break: op Operation{ .deltaPC = 1, .cycles = 4 };
        },
        // CPL (complement A)
        0x2F => op: {
            const A: *u8 = &self.registers.r8.A;
            A.* = ~A.*;

            self.registers.r8.F.Flags.nBCD = true;
            self.registers.r8.F.Flags.halfBCD = true;

            break: op Operation{ .deltaPC = 1, .cycles = 4 };
        },
        // SCF (Set Carry Flag)
        0x37 => op: {
            self.registers.r8.F.Flags.carry = true;
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = false;

            break: op Operation { .deltaPC = 1, .cycles = 4 };
        },
        // CCF (Complement Carry Flag)
        0x3F => op: {
            self.registers.r8.F.Flags.carry = !self.registers.r8.F.Flags.carry;
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = false;

            break: op Operation { .deltaPC = 1, .cycles = 4 };
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
            const source: u8 = self.getFromR8Variant(sourceVar, mmu);
            const destVar: R8Variant = @enumFromInt((opcode & 0b0011_1000) >> 3);
            self.setFromR8Variant(destVar, mmu, source);

            break :op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL or destVar == .HL) 8 else 4 };
        },
        // ADD a, r8
        0x80...0x87 => op: {
            const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
            const source: u8 = self.getFromR8Variant(sourceVar, mmu);
            const A: *u8 = &self.registers.r8.A;
            const result, const overflow = @addWithOverflow(A.*, source);

            self.registers.r8.F.Flags.zero = result == 0;
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = ((A.* & 0x0F) +% (source & 0x0F)) > 0x0F;
            self.registers.r8.F.Flags.carry = overflow == 1;

            A.* = result;
            break :op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 8 else 4 };
        },
        // ADC a, r8
        0x88...0x8F => op: {
            const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
            const source: u8 = self.getFromR8Variant(sourceVar, mmu);
            const A: *u8 = &self.registers.r8.A;
            const carry: u8 = @intFromBool(self.registers.r8.F.Flags.carry);
            const sourceCarry, const carryOverflow = @addWithOverflow(source, carry);
            const result, const overflow = @addWithOverflow(A.*, sourceCarry);

            self.registers.r8.F.Flags.zero = result == 0;
            self.registers.r8.F.Flags.nBCD = false;
            const sourceHalfBCD: bool = (((source & 0x0F) +% (carry & 0x0F)) & 0x10) == 0x10;
            const sourceCaryHalfBCD: bool = (((A.* & 0x0F) +% (sourceCarry & 0x0F)) & 0x10) == 0x10;
            self.registers.r8.F.Flags.halfBCD = sourceHalfBCD or sourceCaryHalfBCD;
            self.registers.r8.F.Flags.carry = carryOverflow == 1 or overflow == 1;

            A.* = result;
            break :op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 8 else 4 };
        },  
        // SUB a, r8
        0x90...0x97 => op: {
            const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
            const source: u8 = self.getFromR8Variant(sourceVar, mmu);
            const A: *u8 = &self.registers.r8.A;
            const result, const overflow = @subWithOverflow(A.*, source);

            self.registers.r8.F.Flags.zero = result == 0;
            self.registers.r8.F.Flags.nBCD = true;
            self.registers.r8.F.Flags.halfBCD = (((A.* & 0x0F) -% (source & 0x0F)) & 0x10) == 0x10;
            self.registers.r8.F.Flags.carry = overflow == 1;

            A.* = result;
            break: op Operation { .deltaPC = 1, .cycles = if (sourceVar == .HL) 8 else 4 };
        },  
        // SBC a, r8
        0x98...0x9F => op: {
            const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
            const source: u8 = self.getFromR8Variant(sourceVar, mmu);
            const A: *u8 = &self.registers.r8.A;
            const carry: u8 = @intFromBool(self.registers.r8.F.Flags.carry);
            const sourceCarry, const carryOverflow = @addWithOverflow(source, carry);
            const result, const overflow = @subWithOverflow(A.*, sourceCarry);

            self.registers.r8.F.Flags.zero = result == 0;
            self.registers.r8.F.Flags.nBCD = true;
            const sourceHalfBCD: bool = (((source & 0x0F) +% (carry & 0x0F)) & 0x10) == 0x10;
            const sourceCaryHalfBCD: bool = (((A.* & 0x0F) -% (sourceCarry & 0x0F)) & 0x10) == 0x10;
            self.registers.r8.F.Flags.halfBCD = sourceHalfBCD or sourceCaryHalfBCD;
            self.registers.r8.F.Flags.carry = carryOverflow == 1 or overflow == 1;

            A.* = result;
            break :op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 8 else 4 };
        },  
        // AND a, r8
        0xA0...0xA7 => op: {
            const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
            const source: u8 = self.getFromR8Variant(sourceVar, mmu);
            const A: *u8 = &self.registers.r8.A;
            A.* &= source;

            self.registers.r8.F.Flags.zero = A.* == 0;
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = true;
            self.registers.r8.F.Flags.carry = false;

            break :op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 8 else 4 };
        },
        // XOR a, r8
        0xA8...0xAF => op: {
            const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
            const source: u8 = self.getFromR8Variant(sourceVar, mmu);
            const dest: *u8 = &self.registers.r8.A;
            dest.* ^= source;

            self.registers.r8.F.Flags.zero = dest.* == 0;
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = false;
            self.registers.r8.F.Flags.carry = false;

            break :op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 8 else 4 };
        },
        // OR a, r8
        0xB0...0xB7 => op: {
            const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
            const source: u8 = self.getFromR8Variant(sourceVar, mmu);
            const dest: *u8 = &self.registers.r8.A;
            dest.* |= source;

            self.registers.r8.F.Flags.zero = dest.* == 0;
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = false;
            self.registers.r8.F.Flags.carry = false;

            break :op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 8 else 4 };
        },
        // CP a, r8
        0xB8...0xBF => op: {
            const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
            const source: u8 = self.getFromR8Variant(sourceVar, mmu);
            const A: *u8 = &self.registers.r8.A;
            _, const overflow = @subWithOverflow(A.*, source);

            self.registers.r8.F.Flags.zero = A.* == source;
            self.registers.r8.F.Flags.nBCD = true;
            self.registers.r8.F.Flags.halfBCD = (((A.* & 0x0F) -% (source & 0x0F)) & 0x10) == 0x10;
            self.registers.r8.F.Flags.carry = overflow == 1;

            break :op Operation{ .deltaPC = 1, .cycles = if (sourceVar == .HL) 8 else 4 };
        },
        // RET cond
        0xC0, 0xC8, 0xD0, 0xD8 => op: {
            const condVar: CondVariant = @enumFromInt((opcode & 0b0001_1000) >> 3);
            const cond: bool = self.getFromCondVariant(condVar);

            if(cond) {
                self.pc = mmu.read16(self.sp);
                self.sp += 2;
            }

            break :op Operation{ .deltaPC = if (cond) 0 else 1, .cycles = if(cond) 20 else 8 };
        },
        // POP r16stk
        0xC1, 0xD1, 0xE1, 0xF1 => op: {
            const destVar: R16StkVariant = @enumFromInt((opcode & 0b0011_0000) >> 4);
            const dest: *u16 = self.getFromR16StkVariant(destVar);

            const stack: u16 = mmu.read16(self.sp);
            dest.* = stack;
            self.sp += 2;

            // If you do a pop on the AF register (0xF1), you need to make sure that the lowest nibble stays 0.
            if(destVar == .AF) {
                dest.* &= 0xFFF0;
            }

            break: op Operation{ .deltaPC = 1, .cycles = 12 };
        },                
        // JP cond imm16
        0xC2, 0xD2, 0xCA, 0xDA => op: {
            const condVar: CondVariant = @enumFromInt((opcode & 0b0001_1000) >> 3);
            const cond: bool = self.getFromCondVariant(condVar);

            const target: u16 = mmu.read16(self.pc +% 1);
            self.pc = if(cond) target else (self.pc + 3);

            break: op Operation { .deltaPC = 0, .cycles =  if (cond) 16 else 12 };
        },
        // PUSH r16stk
        0xC5, 0xD5, 0xE5, 0xF5 => op: {
            const sourceVar: R16StkVariant = @enumFromInt((opcode & 0b0011_0000) >> 4);
            const source: *u16 = self.getFromR16StkVariant(sourceVar);

            self.sp -= 2;
            mmu.write16(self.sp, source.*);

            break: op Operation{ .deltaPC = 1, .cycles = 16 };
        },
        // JP imm16
        0xC3 => op : {
            self.pc = mmu.read16(self.pc +% 1);

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
                mmu.write16(self.sp, self.pc +% 3);

                // jump to imm16
                self.pc = mmu.read16(self.pc +% 1);
            }

            break: op Operation { .deltaPC = if(cond) 0 else 3, .cycles = if(cond) 24 else 12 };
        },
        // ADD a, imm8
        0xC6 => op: {
            // TODO: For add, adc, sub, sbc, and, xor, or, cp we have basically the same code and instruction.
            const source: u8 = mmu.read8(self.pc +% 1);
            const A: *u8 = &self.registers.r8.A;
            const result, const overflow = @addWithOverflow(A.*, source);

            self.registers.r8.F.Flags.zero = result == 0;
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = ((A.* & 0x0F) +% (source & 0x0F)) > 0x0F;
            self.registers.r8.F.Flags.carry = overflow == 1;

            A.* = result;
            break :op Operation{ .deltaPC = 2, .cycles = 8 };
        },
        // RST target
        0xC7, 0xD7, 0xE7, 0xF7, 0xCF, 0xDF, 0xEF, 0xFF => op : {
            // push next address onto stack.
            self.sp -= 2;
            mmu.write16(self.sp, self.pc +% 1);

            const target: u16 = 8 * @as(u16, ((opcode & 0b0011_1000) >> 3));
            self.pc = target;

            break: op Operation{ .deltaPC = 0, .cycles = 16 };
        },
        // RET
        0xC9 => op : {
            // TODO: We have instructions for conditional calls/returns. Which are basically the same code as the unconditional returns.
            // TODO: Can I compbine those? return and conditional return have the same opcode structure, they only differ by the first bit.
            self.pc = mmu.read16(self.sp);
            self.sp += 2;

            break: op Operation { .deltaPC = 0, .cycles =  16 };
        },
        // PREFIX CB
        0xCB => op: {
            // TODO: Maybe there is solution without nesting this?
            opcode = mmu.read8(self.pc +% 1);
            break: op switch (opcode) {
                // RLC r8
                0x00...0x07 => op_pfx: {
                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    var source: u8 = self.getFromR8Variant(sourceVar, mmu);
                    const shiftedBit: u8 = source & 0x80;
                    source <<= 1;
                    source |= (shiftedBit >> 7);
                    self.setFromR8Variant(sourceVar, mmu, source);

                    self.registers.r8.F.Flags.carry = shiftedBit == 0x80;
                    self.registers.r8.F.Flags.zero = source == 0;
                    self.registers.r8.F.Flags.nBCD = false;
                    self.registers.r8.F.Flags.halfBCD = false;

                    break: op_pfx Operation { .deltaPC = 2, .cycles = if (sourceVar == .HL) 16 else 8 };
                },
                // RRC r8 
                0x08...0x0F => op_pfx : {
                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    var source: u8 = self.getFromR8Variant(sourceVar, mmu);
                    const shiftedBit: u8 = (source & 0x01);
                    source >>= 1;
                    source |= (shiftedBit << 7);
                    self.setFromR8Variant(sourceVar, mmu, source);

                    self.registers.r8.F.Flags.carry = shiftedBit == 1;
                    self.registers.r8.F.Flags.zero = source == 0;
                    self.registers.r8.F.Flags.nBCD = false;
                    self.registers.r8.F.Flags.halfBCD = false;

                    break: op_pfx Operation { .deltaPC = 2, .cycles = if (sourceVar == .HL) 16 else 8 };
                },
                // RL r8
                0x10...0x17 => op_pfx: {
                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    var source: u8 = self.getFromR8Variant(sourceVar, mmu);
                    const shiftedBit: bool = (source & 0x80) == 0x80;
                    source <<= 1;
                    const carry: u8 = @intFromBool(self.registers.r8.F.Flags.carry);
                    source |= carry;
                    self.setFromR8Variant(sourceVar, mmu, source);

                    self.registers.r8.F.Flags.carry = shiftedBit;
                    self.registers.r8.F.Flags.zero = source == 0;
                    self.registers.r8.F.Flags.nBCD = false;
                    self.registers.r8.F.Flags.halfBCD = false;

                    break: op_pfx Operation { .deltaPC = 2, .cycles = if (sourceVar == .HL) 16 else 8 };
                },
                // RR r8 
                0x18...0x1F => op_pfx : {
                    // TODO: RR and RRA is basically the same?
                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    var source: u8 = self.getFromR8Variant(sourceVar, mmu);
                    const shiftedBit: bool = (source & 0x01) == 0x01;
                    source >>= 1;
                    const carry: u8 = @intFromBool(self.registers.r8.F.Flags.carry);
                    source |= (carry << 7);
                    self.setFromR8Variant(sourceVar, mmu, source);

                    self.registers.r8.F.Flags.carry = shiftedBit;
                    self.registers.r8.F.Flags.zero = source == 0;
                    self.registers.r8.F.Flags.nBCD = false;
                    self.registers.r8.F.Flags.halfBCD = false;

                    break: op_pfx Operation { .deltaPC = 2, .cycles = if (sourceVar == .HL) 16 else 8 };
                },
                // SLA r8
                0x20...0x27 => op_pfx: {
                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    var source: u8 = self.getFromR8Variant(sourceVar, mmu);
                    const shiftedBit: bool = (source & 0x80) == 0x80;
                    source <<= 1;
                    self.setFromR8Variant(sourceVar, mmu, source);

                    self.registers.r8.F.Flags.carry = shiftedBit;
                    self.registers.r8.F.Flags.zero = source == 0;
                    self.registers.r8.F.Flags.nBCD = false;
                    self.registers.r8.F.Flags.halfBCD = false;

                    break: op_pfx Operation { .deltaPC = 2, .cycles = if (sourceVar == .HL) 16 else 8 };
                },
                // SWAP r8
                0x30...0x37 => op_pfx: {
                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    var source: u8 = self.getFromR8Variant(sourceVar, mmu);
                    source = (source << 4) | (source >> 4);
                    self.setFromR8Variant(sourceVar, mmu, source);

                    self.registers.r8.F.Flags.carry = false;
                    self.registers.r8.F.Flags.zero = source == 0;
                    self.registers.r8.F.Flags.nBCD = false;
                    self.registers.r8.F.Flags.halfBCD = false;

                    break: op_pfx Operation { .deltaPC = 2, .cycles = if (sourceVar == .HL) 16 else 8 };
                },
                // SRA r8
                0x28...0x2F => op_pfx: {
                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    var source: u8 = self.getFromR8Variant(sourceVar, mmu);
                    const shiftedBit: bool = (source & 0x01) == 0x01;
                    const msb: u8 = source & 0x80;
                    source >>= 1;
                    source |= msb;
                    self.setFromR8Variant(sourceVar, mmu, source);

                    self.registers.r8.F.Flags.carry = shiftedBit;
                    self.registers.r8.F.Flags.zero = source == 0;
                    self.registers.r8.F.Flags.nBCD = false;
                    self.registers.r8.F.Flags.halfBCD = false;

                    break: op_pfx Operation { .deltaPC = 2, .cycles = if (sourceVar == .HL) 16 else 8 };
                },
                // SRL r8
                0x38...0x3F => op_pfx: {
                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    var source: u8 = self.getFromR8Variant(sourceVar, mmu);
                    const shiftedBit: bool = (source & 0x01) == 0x01;
                    source >>= 1;
                    self.setFromR8Variant(sourceVar, mmu, source);

                    self.registers.r8.F.Flags.carry = shiftedBit;
                    self.registers.r8.F.Flags.nBCD = false;
                    self.registers.r8.F.Flags.halfBCD = false;
                    self.registers.r8.F.Flags.zero = source == 0;

                    break: op_pfx Operation { .deltaPC = 2, .cycles = if (sourceVar == .HL) 16 else 8 };
                },
                // BIT bit,r8
                0x40...0x7F => op_pfx: {
                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    const source: u8 = self.getFromR8Variant(sourceVar, mmu);
                    const bitIndex: u3 = @intCast((opcode & 0b0011_1000) >> 3);
                    const result: u8 = source & (@as(u8, 1) << bitIndex);

                    self.registers.r8.F.Flags.nBCD = false;
                    self.registers.r8.F.Flags.halfBCD = true;
                    self.registers.r8.F.Flags.zero = result == 0;

                    break: op_pfx Operation { .deltaPC = 2, .cycles = if (sourceVar == .HL) 12 else 8};
                },
                // RES bit,r8
                0x80...0xBF => op_pfx: {
                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    var source: u8 = self.getFromR8Variant(sourceVar, mmu);
                    const bitIndex: u3 = @intCast((opcode & 0b0011_1000) >> 3);
                    source &= ~(@as(u8, 1) << bitIndex);
                    self.setFromR8Variant(sourceVar, mmu, source);

                    break: op_pfx Operation { .deltaPC = 2, .cycles = if (sourceVar == .HL) 16 else 8};
                },
                // SET bit,r8
                0xC0...0xFF => op_pfx: {
                    const sourceVar: R8Variant = @enumFromInt(opcode & 0b0000_0111);
                    var source: u8 = self.getFromR8Variant(sourceVar, mmu);
                    const bitIndex: u3 = @intCast((opcode & 0b0011_1000) >> 3);
                    source |= (@as(u8, 1) << bitIndex);
                    self.setFromR8Variant(sourceVar, mmu, source);

                    break: op_pfx Operation { .deltaPC = 2, .cycles = if (sourceVar == .HL) 16 else 8};
                },
            };
        },
        // CALL imm16
        0xCD => op : {
            // TODO: We have instructions for conditional calls/returns. Which are basically the same code as the unconditional call.
            // TODO: Can I compbine those? Call and conditional call have the same opcode structure, they only differ by the first bit.
            // push next address onto stack.
            self.sp -= 2;
            mmu.write16(self.sp, self.pc +% 3);

            // jump to imm16
            self.pc = mmu.read16(self.pc +% 1);

            break: op Operation { .deltaPC = 0, .cycles =  24 };
        },
        // ADC a, imm8
        0xCE => op: {
            const source: u8 = mmu.read8(self.pc +% 1);
            const A: *u8 = &self.registers.r8.A;
            const carry: u8 = @intFromBool(self.registers.r8.F.Flags.carry);
            const sourceCarry, const carryOverflow = @addWithOverflow(source, carry);
            const result, const overflow = @addWithOverflow(A.*, sourceCarry);

            self.registers.r8.F.Flags.zero = result == 0;
            self.registers.r8.F.Flags.nBCD = false;
            const sourceHalfBCD: bool = (((source & 0x0F) +% (carry & 0x0F)) & 0x10) == 0x10;
            const sourceCaryHalfBCD: bool = (((A.* & 0x0F) +% (sourceCarry & 0x0F)) & 0x10) == 0x10;
            self.registers.r8.F.Flags.halfBCD = sourceHalfBCD or sourceCaryHalfBCD;
            self.registers.r8.F.Flags.carry = carryOverflow == 1 or overflow == 1;

            A.* = result;
            break :op Operation{ .deltaPC = 2, .cycles = 8 };
        },  
        // SUB a, r8
        0xD6 => op: {
            // TODO: For add, adc, sub, sbc, and, xor, or, cp we have basically the same code and instruction.
            const source: u8 = mmu.read8(self.pc +% 1);
            const A: *u8 = &self.registers.r8.A;
            const result, const overflow = @subWithOverflow(A.*, source);

            self.registers.r8.F.Flags.zero = result == 0;
            self.registers.r8.F.Flags.nBCD = true;
            self.registers.r8.F.Flags.halfBCD = (((A.* & 0x0F) -% (source & 0x0F)) & 0x10) == 0x10;
            self.registers.r8.F.Flags.carry = overflow == 1;

            A.* = result;
            break :op Operation{ .deltaPC = 2, .cycles = 8 };
        },  
        // RETI
        0xD9 => op : {
            self.pc = mmu.read16(self.sp);
            self.sp += 2;
            self.ime = true;

            break: op Operation { .deltaPC = 0, .cycles =  16 };
        },
        // SBC a, imm8
        0xDE => op: {
            // TODO: For add, adc, sub, sbc, and, xor, or, cp we have basically the same code and instruction.
            const source: u8 = mmu.read8(self.pc +% 1);
            const A: *u8 = &self.registers.r8.A;
            const carry: u8 = @intFromBool(self.registers.r8.F.Flags.carry);
            const sourceCarry, const carryOverflow = @addWithOverflow(source, carry);
            const result, const overflow = @subWithOverflow(A.*, sourceCarry);

            self.registers.r8.F.Flags.zero = result == 0;
            self.registers.r8.F.Flags.nBCD = true;
            const sourceHalfBCD: bool = (((source & 0x0F) +% (carry & 0x0F)) & 0x10) == 0x10;
            const sourceCaryHalfBCD: bool = (((A.* & 0x0F) -% (sourceCarry & 0x0F)) & 0x10) == 0x10;
            self.registers.r8.F.Flags.halfBCD = sourceHalfBCD or sourceCaryHalfBCD;
            self.registers.r8.F.Flags.carry = carryOverflow == 1 or overflow == 1;

            A.* = result;
            break :op Operation{ .deltaPC = 2, .cycles = 8 };
        },  
        // LDH [imm8], a
        0xE0 => op: {
            const source: u8 = mmu.read8(self.pc +% 1);
            mmu.write8(MemMap.HIGH_PAGE + source, self.registers.r8.A);

            break: op Operation { .deltaPC = 2, .cycles = 12 };
        },
        // LD [c], a
        0xE2 => op: {
            mmu.write8(MemMap.HIGH_PAGE + self.registers.r8.C, self.registers.r8.A);

            break: op Operation { .deltaPC = 1, .cycles = 8 };
        },
        // LD [imm16], a
        0xEA => op: {
            const dest: u16 = mmu.read16(self.pc +% 1);
            mmu.write8(dest, self.registers.r8.A);

            break: op Operation { .deltaPC = 3, .cycles = 16 };
        },
        // AND a, imm8
        0xE6 => op: {
            // TODO: For add, adc, sub, sbc, and, xor, or, cp we have basically the same code and instruction.
            // Difference is only if we use an immediate value or not. Can we make this a better re-use?
            // The difference of the instructions is that the variant is HL + the 2nd bit is set (6th value).
            // So I can change the mask to improve this! Cycle time is the same as HL!
            const source: u8 = mmu.read8(self.pc +% 1);
            const A: *u8 = &self.registers.r8.A;
            A.* &= source;

            self.registers.r8.F.Flags.zero = A.* == 0;
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = true;
            self.registers.r8.F.Flags.carry = false;

            break :op Operation{ .deltaPC = 2, .cycles = 8 };
        },
        // ADD SP, imm8 (signed)
        0xE8 => op: {
            const deltaSP: i8 = mmu.readi8(self.pc +% 1); 

            self.registers.r8.F.Flags.zero = false;
            self.registers.r8.F.Flags.nBCD = false;
            _, const halfOverflow = @addWithOverflow(@as(u4, @truncate(self.sp)), @as(u4, @intCast(deltaSP & 0xF)));
            self.registers.r8.F.Flags.halfBCD = halfOverflow == 1;
            _, const carryOverflow = @addWithOverflow(@as(u8, @truncate(self.sp)), @as(u8, @bitCast(deltaSP)));
            self.registers.r8.F.Flags.carry = carryOverflow == 1;

            self.sp +%= @as(u16, @bitCast(@as(i16, deltaSP)));
            break :op Operation{ .deltaPC = 2, .cycles = 16 };
        },
        // JP (HL)
        0xE9 => op : {
            // TODO: This code is basically the same as JP imm16, and JP and JP Cond is basically the same, combine them!
            self.pc = self.registers.r16.HL;

            break: op Operation { .deltaPC = 0, .cycles =  4 };
        },
        // XOR a, imm8
        0xEE => op: {
            // TODO: For add, adc, sub, sbc, and, xor, or, cp we have basically the same code and instruction.
            const source: u8 = mmu.read8(self.pc +% 1);
            const A: *u8 = &self.registers.r8.A;
            A.* ^= source;

            self.registers.r8.F.Flags.zero = A.* == 0;
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = false;
            self.registers.r8.F.Flags.carry = false;

            break :op Operation{ .deltaPC = 2, .cycles = 8 };
        },
        // LDH a, [imm8]
        0xF0 => op: {
            const source: u8 = mmu.read8(self.pc +% 1);
            self.registers.r8.A = mmu.read8(MemMap.HIGH_PAGE + source);

            break: op Operation { .deltaPC = 2, .cycles = 12 };
        },
        // LDH a, [c]
        0xF2 => op: {
            // TODO: Could we combine some of the high loads/writes with a new high variant? 
            self.registers.r8.A = mmu.read8(MemMap.HIGH_PAGE + self.registers.r8.C);

            break: op Operation { .deltaPC = 1, .cycles = 8 };
        },
        // LD a, [imm16]
        0xFA => op: {
            const source: u16 = mmu.read16(self.pc +% 1);
            self.registers.r8.A = mmu.read8(source);

            break: op Operation { .deltaPC = 3, .cycles = 16 };
        },
        // DI (Disable Interrupts)
        0xF3 => op: {
            self.ime_requested = false;
            self.ime = false;
            break: op Operation { .deltaPC = 1, .cycles =  4 };
        },
        // OR a, imm8
        0xF6 => op: {
            // TODO: For add, adc, sub, sbc, and, xor, or, cp we have basically the same code and instruction.
            const source: u8 = mmu.read8(self.pc +% 1);
            const dest: *u8 = &self.registers.r8.A;
            dest.* |= source;

            self.registers.r8.F.Flags.zero = dest.* == 0;
            self.registers.r8.F.Flags.nBCD = false;
            self.registers.r8.F.Flags.halfBCD = false;
            self.registers.r8.F.Flags.carry = false;

            break :op Operation{ .deltaPC = 2, .cycles = 8 };
        },
        // LD HL, SP+imm8(signed)
        0xF8 => op: {
            const deltaSP: i8 = mmu.readi8(self.pc +% 1); 

            self.registers.r8.F.Flags.zero = false;
            self.registers.r8.F.Flags.nBCD = false;
            _, const halfOverflow = @addWithOverflow(@as(u4, @truncate(self.sp)), @as(u4, @intCast(deltaSP & 0xF)));
            self.registers.r8.F.Flags.halfBCD = halfOverflow == 1;
            _, const carryOverflow = @addWithOverflow(@as(u8, @truncate(self.sp)), @as(u8, @bitCast(deltaSP)));
            self.registers.r8.F.Flags.carry = carryOverflow == 1;

            self.registers.r16.HL = self.sp +% @as(u16, @bitCast(@as(i16, deltaSP)));

            break :op Operation{ .deltaPC = 2, .cycles = 12 };
        },
        // LD SP, HL
        0xF9 => op: {
            self.sp = self.registers.r16.HL;

            break: op Operation { .deltaPC = 1, .cycles = 8 };
        },
        // EI (Enable Interrupts)
        0xFB => op: {
            self.ime_requested = true;
            break: op Operation { .deltaPC = 1, .cycles =  4 };
        },
        // CP a, imm8
        0xFE => op: {
            // TODO: For add, adc, sub, sbc, and, xor, or, cp we have basically the same code and instruction.
            // Difference is only if we use an immediate value or not. Can we make this a better re-use?
            // The difference of the instructions is that the variant is HL + the 2nd bit is set (6th value).
            // So I can change the mask to improve this! Cycle time is the same as HL!
            const source: u8 = mmu.read8(self.pc +% 1);
            const A: *u8 = &self.registers.r8.A;
            const result, const overflow = @subWithOverflow(A.*, source);

            self.registers.r8.F.Flags.zero = result == 0;
            self.registers.r8.F.Flags.nBCD = true;
            self.registers.r8.F.Flags.halfBCD = (((A.* & 0x0F) -% (source & 0x0F)) & 0x10) == 0x10;
            self.registers.r8.F.Flags.carry = overflow == 1;

            break :op Operation{ .deltaPC = 2, .cycles = 8 };
        },
        else => op: {
            std.debug.print("OPERATION_NOT_IMPLEMENTED: {x}\n", .{opcode});
            break: op CPUError.OPERATION_NOT_IMPLEMENTED;
        }
    };

    self.pc +%= operation.deltaPC;
    self.cycles_ahead = operation.cycles;
}
