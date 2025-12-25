const std = @import("std");
const assert = std.debug.assert;

const def = @import("defines.zig");
const Fifo = @import("util/fifo.zig");
const mem_map = @import("mem_map.zig");
// TODO: Try to get rid of mmu dependency. It is currently required to read out IE and IF.
const MMU = @import("mmu.zig");


// TODO: Try to implement interrupt handling differently so that I don't have to pay the size of the largest instruction and the interrupt handler.
// I can reach this when I changed ei and interrupt decoding!
// TODO: This wastes a lost of memory, as the pseudo bank all have to pay the size of the largest.
const longest_instruction_cycles = 24 + 20; // CALL + InterruptHandler
const hram_size = mem_map.hram_high - mem_map.hram_low;

// TODO: Think about how we split this file into multiple files.
// I think having a defines.zig + instruction_set.zig would be best.

// Note: This assumes little-endian
const RegisterFileID = enum(u4) {
    c, b,
    e, d,
    l, h,
    z, w,
    pcl, pch,
    spl, sph,
    ir, dbus,
    f, a,
};

const FlagFileID = enum(u3) {
    // Flags
    carry, half_bcd,
    n_bcd, zero,
    // Pseudo
    temp_lsb, temp_msb,
    const_one, const_zero,
};

const MicroOp = enum(u5) {
    unused,
    // General
    addr_idu, 
    addr_idu_low,
    dbus,
    decode,
    idu_adjust,
    nop,
    // ALU
    alu_adf,
    alu_and, 
    alu_assign, 
    alu_bit,
    alu_ccf, 
    alu_cp, 
    alu_daa_adjust, 
    alu_inc, 
    alu_not,
    alu_or, 
    alu_res, 
    alu_sbf,
    alu_scf, 
    alu_set,
    alu_slf, 
    alu_srf,
    alu_swap, 
    alu_xor, 
    // Misc
    change_ime,
    conditional_check,
    halt,
    set_pc,
    wz_writeback,
};

// TODO: Try to reduce the size of the Param structs
const AddrIduParams = packed struct(u15) {
    addr: RegisterFileID, 
    idu: i2,
    idu_out: RegisterFileID,
    _: u5 = 0, 
};
const IduAdjustParams = packed struct(u15) {
    input: RegisterFileID,
    change_flags: bool,
    _: u10 = 0,
};
const DBusParams = packed struct(u15) {
    source: RegisterFileID,
    target: RegisterFileID,
    _: u7 = 0,
};
// TODO: Consider splitting the Alu params into what we tend to need, to reduce the size of all Params.
const AluParams = packed struct(u15) {
    input_1: RegisterFileID,
    input_2: packed union {
        rfid: RegisterFileID,
        value: u4,
    },
    ffid: FlagFileID,
    output: RegisterFileID,

    pub fn Unpack(registers: *RegisterFile, params: AluParams) struct { u8, u8, u4, u8, *u8 } {
        return .{
            registers.getU8(params.input_1).*,
            registers.getU8(params.input_2.rfid).*,
            params.input_2.value,
            registers.getFlag(params.ffid),
            registers.getU8(params.output),
        };
    }
};
const DecodeParams = packed struct(u15) {
    bank_idx: u2 = opcode_bank_default,
    _: u13 = 0,
};
// TODO: Replace ConditionCheck with FlagFileID?
const ConditionCheck = enum(u3) {
    not_zero,
    zero,
    not_carry,
    carry,
    const_one,
};
const MiscParams = packed struct(u15) {
    write_back: RegisterFileID = .a,
    ime_value: bool = false,
    rst_idx: u4 = 0,
    cc: ConditionCheck = .not_zero,
    _: u3 = 0,
};
const MicroOpData = struct {
    operation: MicroOp,
    params: union(enum) {
        none,
        addr_idu: AddrIduParams,
        idu_adjust: IduAdjustParams,
        dbus: DBusParams,
        alu: AluParams,
        misc: MiscParams,
        decode: DecodeParams,
    },
};
const MicroOpFifo = Fifo.RingbufferFifo(MicroOpData, longest_instruction_cycles);
pub const MicroOpArray = std.ArrayList(MicroOpData);

fn AddrIdu(addr: RegisterFileID, idu: i2, idu_out: RegisterFileID) MicroOpData {
    return .{ .operation = .addr_idu, .params = .{ .addr_idu = AddrIduParams{ .addr = addr, .idu = idu, .idu_out = idu_out } } };
}
fn AddrIduLow(addr: RegisterFileID, idu: i2, idu_out: RegisterFileID) MicroOpData {
    return .{ .operation = .addr_idu_low, .params = .{ .addr_idu = AddrIduParams{ .addr = addr, .idu = idu, .idu_out = idu_out } } };
}
fn IduAdjust(input: RegisterFileID, change_flags: bool) MicroOpData {
    return .{ .operation = .idu_adjust, .params = .{ .idu_adjust = IduAdjustParams{ .input = input, .change_flags = change_flags } } };
}
fn AluFlag(func: MicroOp, input_1: RegisterFileID, input_2: RegisterFileID, ffid: FlagFileID, output: RegisterFileID) MicroOpData {
    return .{ .operation = func, .params = .{ .alu = AluParams{ .input_1 = input_1, .input_2 = .{ .rfid = input_2 }, .ffid = ffid, .output = output } } };
}
fn Alu(func: MicroOp, input_1: RegisterFileID, input_2: RegisterFileID, output: RegisterFileID) MicroOpData {
    return .{ .operation = func, .params = .{ .alu = AluParams{ .input_1 = input_1, .input_2 = .{ .rfid = input_2 }, .ffid = .const_zero, .output = output } } };
}
fn AluValue(func: MicroOp, input_1: RegisterFileID, input_2: u4, output: RegisterFileID) MicroOpData {
    return .{ .operation = func, .params = .{ .alu = AluParams{ .input_1 = input_1, .input_2 = .{ .value = input_2 }, .ffid = .const_zero, .output = output } } };
}
fn AluValueRel(func: MicroOp, input_1: RegisterFileID, input_2: i2, output: RegisterFileID) MicroOpData {
    return .{ .operation = func, .params = .{ .alu = AluParams{ .input_1 = input_1, .input_2 = .{ .value = @bitCast(@as(i4, input_2)) }, .ffid = .const_zero, .output = output } } };
}
fn Dbus(source: RegisterFileID, target: RegisterFileID) MicroOpData {
    return .{ .operation = .dbus, .params = .{ .dbus = DBusParams{ .source = source, .target = target } } };
}
fn Decode(bank_idx: u2) MicroOpData {
    return .{ .operation = .decode, .params = .{ .decode = DecodeParams{ .bank_idx = bank_idx } } };
}
fn MiscWB(rfid: RegisterFileID) MicroOpData {
    return .{ .operation = .wz_writeback, .params = .{ .misc = MiscParams{ .write_back = rfid } } };
}
fn MiscCC(cc: ConditionCheck) MicroOpData {
    return .{ .operation = .conditional_check, .params = .{ .misc = MiscParams{ .cc = cc } } };
}
fn MiscHALT() MicroOpData {
    return .{ .operation = .halt, .params = .{ .misc = MiscParams{} } };
}
fn MiscRST(rst_idx: u4) MicroOpData {
    return .{ .operation = .set_pc, .params = .{ .misc = MiscParams{ .rst_idx = rst_idx } } };
}
fn MiscIME(ime: bool) MicroOpData {
    return .{ .operation = .change_ime, .params = .{ .misc = MiscParams{ .ime_value = ime } } };
}
fn Nop() MicroOpData {
    return .{ .operation = .nop, .params = .none };
}

pub const opcode_bank_default = 0;
pub const opcode_bank_prefix = 1;
// 0x10 = STOP, 0x00-0x04: Interrupt Handler
pub const opcode_bank_pseudo = 2;
pub const num_opcode_banks = 3;
pub const num_opcodes = 256;
fn genOpcodeBanks(alloc: std.mem.Allocator) [num_opcode_banks][num_opcodes]MicroOpArray {
    var returnVal: [num_opcode_banks][num_opcodes]MicroOpArray = undefined;
    @memset(&returnVal, [_]MicroOpArray{.{}} ** num_opcodes);

    const r8_rfids = [_]RegisterFileID{ .b, .c, .d, .e, .h, .l, .dbus, .a };
    const r16_rfids = [_]RegisterFileID{ .c, .e, .l, .spl };
    const r16_stack_rfids = [_]RegisterFileID{ .c, .e, .l, .f };
    // TODO: Can we combine them? Can we use cond_cc_jump for the oother cond_cc?
    const cond_cc = [_]ConditionCheck{ .not_zero, .zero, .not_carry, .carry };
    const cond_cc_one = [_]ConditionCheck{ .not_zero, .zero, .not_carry, .carry, .const_one };
    
    // TODO: Right now some instruction use a different order than the default.
    // Could I find a order that fits all the cases cleanly?
    // Default order:
    // 0: ADDR + IDU 
    // 1: DBUS + Push Pins
    // 2: ALU/MISC + Apply Pins
    // 3: DECODE
    // TODO: Maybe AddrIdu -> ALU/Misc -> Dbus -> Decode should be the default?

    //
    // DEFAULT BANK:
    //

    // NOP
    returnVal[opcode_bank_default][0x00].appendSlice(alloc, &[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD r16, imm16
    const ld_r16_imm_opcodes = [_]u8{ 0x01, 0x11, 0x21, 0x31 };
    for (ld_r16_imm_opcodes, r16_rfids) |opcode, rfid| {
        returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z),  Nop(),  Nop(),
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .w),  Nop(),  Nop(),
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), MiscWB(rfid), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // LD r16mem, a
    const ld_r16mem_a_opcodes = [_]u8{ 0x02, 0x12, 0x22, 0x32 };
    const ld_r16mem_a_idu = [_]i2{ 0, 0, 1, -1 }; 
    const ld_r16mem_a_rfids = [_]RegisterFileID{ .c, .e, .l, .l };
    for(ld_r16mem_a_opcodes, ld_r16mem_a_rfids, ld_r16mem_a_idu) |opcode, rfid, idu| {
        returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
            AddrIdu(rfid, idu, rfid), Dbus(.a, .dbus),  Nop(),                  Nop(),
            AddrIdu(.pcl, 1, .pcl),   Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // INC r16, DEC r16
    const inc_dec_r16_delta = [2]i2{ 1, -1 };
    const inc_dec_r16_opcodes = [2][r16_rfids.len]u8{
        [_]u8{ 0x03, 0x13, 0x23, 0x33 }, [_]u8{ 0x0B, 0x1B, 0x2B, 0x3B },
    };
    for(inc_dec_r16_opcodes, inc_dec_r16_delta) |opcodes, delta| {
        for(opcodes, r16_rfids) |opcode, rfid| {
            returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
                AddrIdu(rfid, delta, rfid), Nop(),            Nop(), Nop(),
                AddrIdu(.pcl, 1, .pcl),     Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
            }) catch unreachable;
        }
    }

    // INC r8, DEC r8
    const inc_dec_r8_delta = [2]i2{ 1, -1 };
    const inc_dec_r8_opcodes = [2][r8_rfids.len]u8{ 
        [_]u8{ 0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34, 0x3C }, [_]u8{ 0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D } 
    };
    for(inc_dec_r8_opcodes, inc_dec_r8_delta) |opcodes, delta| {
        for(opcodes, r8_rfids) |opcode, rfid| {
            if(rfid == .dbus) {
                returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
                    AddrIdu(.l, 0, .l), Dbus(.dbus, .z), Nop(), Nop(),
                    // TODO: Why does this not follow the default microop order?
                    AddrIdu(.l, 0, .l), AluValueRel(.alu_inc, .z, delta, .z), Dbus(.z, .dbus), Nop(),
                    AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
                }) catch unreachable;
            } else {
                returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
                    AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), AluValueRel(.alu_inc, rfid, delta, rfid), Decode(opcode_bank_default),
                }) catch unreachable;
            }
        }
    }

    // LD r8, imm8
    const ld_r8_imm8_opcodes = [_]u8{ 0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E };
    for(ld_r8_imm8_opcodes, r8_rfids) |opcode, rfid| {
        if(rfid == .dbus) {
            returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
                AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z),  Nop(), Nop(),
                AddrIdu(.l, 0, .l), Dbus(.z, .dbus), Nop(), Nop(),
                AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
            }) catch unreachable;
        } else {
            returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
                AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z),  Nop(),                    Nop(),
                AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Alu(.alu_assign, .z, .z, rfid), Decode(opcode_bank_default),
            }) catch unreachable;
        }
    }

    // RLCA, RRCA, RLA, RRA
    const rotate_opcodes = [_]u8{ 0x07, 0x0F, 0x17, 0x1F };
    const rotate_uops = [_]MicroOp{ .alu_slf, .alu_srf, .alu_slf, .alu_srf };
    const rotate_flags = [_]FlagFileID{ .temp_msb, .temp_lsb, .carry, .carry };
    for(rotate_opcodes, rotate_uops, rotate_flags) |opcode, uop, flag| {
        returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), AluFlag(uop, .a, .b, flag, .a), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // LD (imm16),SP
    returnVal[opcode_bank_default][0x08].appendSlice(alloc, &[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z),   Nop(), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .w),   Nop(), Nop(),
        AddrIdu(.z, 1, .z),   Dbus(.spl, .dbus), Nop(), Nop(),
        AddrIdu(.z, 0, .z),   Dbus(.sph, .dbus), Nop(), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir),  Nop(), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD a, r16mem
    const ld_a_r16mem_opcodes = [_]u8{ 0x0A, 0x1A, 0x2A, 0x3A };
    const ld_a_r16mem_rfids = [_]RegisterFileID{ .c, .e, .l, .l };
    const ld_a_r16mem_idu = [_]i2{ 0, 0, 1, -1 };
    for(ld_a_r16mem_opcodes, ld_a_r16mem_rfids, ld_a_r16mem_idu) |opcode, rfid, idu| {
        returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
            AddrIdu(rfid, idu, rfid), Dbus(.dbus, .z),   Nop(),               Nop(),
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir),  Alu(.alu_assign, .z, .z, .a), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // ADD HL, R16
    const add_hl_r16_opcodes = [_]u8{ 0x09, 0x19, 0x29, 0x39 };
    for(add_hl_r16_opcodes, r16_rfids) |opcode, rfid| {
        const r16_msb: RegisterFileID = @enumFromInt((@intFromEnum(rfid) + 1));
        returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
            Nop(), Nop(), AluFlag(.alu_adf, .l, rfid, .const_zero, .l), Nop(),
            AddrIdu(.pcl, 1, .pcl),   Dbus(.dbus, .ir), AluFlag(.alu_adf, .h, r16_msb, .carry, .h), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // STOP
    returnVal[opcode_bank_default][0x10].appendSlice(alloc, &[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl), Nop(), Nop(), Decode(opcode_bank_pseudo),
    }) catch unreachable;

    // JR imm8, JR cond imm8
    const jr_opcodes = [_]u8{ 0x20, 0x28, 0x30, 0x38, 0x18 };
    for(jr_opcodes, cond_cc_one) |opcode, cc| {
        returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z), MiscCC(cc), Nop(),
            IduAdjust(.pcl, false), Nop(), Nop(), Nop(),
            AddrIdu(.z, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // DAA, CPL, SCF, CCF
    const misc_opcodes = [_]u8{ 0x27, 0x2F, 0x37, 0x3F };
    const misc_uops = [_]MicroOp{ .alu_daa_adjust, .alu_not, .alu_scf, .alu_ccf };
    for(misc_opcodes, misc_uops) |opcode, uop| {
        returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Alu(uop, .a, .a, .a), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // LD r8, r8
    var ld_r8_r8_opcode: u8 = 0x40;
    for(r8_rfids) |target_rfid| {
        for (r8_rfids) |source_rfid| {
            if(source_rfid == .dbus and target_rfid == .dbus) { // HALT
                returnVal[opcode_bank_default][ld_r8_r8_opcode].appendSlice(alloc, &[_]MicroOpData{
                    AddrIdu(.pcl, 0, .pcl), Dbus(.dbus, .ir), MiscHALT(), Decode(opcode_bank_default),
                }) catch unreachable;
            } else if (source_rfid == .dbus) {
                returnVal[opcode_bank_default][ld_r8_r8_opcode].appendSlice(alloc, &[_]MicroOpData{
                    AddrIdu(.l, 0, .l), Dbus(.dbus, .z), Nop(), Nop(),
                    AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Alu(.alu_assign, .z, .z, target_rfid), Decode(opcode_bank_default),
                }) catch unreachable;
            } else if (target_rfid == .dbus) {
                returnVal[opcode_bank_default][ld_r8_r8_opcode].appendSlice(alloc, &[_]MicroOpData{
                    AddrIdu(.l, 0, .l), Dbus(source_rfid, .dbus), Nop(), Nop(),
                    AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
                }) catch unreachable;
            }
            else {
                returnVal[opcode_bank_default][ld_r8_r8_opcode].appendSlice(alloc, &[_]MicroOpData{
                    AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Alu(.alu_assign, source_rfid, source_rfid, target_rfid), Decode(opcode_bank_default),
                }) catch unreachable;
            }
            ld_r8_r8_opcode += 1;
        }
    }

    // ADD a r8, ADC a r8, SUB a r8, SBC a r8
    const arithmetic_r8_opcodes = [4][r8_rfids.len]u8{
        [_]u8{ 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87 }, [_]u8{ 0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E, 0x8F },
        [_]u8{ 0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97 }, [_]u8{ 0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F },
    };
    const arithmetic_r8_uops = [4]MicroOp{ .alu_adf, .alu_adf, .alu_sbf, .alu_sbf };
    const arithmetic_r8_flags = [4]FlagFileID{ .const_zero, .carry, .const_zero, .carry };
    for(arithmetic_r8_opcodes, arithmetic_r8_uops, arithmetic_r8_flags) |opcodes, uop, flag| {
        for(opcodes, r8_rfids) |opcode, rfid| {
            if(rfid == .dbus) {
                returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
                    AddrIdu(.l, 0, .l), Dbus(.dbus, .z), Nop(), Nop(),
                    AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), AluFlag(uop, .a, .z, flag, .a), Decode(opcode_bank_default),
                }) catch unreachable;
            } else {
                returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
                    AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), AluFlag(uop, .a, rfid, flag, .a), Decode(opcode_bank_default),
                }) catch unreachable;
            }
        }
    }

    // AND a r8, XOR a r8, OR a r8, CP a r8
    const logic_r8_opcodes = [4][r8_rfids.len]u8{
        [_]u8{ 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7 }, [_]u8{ 0xA8, 0xA9, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF },
        [_]u8{ 0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7 }, [_]u8{ 0xB8, 0xB9, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF },
    };
    const logic_r8_uops = [4]MicroOp{ .alu_and, .alu_xor, .alu_or, .alu_cp };
    for(logic_r8_opcodes, logic_r8_uops) |opcodes, uop| {
        for(opcodes, r8_rfids) |opcode, rfid| {
            if(rfid == .dbus) {
                returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
                    AddrIdu(.l, 0, .l), Dbus(.dbus, .z), Nop(), Nop(),
                    AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Alu(uop, .a, .z, .a), Decode(opcode_bank_default),
                }) catch unreachable;
            } else {
                returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
                    AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Alu(uop, .a, rfid, .a), Decode(opcode_bank_default),
                }) catch unreachable;
            }
        }
    }

    // RET cond
    // TODO: RET and RET cond are mostly the same, but RET cond has one Mcycle more, can we still combine them?
    const ret_cond_opcodes = [_]u8{ 0xC0, 0xC8, 0xD0, 0xD8 };
    for(ret_cond_opcodes, cond_cc) |opcode, cc| {
        returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
            Nop(), Nop(), MiscCC(cc), Nop(),
            AddrIdu(.spl, 1, .spl), Dbus(.dbus, .z), Nop(), Nop(),
            AddrIdu(.spl, 1, .spl), Dbus(.dbus, .w), Nop(), Nop(),
            Nop(), Nop(), MiscWB(.pcl), Nop(),
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // POP r16stk
    const pop_rr_opcodes = [_]u8{ 0xC1, 0xD1, 0xE1, 0xF1 };
    for(pop_rr_opcodes, r16_stack_rfids) |opcode, rfid| {
        returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
            AddrIdu(.spl, 1, .spl), Dbus(.dbus, .z), Nop(), Nop(),
            AddrIdu(.spl, 1, .spl), Dbus(.dbus, .w), Nop(), Nop(),
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), MiscWB(rfid), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // JP cond imm16, JP imm16
    const jp_opcodes = [_]u8{ 0xC2, 0xCA, 0xD2, 0xDA, 0xC3 };
    for(jp_opcodes, cond_cc_one) |opcode, cc| {
        returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z), Nop(), Nop(),
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .w), MiscCC(cc), Nop(),
            Nop(), Nop(), MiscWB(.pcl), Nop(),
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // PUSH r16stk
    const push_rr_opcodes = [_]u8{ 0xC5, 0xD5, 0xE5, 0xF5 };
    for(push_rr_opcodes, r16_stack_rfids) |opcode, rfid| {
        const msb_rfid: RegisterFileID = @enumFromInt(@intFromEnum(rfid) + 1);
        returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
            AddrIdu(.spl, -1, .spl), Nop(), Nop(), Nop(),
            AddrIdu(.spl, -1, .spl), Dbus(msb_rfid, .dbus), Nop(), Nop(),
            AddrIdu(.spl, 0, .spl), Dbus(rfid, .dbus), Nop(), Nop(),
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // CALL cond imm16, CALL imm16
    const call_opcodes = [_]u8{ 0xC4, 0xCC, 0xD4, 0xDC, 0xCD };
    for(call_opcodes, cond_cc_one) |opcodes, cc| {
        returnVal[opcode_bank_default][opcodes].appendSlice(alloc, &[_]MicroOpData{
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z), Nop(), Nop(),
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .w), MiscCC(cc), Nop(),
            AddrIdu(.spl, -1, .spl), Nop(), Nop(), Nop(),
            AddrIdu(.spl, -1, .spl), Dbus(.pch, .dbus), Nop(), Nop(),
            AddrIdu(.spl, 0, .spl), Dbus(.pcl, .dbus), MiscWB(.pcl), Nop(),
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // ADD a imm8, ADC a imm8, SUB a imm8, SBC a imm8
    const arithmetic_imm8_opcodes = [_]u8{ 0xC6, 0xCE, 0xD6, 0xDE };
    const arithmetic_imm8_uops = [_]MicroOp{ .alu_adf, .alu_adf, .alu_sbf, .alu_sbf };
    const arithmetic_imm8_flags = [_]FlagFileID{ .const_zero, .carry, .const_zero, .carry };
    for(arithmetic_imm8_opcodes, arithmetic_imm8_uops, arithmetic_imm8_flags) |opcode, uop, flag| {
        returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z), Nop(), Nop(),
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), AluFlag(uop, .a, .z, flag, .a), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // RST target
    const rst_opcodes = [_]u8{ 0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF };
    const rst_idx = [_]u4{ 0, 1, 2, 3, 4, 5, 6, 7 };
    for(rst_opcodes, rst_idx) |opcodes, idx| {
        returnVal[opcode_bank_default][opcodes].appendSlice(alloc, &[_]MicroOpData{
            AddrIdu(.spl, -1, .spl), Nop(), Nop(), Nop(),
            AddrIdu(.spl, -1, .spl), Dbus(.pch, .dbus), Nop(), Nop(),
            AddrIdu(.spl, 0, .spl), Dbus(.pcl, .dbus), MiscRST(idx), Nop(),
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // RET
    returnVal[opcode_bank_default][0xC9].appendSlice(alloc, &[_]MicroOpData{
        AddrIdu(.spl, 1, .spl), Dbus(.dbus, .z), Nop(), Nop(),
        AddrIdu(.spl, 1, .spl), Dbus(.dbus, .w), Nop(), Nop(),
        Nop(), Nop(), MiscWB(.pcl), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
    }) catch unreachable;

    // Prefix
    returnVal[opcode_bank_default][0xCB].appendSlice(alloc, &[_]MicroOpData{ // prefix
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_prefix),
    }) catch unreachable;

    // RETI
    // TODO: RET and RETI differ only in the MiscIME() call. If we can set the IME to itself
    returnVal[opcode_bank_default][0xD9].appendSlice(alloc, &[_]MicroOpData{
        AddrIdu(.spl, 1, .spl), Dbus(.dbus, .z), Nop(), Nop(),
        AddrIdu(.spl, 1, .spl), Dbus(.dbus, .w), Nop(), Nop(),
        Nop(), Nop(), MiscWB(.pcl), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), MiscIME(true), Decode(opcode_bank_default),
    }) catch unreachable;

    // LDH [imm8], a
    returnVal[opcode_bank_default][0xE0].appendSlice(alloc, &[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z), Nop(), Nop(),
        AddrIduLow(.z, 0, .z), Dbus(.a, .dbus), Nop(), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
    }) catch unreachable;

    // LDH [c], a
    returnVal[opcode_bank_default][0xE2].appendSlice(alloc, &[_]MicroOpData{
        AddrIduLow(.c, 0, .c), Dbus(.a, .dbus), Nop(), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
    }) catch unreachable;

    // AND a imm8, XOR a imm8, OR a imm8, CP a imm8
    const logic_imm8_opcodes = [_]u8{ 0xE6, 0xEE, 0xF6, 0xFE };
    const logic_imm8_uops = [_]MicroOp{ .alu_and, .alu_xor, .alu_or, .alu_cp };
    for(logic_imm8_opcodes, logic_imm8_uops) |opcode, uop| {
        returnVal[opcode_bank_default][opcode].appendSlice(alloc, &[_]MicroOpData{
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z), Nop(), Nop(),
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Alu(uop, .a, .z, .a), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // ADD SP, imm8 (signed)
    returnVal[opcode_bank_default][0xE8].appendSlice(alloc, &[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z), Nop(), Nop(),
        // Note: Using IduAdjust + WZ-Writebak differs from the definition from gekkio. They use a special adjust add.
        IduAdjust(.spl, true), Nop(), Nop(), Nop(),
        Nop(), Nop(), Nop(), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), MiscWB(.spl), Decode(opcode_bank_default),
    }) catch unreachable;

    // JP HL
    returnVal[opcode_bank_default][0xE9].appendSlice(alloc, &[_]MicroOpData{
        AddrIdu(.l, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD [imm16], a
    returnVal[opcode_bank_default][0xEA].appendSlice(alloc, &[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z), Nop(), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .w), Nop(), Nop(),
        AddrIdu(.z, 0, .z), Dbus(.a, .dbus), Nop(), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
    }) catch unreachable;

    // LDH a, [imm8]
    returnVal[opcode_bank_default][0xF0].appendSlice(alloc, &[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z), Nop(), Nop(),
        AddrIduLow(.z, 0, .z), Dbus(.dbus, .z), Nop(), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Alu(.alu_assign, .z, .z, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // LDH a, [c]
    returnVal[opcode_bank_default][0xF2].appendSlice(alloc, &[_]MicroOpData{
        AddrIduLow(.c, 0, .c), Dbus(.dbus, .z), Nop(), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Alu(.alu_assign, .z, .z, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD a, [imm16]
    returnVal[opcode_bank_default][0xFA].appendSlice(alloc, &[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z), Nop(), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .w), Nop(), Nop(),
        AddrIdu(.z, 0, .z), Dbus(.dbus, .z), Nop(), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Alu(.alu_assign, .z, .z, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // DI (Disable Interrupts)
    returnVal[opcode_bank_default][0xF3].appendSlice(alloc, &[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), MiscIME(false), Decode(opcode_bank_default),
    }) catch unreachable;

    // EI (Enable Interrupts)
    returnVal[opcode_bank_default][0xFB].appendSlice(alloc, &[_]MicroOpData{
        // Note: switching MiscIME with Decode allowes the effect of the EI instruction to be delayed by one instruction.
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Decode(opcode_bank_default), MiscIME(true),
    }) catch unreachable;

    // LD HL, SP+imm8(signed)
    returnVal[opcode_bank_default][0xF8].appendSlice(alloc, &[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .z), Nop(), Nop(),
        // Note: Using IduAdjust + WZ-Writebak differs from the definition from gekkio. They use a special adjust add.
        IduAdjust(.spl, true), Nop(), MiscWB(.l), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD SP, HL
    returnVal[opcode_bank_default][0xF9].appendSlice(alloc, &[_]MicroOpData{
        AddrIdu(.l, 0, .spl), Dbus(.dbus, .z), Nop(), Nop(),
        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
    }) catch unreachable;

    //
    // PREFIX BANK:
    //

    const bit_shift_flags = [_]FlagFileID{ .temp_msb, .temp_lsb, .carry,   .carry,   .const_zero, .temp_msb,    .temp_msb, .const_zero };
    const bit_shift_uops = [_]MicroOp{     .alu_slf,  .alu_srf,  .alu_slf, .alu_srf, .alu_slf,     .alu_srf,     .alu_swap, .alu_srf }; 
    var bit_shift_opcode: u8 = 0x00;
    for(bit_shift_uops, bit_shift_flags) |bit_shift_uop, flag| {
        for(r8_rfids) |rfid| {
            if(rfid == .dbus) {
                returnVal[opcode_bank_prefix][bit_shift_opcode].appendSlice(alloc, &[_]MicroOpData{
                    AddrIdu(.l, 0, .l), Dbus(.dbus, .z), Nop(), Nop(),
                    // TODO: Why does this not follow the default microop order?
                    AddrIdu(.l, 0, .l), AluFlag(bit_shift_uop, .z, .z, flag, .z), Dbus(.z, .dbus), Nop(),
                    AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
                }) catch unreachable;
            } else {
                returnVal[opcode_bank_prefix][bit_shift_opcode].appendSlice(alloc, &[_]MicroOpData{
                    AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), AluFlag(bit_shift_uop, rfid, rfid, flag, rfid), Decode(opcode_bank_default),
                }) catch unreachable;
            }
            bit_shift_opcode += 1;
        }
    }

    const bit_uops = [_]MicroOp{ .alu_bit, .alu_res, .alu_set };  
    const bit_opcodes = [_]u8{ 0x40, 0x80, 0xC0 };
    for(bit_uops, 0..) |bit_uop, i| {
        var bit_opcode: u8 = bit_opcodes[i];
        for(0..8) |bit_index| {
            for(r8_rfids) |rfid| {
                if(rfid == .dbus) {
                    // TODO: Strange that only the bit dbus version is shorter then the rest of the bit uops.
                    // According to the opcode tables all of them should be shorter.
                    if(bit_uop == .alu_bit) {
                        returnVal[opcode_bank_prefix][bit_opcode].appendSlice(alloc, &[_]MicroOpData{
                            AddrIdu(.l, 0, .l), Dbus(.dbus, .z), Nop(), Nop(),
                            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), AluValue(bit_uop, .z, @intCast(bit_index), .z), Decode(opcode_bank_default),
                        }) catch unreachable;
                    }
                    else {
                        returnVal[opcode_bank_prefix][bit_opcode].appendSlice(alloc, &[_]MicroOpData{
                            AddrIdu(.l, 0, .l), Dbus(.dbus, .z), Nop(), Nop(),
                            // TODO: Why does this not follow the default microop order?
                            AddrIdu(.l, 0, .l), AluValue(bit_uop, .z, @intCast(bit_index), .z), Dbus(.z, .dbus), Nop(),
                            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
                        }) catch unreachable;
                    }
                } else {
                    returnVal[opcode_bank_prefix][bit_opcode].appendSlice(alloc, &[_]MicroOpData{
                        AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), AluValue(bit_uop, rfid, @intCast(bit_index), rfid), Decode(opcode_bank_default),
                    }) catch unreachable;
                }
                bit_opcode +%= 1;
            }
        }
    }

    //
    // PSEUDO BANK:
    //

    // INTERRUPT
    const interrupt_idx = [_]u4{ 8, 9, 10, 11, 12 };
    const interrupt_opcodes = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04 };
    for(interrupt_opcodes, interrupt_idx) |opcode, idx| {
        returnVal[opcode_bank_pseudo][opcode].appendSlice(alloc, &[_]MicroOpData{
            Nop(), Nop(), Nop(), Nop(),
            AddrIdu(.spl, -1, .spl), Nop(), Nop(), Nop(),
            AddrIdu(.spl, -1, .spl), Dbus(.pch, .dbus), MiscIME(false), Nop(),
            AddrIdu(.spl, 0, .spl), Dbus(.pcl, .dbus), MiscRST(idx), Nop(),
            AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // TODO: Placeholder: Need an actual implementation for STOP.
    // STOP
    returnVal[opcode_bank_pseudo][0x10].appendSlice(alloc, &[_]MicroOpData{
        Nop(), Nop(), Nop(), Decode(opcode_bank_pseudo),
    }) catch unreachable;

    return returnVal;

}
pub var opcode_banks: [num_opcode_banks][num_opcodes]MicroOpArray = undefined;

// TODO: Do we actually need/want this? Should this be in def?
// IF and IE flags.
const InterruptFlags = packed struct(u8) {
    // priority: highest to lowest.
    v_blank: bool = false,
    lcd_stat: bool = false,
    timer: bool = false,
    serial: bool = false,
    joypad: bool = false,
    _: u3 = 0,

    const Self = @This();
    pub fn fromMem(memory: *[def.addr_space]u8) Self {
        return @bitCast(memory[mem_map.interrupt_flag]);
    } 
    pub fn toMem(self: Self, memory: *[def.addr_space]u8) void {
        memory[mem_map.interrupt_flag] = @bitCast(self);
    }
};

pub const FlagRegister = packed struct(u8) {
    _: u4 = 0,
    carry: u1 = 0,
    half_bcd: u1 = 0,
    n_bcd: u1 = 0,
    zero: u1 = 0,
};
const PseudoFlagRegister = packed struct(u8) {
    temp_lsb: u1 = 0,
    temp_msb: u1 = 0,
    const_one: u1 = 1,
    const_zero: u1 = 0,
    _: u4 = 0,
};
const RegisterFile = packed union {
    r16: packed struct {
        bc: u16 = 0,
        de: u16 = 0,
        hl: u16 = 0,
        wz: u16 = 0,
        pc: u16 = 0,
        sp: u16 = 0,
        ir_dbus: u16 = 0,
        af: u16 = 0,
        pu: u16 = 0,
    },
    // Note: gb and x86 are little-endian
    r8: packed struct {
        c: u8 = 0, b: u8 = 0,
        e: u8 = 0, d: u8 = 0,
        l: u8 = 0, h: u8 = 0,
        z: u8 = 0, w: u8 = 0,
        pcl: u8 = 0, pch: u8 = 0,
        spl: u8 = 0, sph: u8 = 0,
        ir: u8 = 0, dbus: u8 = 0,
        f: FlagRegister = .{}, a: u8 = 0,
        // p = Pseudo, u = unused
        p: PseudoFlagRegister = .{}, u: u8 = 0,
    },

    const Self = @This();
    pub fn getU8(self: *Self, rfid: RegisterFileID) *u8 {
        const index: u4 = @intFromEnum(rfid); 
        const base: [*]u8 = @alignCast(@ptrCast(self));
        return @ptrCast(base + index);
    } 
    pub fn getU16(self: *Self, rfid: RegisterFileID) *u16 {
        const index: u4 = @intFromEnum(rfid); 
        assert(index % 2 == 0); // requires aligned rfid.
        const index_u16: u4 = index / 2;
        const base: [*]u16 = @alignCast(@ptrCast(self));
        return @ptrCast(base + index_u16);
    } 
    pub fn getFlag(self: *Self, ffid: FlagFileID) u1 {
        // Note: This only works for the specific memory layout above (bytes and bits).
        // Flag followed by A followed by Pseudoflag. And the specific order of the bits.
        const ffid_idx: u5 = @intFromEnum(ffid);
        const base_index: u5 = ffid_idx + 4; 
        const offset: u5 = base_index + (8 * (base_index / 8));
        const base: *align(1) u32 = @alignCast(@ptrCast(&self.r8.f));
        return @truncate(base.* >> offset);
    }
};

pub const State = struct {
    hram: [hram_size]u8 = undefined,
    interrupt_enable: u8 = 0,

    uop_fifo: MicroOpFifo = .{}, 

    registers: RegisterFile = .{ .r8 = .{} },
    address_bus: u16 = 0,

    interrupt_master_enable: bool = false,

    // Differentiate the behaviour of halt when it is first encountered vs repeated hits (cpu is halted).
    halt_again: bool = false,
};

pub fn init(state: *State, alloc: std.mem.Allocator) void {
    opcode_banks = genOpcodeBanks(alloc);

    const opcode_bank = opcode_banks[opcode_bank_default];
    const uops: MicroOpArray = opcode_bank[state.registers.r8.ir];
    state.uop_fifo.write(uops.items);

    state.hram = [_]u8{ 0 } ** hram_size;
    state.interrupt_enable = 0;
}

pub fn deinit(_: *State, alloc: std.mem.Allocator) void {
    for(&opcode_banks) |*bank| {
        for(bank) |*instruction| {
            instruction.deinit(alloc);
        }
    }
}

pub fn cycle(state: *State, mmu: *MMU.State) def.Bus {
    var bus: def.Bus = .{}; 
    const flags = state.registers.r8.f;
    const uop: MicroOpData = state.uop_fifo.readItem().?;
    switch(uop.operation) {
        .addr_idu => {
            const params: AddrIduParams = uop.params.addr_idu;
            const addr: u16 = state.registers.getU16(params.addr).*;
            state.address_bus = addr;
            const output: *u16 = state.registers.getU16(params.idu_out);
            // +% -1 <=> +% 65535
            const idu_factor: u16 = @bitCast(@as(i16, params.idu));
            output.* = addr +% idu_factor;
        },
        .addr_idu_low => {
            const params: AddrIduParams = uop.params.addr_idu;
            const input: u8 = state.registers.getU8(params.addr).*;
            const addr: u16 = 0xFF00 + @as(u16, input);
            state.address_bus = addr;
            const output: *u8 = state.registers.getU8(params.idu_out);
            // +% -1 <=> +% 255
            const idu_factor: u8 = @bitCast(@as(i8, params.idu));
            output.* = input +% idu_factor;
        },
        .alu_adf => {
            const input_1, const input_2, _, const flag, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            const input_flag, const flag_overflow = @addWithOverflow(input_1, flag);
            const result, const overflow = @addWithOverflow(input_2, input_flag);
            output.* = result;

            const half_bcd: u1 = @truncate(((input_1 & 0xF) + (input_2 & 0xF) + flag) >> 4);
            // TODO: Super hacky. ADD HL, r16 does not change the zero flag, but all other kinds of ADD instructions do.
            const zero: u1 = if(uop.params.alu.output == .a) @intFromBool(result == 0) else flags.zero;
            state.registers.r8.f = .{ .carry = flag_overflow | overflow, .half_bcd = half_bcd, .n_bcd = 0, .zero = zero};
        },
        .alu_and => {
            const input_1, const input_2, _, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            output.* = input_1 & input_2;
            
            state.registers.r8.f = .{ .carry = 0, .half_bcd = 1, .n_bcd = 0, .zero = @intFromBool(output.* == 0) };
        },
        .alu_assign => {
            const input_1, _, _, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            output.* = input_1;
        },
        .alu_bit => {
            const input_1, _, const input_2, _, _ = AluParams.Unpack(&state.registers, uop.params.alu);
            const result: u8 = input_1 & (@as(u8, 1) << @as(u3, @intCast(input_2)));

            state.registers.r8.f = .{ .carry = flags.carry, .half_bcd = 1, .n_bcd = 0, .zero = @intFromBool(result == 0) };
        },
        .alu_ccf => {
            state.registers.r8.f = .{ .carry = ~flags.carry, .half_bcd = 0, .n_bcd = 0, .zero = flags.zero };
        },
        .alu_cp => {
            const input_1, const input_2, _, _, _ = AluParams.Unpack(&state.registers, uop.params.alu);
            const result, const overflow = @subWithOverflow(input_1, input_2);

            const half_bcd: u1 = @truncate(((input_1 & 0xF) -% (input_2 & 0xF)) >> 4);
            state.registers.r8.f = .{ .carry = overflow, .half_bcd = half_bcd, .n_bcd = 1, .zero = @intFromBool(result == 0) };
        },
        .alu_daa_adjust => {
            const input_1, _, _, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            const low: u1 = ~flags.n_bcd & @intFromBool((input_1 & 0xF) > 0x09) | flags.half_bcd;
            const high: u1 = ~flags.n_bcd & @intFromBool(input_1 > 0x99) | flags.carry;
            const offset: u8 = 0x06 * @as(u8, low) + 0x60 * @as(u8, high);
            const result = if (flags.n_bcd == 1) input_1 -% offset else input_1 +% offset;
            output.* = result;

            state.registers.r8.f = .{ .carry = high, .half_bcd = 0, .n_bcd = flags.n_bcd, .zero = @intFromBool(result == 0) };
        },
        .alu_inc => {
            const input_1, _, const input_2, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            // TODO: This works but it is a type unsafe to cast a i2 to u4 and back.
            const factor: i2 = @bitCast(@as(u2, @truncate(input_2)));
            // +% -1 <=> +% 255
            const factor_inc: u8 = @bitCast(@as(i8, factor));
            output.* = input_1 +% factor_inc;

            const half_bcd: u1 = @truncate(((input_1 & 0xF) +% factor_inc) >> 4);
            const n_bcd: u1 = if(factor < 0) 1 else 0;
            state.registers.r8.f = .{ .carry = flags.carry, .half_bcd = half_bcd, .n_bcd = n_bcd, .zero = @intFromBool(output.* == 0) };
        },
        .alu_not => {
            const input_1, _, _, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            output.* = ~input_1;

            state.registers.r8.f = .{ .carry = flags.carry, .half_bcd = 1, .n_bcd = 1, .zero = flags.zero };
        },
        .alu_or => {
            const input_1, const input_2, _, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            output.* = input_1 | input_2;

            state.registers.r8.f = .{ .carry = 0, .half_bcd = 0, .n_bcd = 0, .zero = @intFromBool(output.* == 0) };
        }, 
        .alu_res => {
            const input_1, _, const input_2, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            const mask: u8 = @as(u8, 1) << @as(u3, @intCast(input_2));
            const result: u8 = input_1 & ~mask;
            output.* = result;
        }, 
        .alu_sbf => {
            const input_1, const input_2, _, const flag, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            const input_flag, const flag_overflow = @addWithOverflow(input_2, flag);
            const result, const overflow = @subWithOverflow(input_1, input_flag);
            output.* = result;

            const half_bcd: u1 = @truncate(((input_1 & 0xF) -% (input_2 & 0xF) -% flag) >> 4);
            state.registers.r8.f = .{ .carry = flag_overflow | overflow, .half_bcd = half_bcd, .n_bcd = 1, .zero = @intFromBool(result == 0) };
        },
        .alu_scf => {
            state.registers.r8.f = .{ .carry = 1, .half_bcd = 0, .n_bcd = 0, .zero = flags.zero };
        },
        .alu_set => {
            const input_1, _, const input_2, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            const mask: u8 = @as(u8, 1) << @as(u3, @intCast(input_2));
            const result: u8 = input_1 | mask;
            output.* = result;
        },
        .alu_slf => {
            const input_1, _, _, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            var result, const shifted_bit = @shlWithOverflow(input_1, 1);
            state.registers.r8.p.temp_msb = shifted_bit;
            const flag: u8 = state.registers.getFlag(uop.params.alu.ffid);
            result |= flag;
            output.* = result;

            // TODO: Workaround to not set the flag values for rlca. Need a better flag system.
            const zero: u1 = if(uop.params.alu.input_1 == uop.params.alu.input_2.rfid) @intFromBool(result == 0) else 0;
            state.registers.r8.f = .{ .carry = shifted_bit, .half_bcd = 0, .n_bcd = 0, .zero = zero };
        },
        .alu_srf => {
            const input_1, _, _, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            const lsb: u1 = @truncate(input_1); 
            const msb: u1 = @intCast(input_1 >> 7);
            state.registers.r8.p.temp_lsb = lsb;
            state.registers.r8.p.temp_msb = msb;
            const flag: u8 = state.registers.getFlag(uop.params.alu.ffid);
            const result: u8 = (input_1 >> 1) | (flag << 7);
            output.* = result;

            // TODO: Workaround to not set the flag values for rra. Need a better flag system.
            const zero: u1 = if(uop.params.alu.input_1 == uop.params.alu.input_2.rfid) @intFromBool(result == 0) else 0;
            state.registers.r8.f = .{ .carry = lsb, .half_bcd = 0, .n_bcd = 0, .zero = zero };
        },
        .alu_swap => {
            const input_1, _, _, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            const result = (input_1 << 4) | (input_1 >> 4);
            output.* = result;

            state.registers.r8.f = .{ .carry = 0, .half_bcd = 0, .n_bcd = 0, .zero = @intFromBool(result == 0) };
        },
        .alu_xor => {
            const input_1, const input_2, _, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            output.* = input_1 ^ input_2;

            state.registers.r8.f = .{ .carry = 0, .half_bcd = 0, .n_bcd = 0, .zero = @intFromBool(output.* == 0) };
        },
        .change_ime => {
            state.interrupt_master_enable = uop.params.misc.ime_value;
        },
        .conditional_check => {
            const params: MiscParams = uop.params.misc;
            const cc = params.cc;
            const flag: u1 = switch(cc) {
                .not_zero => ~state.registers.r8.f.zero,
                .zero => state.registers.r8.f.zero,
                .not_carry => ~state.registers.r8.f.carry,
                .carry => state.registers.r8.f.carry,
                .const_one => state.registers.r8.p.const_one,
            };

            if(flag == 0) { // Load next instruction
                assert((state.uop_fifo.length() % 4) == 1); // We assume that conditional_check uop is followed by another uop inside of this mcycle (Decode step).
                state.uop_fifo.clear();
                state.uop_fifo.write(&[_]MicroOpData{
                    Nop(),
                    AddrIdu(.pcl, 1, .pcl), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
                });
            }
        },
        .dbus => {
            const params: DBusParams = uop.params.dbus;
            if(params.source == .dbus) { // Read
                bus.read = state.address_bus;
                bus.write = null;
                bus.data = state.registers.getU8(params.target);
            } else if(params.target == .dbus) { // Write
                bus.read = null;
                bus.write = state.address_bus;
                bus.data = state.registers.getU8(params.source);
            } else {
                unreachable;
            }
        },
        .decode => {
            // TODO: If an interrupt is pending during an instruction, do we handle interrupt immediately or after the next instruction like this?

            // TODO: Consider using an external system to only check and set an interrupt signal line on the cpu when IE and IF are checked.
            // Because the CPU should not be able to access IF and IE like this!
            // And this check is done at worst every m-cycle. but it could also just happen the moment an interrupt is set.
            // TODO: Using an external system would also allow me to split this decode function into decode and decode_interrupt
            // When an interrupt is pending or the IE bits are changed, we will inform the cpu about this. if all other conditions are met,
            // the cpu will replace the last instruction (decode) with the decode_interrupt instruction!
            const interrupt_signal: u8 = mmu.memory[mem_map.interrupt_enable] & mmu.memory[mem_map.interrupt_flag];
            if(state.interrupt_master_enable and interrupt_signal != 0) {
                const interrupt_idx: u3 = getLowestSetBit(interrupt_signal);
                const interrupt_uops: MicroOpArray = opcode_banks[opcode_bank_pseudo][interrupt_idx];
                state.uop_fifo.write(interrupt_uops.items);

                const mask: u8 = @as(u8, 1) << interrupt_idx;
                const result: u8 = mmu.memory[mem_map.interrupt_flag] & ~mask;
                mmu.memory[mem_map.interrupt_flag] = result;

                // TODO: Because we are preparing to load the next instruction but not decoding it we are skipping one byte.
                // Removing the pc again is more of a hack and it should not happen. 
                // I should rethink when exactly an interrupt would happen when it is triggered during an instruction.
                // And how that interacts with the EI instruction.
                state.registers.r16.pc -= 1;
            } else {
                const params: DecodeParams = uop.params.decode;
                const opcode_bank = opcode_banks[params.bank_idx];
                const opcode: u8 = state.registers.r8.ir;
                const uops: MicroOpArray = opcode_bank[opcode];
                state.uop_fifo.write(uops.items);
            }
        },
        .halt => {
            // pc is on byte after halt.
            // if no interrupt pending: set ir to 0x76 (HALT), set halt-again-flag => will decode halt again.
            // if interrupt pending & ime = true: set ir to 0x76 (HALT), reset halt-again-flag => will decode halt again and append interrupt. 
            // if interrupt pending & ime = false: 
            //             halt-again-flag = false: do nothing => byte is read twice (halt-bug).
            //             halt-again-flag = true: increment pcl, reset halt-again-flag => just like normal.

            // TODO: So many conditionals, a way to implement this better?
            const pc_curr: u16 = state.registers.r16.pc;
            if(pc_curr == 0) {}
            const halt_uop: u8 = 0x76;
            const interrupt_signal: u8 = mmu.memory[mem_map.interrupt_enable] & mmu.memory[mem_map.interrupt_flag];
            if(interrupt_signal == 0) { // No interrupt pending
                state.registers.r8.ir = halt_uop;
                state.halt_again = true;
            } else { // Interrupt pending
                if(state.interrupt_master_enable) {
                    state.registers.r8.ir = halt_uop;
                    state.halt_again = false;
                } else {
                    if(state.halt_again) {
                        state.registers.r16.pc += 1;
                        state.halt_again = false;
                    }
                }
            }
        },
        .idu_adjust => {
            const params: IduAdjustParams = uop.params.idu_adjust;
            const input_low: u8 = state.registers.getU8(params.input).*;
            const z: u8 = state.registers.r8.z;
            const result, const overflow = @addWithOverflow(z, input_low);
            state.registers.r8.z = result;

            // TODO: Can we do this better? Relative jumps to not change the flags, but other instructions do.
            if(params.change_flags) {
                const half_bcd: u1 = @truncate(((input_low & 0xF) + (z & 0xF)) >> 4);
                state.registers.r8.f = .{ .carry = overflow, .half_bcd = half_bcd, .n_bcd = 0, .zero = 0 };
            }

            const z_sign: u1 = @intCast(z >> 7);
            const carry: bool = overflow == 1;
            const amplitude: i2 = @intFromBool(carry) ^ z_sign;
            const adjust: i2 = if(z_sign == 1) -amplitude else amplitude;
            const input_high: u8 = state.registers.getU8(@enumFromInt(@intFromEnum(params.input) + 1)).*;
            state.registers.r8.w = input_high +% @as(u8, @bitCast(@as(i8, adjust)));
        },
        .nop => {
        },
        .set_pc => {
            const params: MiscParams = uop.params.misc;
            const new_pc: u16 = @as(u16, params.rst_idx) * 0x08;
            state.registers.r16.pc = new_pc;
        },
        .wz_writeback => {
            const params: MiscParams = uop.params.misc;
            const target: *u16 = state.registers.getU16(params.write_back);
            target.* = state.registers.r16.wz;
        },
        else => { 
            std.debug.print("CPU_MICRO_OP_NOT_IMPLEMENTED: {any}\n", .{uop});
            unreachable;
        },
    }

    return bus;
}

pub fn request(state: *State, bus: def.Bus) void {
    if (bus.read) |read_addr| {
        switch (read_addr) {
            mem_map.hram_low...(mem_map.hram_high - 1) => {
                const hram_addr = read_addr - mem_map.hram_low;
                bus.data.* = state.hram[hram_addr];
                bus.read = null;
            },
            mem_map.interrupt_enable => {
                bus.data.* = state.interrupt_enable;
                bus.read = null;
            },
            else => {},
        }
    } 

    if (bus.write) |write_addr| {
        switch (write_addr) {
            mem_map.hram_low...(mem_map.hram_high - 1) => {
                const hram_addr = write_addr - mem_map.hram_low;
                state.work_ram[hram_addr] = bus.data.*;
                bus.read = null;
            },
            mem_map.interrupt_enable => {
                state.work_ram[mem_map.interrupt_enable] = bus.data.*;
                bus.read = null;
            },
            else => {},
        }
    } 
}

pub fn loadDump(state: *State, file_type: def.FileType, alloc: std.mem.Allocator) void {
    // TODO: I would need a more stabile and better thought out initialization system when you load files.
    switch(file_type) {
        .gameboy => {
        },
        .dump => {
            init(state, alloc);
        },
        .unknown => {
        }
    }
}

fn getLowestSetBit(value: u8) u3 {
    // https://stackoverflow.com/questions/757059/position-of-least-significant-bit-that-is-set
    const deBrujinHash: u16 = 0b0001_1101;
    const deBrujinTable = [_]u3{ 0, 1, 6, 2, 7, 5, 4, 3 }; 
    const lowest: u8 = value & ~(value -% 1);
    const hash: u8 = @truncate(@as(u16, lowest) * deBrujinHash);
    return deBrujinTable[hash >> 5];
}
