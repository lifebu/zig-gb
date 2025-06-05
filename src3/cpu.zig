const std = @import("std");
const assert = std.debug.assert;

const def = @import("defines.zig");
const Fifo = @import("util/fifo.zig");
const mem_map = @import("mem_map.zig");
const MMU = @import("mmu.zig");

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
    temp_lsb, temp_msb,
    const_true, const_false,
    carry, half_bcd,
    n_bcd, zero,
};

// TODO: Try to implement interrupt handling differently so that I don't have to pay the size of the largest instruction and the interrupt handler.
const longest_instruction_cycles = 24 + 20; // CALL + InterruptHandler

const MicroOp = enum(u6) {
    unused,
    // General
    addr_idu, 
    apply_pins,
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
    // TODO: Once most of the other things are done, consider renaming all of the ffid alu ops to something without flag.
    // The shortnames make them a little bit harder to understand (especially sbf, adf)
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
    low_offset: bool,
    idu: i2,
    idu_out: RegisterFileID,
    _: u4 = 0, 
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
            @intFromBool(registers.getFlag(params.ffid)),
            registers.getU8(params.output),
        };
    }
};
const DecodeParams = packed struct(u15) {
    bank_idx: u2 = opcode_bank_default,
    _: u13 = 0,
};
// TODO: Is this the best way to implement this?
const ConditionCheck = enum(u2) {
    not_zero,
    zero,
    not_carry,
    carry,
};
const MiscParams = packed struct(u15) {
    write_back: RegisterFileID = .a,
    ime_value: bool = false,
    rst_idx: u4 = 0,
    cc: ConditionCheck = .not_zero,
    _: u4 = 0,
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
const MicroOpArray = std.BoundedArray(MicroOpData, longest_instruction_cycles);

// TODO: IN general add more sanity checks and asserts.
fn AddrIdu(addr: RegisterFileID, idu: i2, idu_out: RegisterFileID, low_offset: bool) MicroOpData {
    // TODO: Maybe add a sanity check here to see if the addr rfid is a valid 16-bit register? Because you could read 16bit between two 16bit registers.
    return .{ .operation = .addr_idu, .params = .{ .addr_idu = AddrIduParams{ .addr = addr, .idu = idu, .idu_out = idu_out, .low_offset = low_offset } } };
}
fn IduAdjust(input: RegisterFileID, change_flags: bool) MicroOpData {
    return .{ .operation = .idu_adjust, .params = .{ .idu_adjust = IduAdjustParams{ .input = input, .change_flags = change_flags } } };
}
fn AluFlag(func: MicroOp, input_1: RegisterFileID, input_2: RegisterFileID, ffid: FlagFileID, output: RegisterFileID) MicroOpData {
    return .{ .operation = func, .params = .{ .alu = AluParams{ .input_1 = input_1, .input_2 = .{ .rfid = input_2 }, .ffid = ffid, .output = output } } };
}
fn Alu(func: MicroOp, input_1: RegisterFileID, input_2: RegisterFileID, output: RegisterFileID) MicroOpData {
    return .{ .operation = func, .params = .{ .alu = AluParams{ .input_1 = input_1, .input_2 = .{ .rfid = input_2 }, .ffid = .const_false, .output = output } } };
}
fn AluValue(func: MicroOp, input_1: RegisterFileID, input_2: u4, output: RegisterFileID) MicroOpData {
    return .{ .operation = func, .params = .{ .alu = AluParams{ .input_1 = input_1, .input_2 = .{ .value = input_2 }, .ffid = .const_false, .output = output } } };
}
fn AluValueRel(func: MicroOp, input_1: RegisterFileID, input_2: i2, output: RegisterFileID) MicroOpData {
    return .{ .operation = func, .params = .{ .alu = AluParams{ .input_1 = input_1, .input_2 = .{ .value = @bitCast(@as(i4, input_2)) }, .ffid = .const_false, .output = output } } };
}
fn ApplyPins() MicroOpData {
    return .{ .operation = .apply_pins, .params = .none };
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
// TODO: Would be nicer to create this immediately instead of creating a function, but like this it is easier to implement the instructions in any order.
fn genOpcodeBanks() [num_opcode_banks][num_opcodes]MicroOpArray {
    var returnVal: [num_opcode_banks][num_opcodes]MicroOpArray = undefined;
    @memset(&returnVal, [_]MicroOpArray{.{}} ** num_opcodes);

    const r8_rfids = [_]RegisterFileID{ .b, .c, .d, .e, .h, .l, .dbus, .a };
    const r16_rfids = [_]RegisterFileID{ .c, .e, .l, .spl };
    const r16_stack_rfids = [_]RegisterFileID{ .c, .e, .l, .f };
    const cond_cc = [_]ConditionCheck{ .not_zero, .zero, .not_carry, .carry };
    
    // TODO: Right now some instruction use a different order than the default.
    // Could I find a order that fits all the cases cleanly?
    // Default order:
    // 0: ADDR + IDU 
    // 1: DBUS + Push Pins
    // 2: ALU/MISC + Apply Pins
    // 3: DECODE

    //
    // DEFAULT BANK:
    //

    // NOP
    returnVal[opcode_bank_default][0x00].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD r16, imm16
    const ld_r16_imm_opcodes = [_]u8{ 0x01, 0x11, 0x21, 0x31 };
    for (ld_r16_imm_opcodes, r16_rfids) |opcode, rfid| {
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z),  ApplyPins(),  Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .w),  ApplyPins(),  Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), MiscWB(rfid), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // LD r16mem, a
    const ld_r16mem_a_opcodes = [_]u8{ 0x02, 0x12, 0x22, 0x32 };
    const ld_r16mem_a_idu = [_]i2{ 0, 0, 1, -1 }; 
    const ld_r16mem_a_rfids = [_]RegisterFileID{ .c, .e, .l, .l };
    for(ld_r16mem_a_opcodes, ld_r16mem_a_rfids, ld_r16mem_a_idu) |opcode, rfid, idu| {
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(rfid, idu, rfid, false), Dbus(.a, .dbus),  ApplyPins(),                  Nop(),
            AddrIdu(.pcl, 1, .pcl, false),   Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // Inc r16
    const inc_r16_opcodes = [_]u8{ 0x03, 0x13, 0x23, 0x33 };
    for(inc_r16_opcodes, r16_rfids) |opcode, rfid| {
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(rfid, 1, rfid, false), Nop(),            Nop(), Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // INC r8
    const inc_r8_opcodes = [_]u8{ 0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34, 0x3C };
    for(inc_r8_opcodes, r8_rfids) |opcode, rfid| {
        // TODO: This edge case creates a lot of copied code between all the simple alu op variants.
        // Plus this condition is generally not a good way to solve this.
        if(rfid == .dbus) {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.l, 0, .l, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
                AddrIdu(.l, 0, .l, false), AluValueRel(.alu_inc, .z, 1, .z), Dbus(.z, .dbus), ApplyPins(),
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
            }) catch unreachable;
        } else {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluValueRel(.alu_inc, rfid, 1, rfid), Decode(opcode_bank_default),
            }) catch unreachable;
        }
    }

    // DEC r8
    const dec_r8_opcodes = [_]u8{ 0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D };
    for(dec_r8_opcodes, r8_rfids) |opcode, rfid| {
        if(rfid == .dbus) {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.l, 0, .l, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
                AddrIdu(.l, 0, .l, false), AluValueRel(.alu_inc, .z, -1, .z), Dbus(.z, .dbus), ApplyPins(),
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
            }) catch unreachable;
        } else {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluValueRel(.alu_inc, rfid, -1, rfid), Decode(opcode_bank_default),
            }) catch unreachable;
        }
    }

    // LD r8, imm8
    const ld_r8_imm8_opcodes = [_]u8{ 0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E };
    for(ld_r8_imm8_opcodes, r8_rfids) |opcode, rfid| {
        if(rfid == .dbus) {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z),  ApplyPins(), Nop(),
                AddrIdu(.l, 0, .l, false), Dbus(.z, .dbus), ApplyPins(), Nop(),
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
            }) catch unreachable;
        } else {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z),  ApplyPins(),                    Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_assign, .z, .z, rfid), Decode(opcode_bank_default),
            }) catch unreachable;
        }
    }

    // RLCA
    returnVal[opcode_bank_default][0x07].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_slf, .a, .b, .temp_msb, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD (imm16),SP
    returnVal[opcode_bank_default][0x08].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z),   ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .w),   ApplyPins(), Nop(),
        AddrIdu(.z, 1, .z, false),   Dbus(.spl, .dbus), ApplyPins(), Nop(),
        AddrIdu(.z, 0, .z, false),   Dbus(.sph, .dbus), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir),  ApplyPins(), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD a, r16mem
    // TODO: combine those just like LD r16mem, a
    const ld_a_r16mem_opcodes = [_]u8{ 0x0A, 0x1A };
    const ld_a_r16mem_rfids = [_]RegisterFileID{ .c, .e };
    for(ld_a_r16mem_opcodes, ld_a_r16mem_rfids) |opcode, rfid| {
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(rfid, 0, rfid, false), Dbus(.dbus, .z),   ApplyPins(),               Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir),  Alu(.alu_assign, .z, .z, .a), Decode(opcode_bank_default),
        }) catch unreachable;
    }
    const ld_a_r16mem_hl_opcodes = [_]u8{ 0x2A, 0x3A };
    const ld_a_r16mem_hl_idu = [_]i2{ 1, -1 };
    for(ld_a_r16mem_hl_opcodes, ld_a_r16mem_hl_idu) |opcode, idu| {
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(.l, idu, .l, false), Dbus(.dbus, .z),   ApplyPins(),               Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir),  Alu(.alu_assign, .z, .z, .a), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // DEC r16
    const dec_r16_opcodes = [_]u8{ 0x0B, 0x1B, 0x2B, 0x3B };
    for(dec_r16_opcodes, r16_rfids) |opcode, rfid| {
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(rfid, -1, rfid, false), Nop(),           Nop(), Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // ADD HL, R16
    const add_hl_r16_opcodes = [_]u8{ 0x09, 0x19, 0x29, 0x39 };
    for(add_hl_r16_opcodes, r16_rfids) |opcode, rfid| {
        const r16_msb: RegisterFileID = @enumFromInt((@intFromEnum(rfid) + 1));
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            // TODO: In gekkio it shows + and then +_c, so I think I need add and add+carry? Test this!
            Nop(), Nop(), AluFlag(.alu_adf, .l, rfid, .const_false, .l), Nop(),
            AddrIdu(.pcl, 1, .pcl, false),   Dbus(.dbus, .ir), AluFlag(.alu_adf, .h, r16_msb, .carry, .h), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // RRCA
    returnVal[opcode_bank_default][0x0F].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_srf, .a, .b, .temp_lsb, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // STOP
    returnVal[opcode_bank_default][0x10].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Nop(), Nop(), Decode(opcode_bank_pseudo),
    }) catch unreachable;

    // RLA
    returnVal[opcode_bank_default][0x17].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_slf, .a, .b, .carry, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // JR r8 
    returnVal[opcode_bank_default][0x18].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        IduAdjust(.pcl, false), Nop(), Nop(), Nop(),
        AddrIdu(.z, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
    }) catch unreachable;

    // RRA
    returnVal[opcode_bank_default][0x1F].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_srf, .a, .b, .carry, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // JR cond imm8
    const jr_cond_imm8_opcodes = [_]u8{ 0x20, 0x28, 0x30, 0x38 };
    for(jr_cond_imm8_opcodes, cond_cc) |opcode, cc| {
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), MiscCC(cc), Nop(),
            IduAdjust(.pcl, false), Nop(), Nop(), Nop(),
            AddrIdu(.z, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // DAA
    returnVal[opcode_bank_default][0x27].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_daa_adjust, .a, .a, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // CPL
    returnVal[opcode_bank_default][0x2F].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_not, .a, .a, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // SCF
    returnVal[opcode_bank_default][0x37].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_scf, .a, .a, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // CCF
    returnVal[opcode_bank_default][0x3F].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_ccf, .a, .a, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD r8, r8
    // TODO: Would be nicer to have a searchable list like the other operations, so that If I have a bug with 0x45, I know which opcode it must be.
    var ld_r8_r8_opcode: u8 = 0x40;
    for(r8_rfids) |target_rfid| {
        for (r8_rfids) |source_rfid| {
            // TODO: This branch is even worse! The cases are rarely hit, especially HALT!
            if(source_rfid == .dbus and target_rfid == .dbus) { // HALT
                returnVal[opcode_bank_default][ld_r8_r8_opcode].appendSlice(&[_]MicroOpData{
                    AddrIdu(.pcl, 0, .pcl, false), Dbus(.dbus, .ir), MiscHALT(), Decode(opcode_bank_default),
                }) catch unreachable;
            } else if (source_rfid == .dbus) {
                returnVal[opcode_bank_default][ld_r8_r8_opcode].appendSlice(&[_]MicroOpData{
                    AddrIdu(.l, 0, .l, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
                    AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_assign, .z, .z, target_rfid), Decode(opcode_bank_default),
                }) catch unreachable;
            } else if (target_rfid == .dbus) {
                returnVal[opcode_bank_default][ld_r8_r8_opcode].appendSlice(&[_]MicroOpData{
                    AddrIdu(.l, 0, .l, false), Dbus(source_rfid, .dbus), ApplyPins(), Nop(),
                    AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
                }) catch unreachable;
            }
            else {
                returnVal[opcode_bank_default][ld_r8_r8_opcode].appendSlice(&[_]MicroOpData{
                    AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_assign, source_rfid, source_rfid, target_rfid), Decode(opcode_bank_default),
                }) catch unreachable;
            }
            ld_r8_r8_opcode += 1;
        }
    }

    // TODO: ADD, ADC, SUB, SBC, AND, OR, basically all single mcycle instructions have the same structure.
    // Only the ALU op changes, so we can combine them?
    // ADD a, r8
    const add_a_r8_opcodes = [_]u8{ 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87 };
    for(add_a_r8_opcodes, r8_rfids) |opcode, rfid| {
        if(rfid == .dbus) {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.l, 0, .l, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_adf, .a, .z, .const_false, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        } else {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_adf, .a, rfid, .const_false, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        }
    }

    // ADC a, r8
    const adc_a_r8_opcodes = [_]u8{ 0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E, 0x8F };
    for(adc_a_r8_opcodes, r8_rfids) |opcode, rfid| {
        if(rfid == .dbus) {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.l, 0, .l, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_adf, .a, .z, .carry, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        } else {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_adf, .a, rfid, .carry, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        }
    }

    // SUB a, r8
    const sub_a_r8_opcodes = [_]u8{ 0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97 };
    for(sub_a_r8_opcodes, r8_rfids) |opcode, rfid| {
        if(rfid == .dbus) {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.l, 0, .l, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_sbf, .z, .z, .const_false, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        } else {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_sbf, rfid, rfid, .const_false, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        }
    }

    // SBC a, r8
    const sbc_a_r8_opcodes = [_]u8{ 0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F };
    for(sbc_a_r8_opcodes, r8_rfids) |opcode, rfid| {
        if(rfid == .dbus) {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.l, 0, .l, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_sbf, .z, .z, .carry, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        } else {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_sbf, rfid, rfid, .carry, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        }
    }

    // AND a, r8
    const and_a_r8_opcodes = [_]u8{ 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7 };
    for(and_a_r8_opcodes, r8_rfids) |opcode, rfid| {
        if(rfid == .dbus) {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.l, 0, .l, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_and, .z, .z, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        } else {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_and, rfid, rfid, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        }
    }

    // XOR a, r8
    const xor_a_r8_opcodes = [_]u8{ 0xA8, 0xA9, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF };
    for(xor_a_r8_opcodes, r8_rfids) |opcode, rfid| {
        if(rfid == .dbus) {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.l, 0, .l, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_xor, .z, .z, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        } else {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_xor, rfid, rfid, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        }
    }

    // OR a, r8
    const or_a_r8_opcodes = [_]u8{ 0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7 };
    for(or_a_r8_opcodes, r8_rfids) |opcode, rfid| {
        if(rfid == .dbus) {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.l, 0, .l, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_or, .z, .z, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        } else {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_or, rfid, rfid, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        }
    }

    // CP a, r8
    const cp_a_r8_opcodes = [_]u8{ 0xB8, 0xB9, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF };
    for(cp_a_r8_opcodes, r8_rfids) |opcode, rfid| {
        if(rfid == .dbus) {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.l, 0, .l, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_cp, .z, .z, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        } else {
            returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_cp, rfid, rfid, .a), Decode(opcode_bank_default),
            }) catch unreachable;
        }
    }

    // RET cond
    const ret_cond_opcodes = [_]u8{ 0xC0, 0xC8, 0xD0, 0xD8 };
    for(ret_cond_opcodes, cond_cc) |opcode, cc| {
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            Nop(), Nop(), MiscCC(cc), Nop(),
            AddrIdu(.spl, 1, .spl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
            AddrIdu(.spl, 1, .spl, false), Dbus(.dbus, .w), ApplyPins(), Nop(),
            Nop(), Nop(), MiscWB(.pcl), Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // POP r16stk
    const pop_rr_opcodes = [_]u8{ 0xC1, 0xD1, 0xE1, 0xF1 };
    for(pop_rr_opcodes, r16_stack_rfids) |opcode, rfid| {
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(.spl, 1, .spl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
            AddrIdu(.spl, 1, .spl, false), Dbus(.dbus, .w), ApplyPins(), Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), MiscWB(rfid), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // JP cond imm16
    const jp_cond_opcodes = [_]u8{ 0xC2, 0xCA, 0xD2, 0xDA };
    for(jp_cond_opcodes, cond_cc) |opcode, cc| {
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .w), MiscCC(cc), Nop(),
            Nop(), Nop(), MiscWB(.pcl), Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // PUSH r16stk
    const push_rr_opcodes = [_]u8{ 0xC5, 0xD5, 0xE5, 0xF5 };
    for(push_rr_opcodes, r16_stack_rfids) |opcode, rfid| {
        const msb_rfid: RegisterFileID = @enumFromInt(@intFromEnum(rfid) + 1);
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(.spl, -1, .spl, false), Nop(), Nop(), Nop(),
            AddrIdu(.spl, -1, .spl, false), Dbus(msb_rfid, .dbus), ApplyPins(), Nop(),
            AddrIdu(.spl, 0, .spl, false), Dbus(rfid, .dbus), ApplyPins(), Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // JP imm16
    returnVal[opcode_bank_default][0xC3].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .w), ApplyPins(), Nop(),
        Nop(), Nop(), MiscWB(.pcl), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
    }) catch unreachable;


    // CALL cond imm16
    const call_cond_opcodes = [_]u8{ 0xC4, 0xCC, 0xD4, 0xDC };
    for(call_cond_opcodes, cond_cc) |opcodes, cc| {
        returnVal[opcode_bank_default][opcodes].appendSlice(&[_]MicroOpData{
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .w), MiscCC(cc), Nop(),
            AddrIdu(.spl, -1, .spl, false), Nop(), Nop(), Nop(),
            AddrIdu(.spl, -1, .spl, false), Dbus(.pch, .dbus), ApplyPins(), Nop(),
            AddrIdu(.spl, 0, .spl, false), Dbus(.pcl, .dbus), MiscWB(.pcl), Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // ADD a, imm8
    returnVal[opcode_bank_default][0xC6].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_adf, .a, .z, .const_false, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // RST target
    const rst_opcodes = [_]u8{ 0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF };
    const rst_idx = [_]u4{ 0, 1, 2, 3, 4, 5, 6, 7 };
    for(rst_opcodes, rst_idx) |opcodes, idx| {
        returnVal[opcode_bank_default][opcodes].appendSlice(&[_]MicroOpData{
            AddrIdu(.spl, -1, .spl, false), Nop(), Nop(), Nop(),
            AddrIdu(.spl, -1, .spl, false), Dbus(.pch, .dbus), ApplyPins(), Nop(),
            AddrIdu(.spl, 0, .spl, false), Dbus(.pcl, .dbus), MiscRST(idx), Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // RET
    returnVal[opcode_bank_default][0xC9].appendSlice(&[_]MicroOpData{
        AddrIdu(.spl, 1, .spl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.spl, 1, .spl, false), Dbus(.dbus, .w), ApplyPins(), Nop(),
        Nop(), Nop(), MiscWB(.pcl), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
    }) catch unreachable;

    // Prefix
    returnVal[opcode_bank_default][0xCB].appendSlice(&[_]MicroOpData{ // prefix
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_prefix),
    }) catch unreachable;

    // CALL imm16
    // TODO: CALL and CALL cc are almost the same. the only difference is the CC Check after changing WZ.
    returnVal[opcode_bank_default][0xCD].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .w), ApplyPins(), Nop(),
        AddrIdu(.spl, -1, .spl, false), Nop(), Nop(), Nop(),
        AddrIdu(.spl, -1, .spl, false), Dbus(.pch, .dbus), ApplyPins(), Nop(),
        AddrIdu(.spl, 0, .spl, false), Dbus(.pcl, .dbus), MiscWB(.pcl), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
    }) catch unreachable;

    // ADC a, imm8
    // TODO: ADC a, imm8 and ADC a, r8 are very similar.
    returnVal[opcode_bank_default][0xCE].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_adf, .a, .z, .carry, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // SUB a, imm8
    // TODO: SUB a, imm8 and SUB a, r8 are very similar.
    returnVal[opcode_bank_default][0xD6].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_sbf, .z, .z, .const_false, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // RETI
    returnVal[opcode_bank_default][0xD9].appendSlice(&[_]MicroOpData{
        AddrIdu(.spl, 1, .spl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.spl, 1, .spl, false), Dbus(.dbus, .w), ApplyPins(), Nop(),
        Nop(), Nop(), MiscWB(.pcl), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), MiscIME(true), Decode(opcode_bank_default),
    }) catch unreachable;

    // SBC a, imm8
    // TODO: SBC a, imm8 and SBC a, r8 are very similar.
    returnVal[opcode_bank_default][0xDE].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(.alu_sbf, .z, .z, .carry, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // LDH [imm8], a
    returnVal[opcode_bank_default][0xE0].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.z, 0, .z, true), Dbus(.a, .dbus), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
    }) catch unreachable;

    // LDH [c], a
    returnVal[opcode_bank_default][0xE2].appendSlice(&[_]MicroOpData{
        AddrIdu(.c, 0, .c, true), Dbus(.a, .dbus), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
    }) catch unreachable;

    // AND a, imm8
    // TODO: AND a, imm8 and AND a, r8 are very similar.
    returnVal[opcode_bank_default][0xE6].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_and, .z, .z, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // ADD SP, imm8 (signed)
    returnVal[opcode_bank_default][0xE8].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        // Note: Using IduAdjust + WZ-Writebak differs from the definition from gekkio. They use a special adjust add.
        IduAdjust(.spl, true), Nop(), Nop(), Nop(),
        Nop(), Nop(), Nop(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), MiscWB(.spl), Decode(opcode_bank_default),
    }) catch unreachable;

    // JP HL
    returnVal[opcode_bank_default][0xE9].appendSlice(&[_]MicroOpData{
        AddrIdu(.l, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD [imm16], a
    returnVal[opcode_bank_default][0xEA].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .w), ApplyPins(), Nop(),
        AddrIdu(.z, 0, .z, false), Dbus(.a, .dbus), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
    }) catch unreachable;

    // XOR a, imm8
    // TODO: XOR a, imm8 and XOR a, r8 are very similar.
    returnVal[opcode_bank_default][0xEE].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_xor, .z, .z, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // LDH a, [imm8]
    // TODO: There are a lot of LDH instructions with 8bit values, can I combine them?
    returnVal[opcode_bank_default][0xF0].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.z, 0, .z, true), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_assign, .z, .z, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // LDH a, [c]
    returnVal[opcode_bank_default][0xF2].appendSlice(&[_]MicroOpData{
        AddrIdu(.c, 0, .c, true), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_assign, .z, .z, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD a, [imm16]
    returnVal[opcode_bank_default][0xFA].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .w), ApplyPins(), Nop(),
        AddrIdu(.z, 0, .z, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_assign, .z, .z, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // DI (Disable Interrupts)
    returnVal[opcode_bank_default][0xF3].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), MiscIME(false), Decode(opcode_bank_default),
    }) catch unreachable;

    // OR a, imm8
    // TODO: OR a, imm8 and OR a, r8 are very similar.
    returnVal[opcode_bank_default][0xF6].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_or, .z, .z, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD HL, SP+imm8(signed)
    returnVal[opcode_bank_default][0xF8].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        // Note: Using IduAdjust + WZ-Writebak differs from the definition from gekkio. They use a special adjust add.
        IduAdjust(.spl, true), Nop(), MiscWB(.l), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD SP, HL
    returnVal[opcode_bank_default][0xF9].appendSlice(&[_]MicroOpData{
        AddrIdu(.l, 0, .spl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
    }) catch unreachable;

    // EI (Enable Interrupts)
    returnVal[opcode_bank_default][0xFB].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), MiscIME(true), Decode(opcode_bank_default),
    }) catch unreachable;

    // CP a, imm8
    // TODO: CP a, imm8 and CP a, r8 are very similar.
    returnVal[opcode_bank_default][0xFE].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), Alu(.alu_cp, .z, .z, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    //
    // PREFIX BANK:
    //

    const bit_shift_flags = [_]FlagFileID{ .temp_msb, .temp_lsb, .carry,   .carry,   .const_false, .temp_msb,    .temp_msb, .const_false };
    const bit_shift_uops = [_]MicroOp{     .alu_slf,  .alu_srf,  .alu_slf, .alu_srf, .alu_slf,     .alu_srf,     .alu_swap, .alu_srf }; 
    // TODO: Would be nicer to have a searchable list like the other operations, so that If I have a bug with 0x45, I know which opcode it must be.
    var bit_shift_opcode: u8 = 0x00;
    for(bit_shift_uops, bit_shift_flags) |bit_shift_uop, flag| {
        for(r8_rfids) |rfid| {
            if(rfid == .dbus) {
                returnVal[opcode_bank_prefix][bit_shift_opcode].appendSlice(&[_]MicroOpData{
                    AddrIdu(.l, 0, .l, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
                    AddrIdu(.l, 0, .l, false), AluFlag(bit_shift_uop, .z, .z, flag, .z), Dbus(.z, .dbus), ApplyPins(),
                    AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
                }) catch unreachable;
            } else {
                returnVal[opcode_bank_prefix][bit_shift_opcode].appendSlice(&[_]MicroOpData{
                    AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluFlag(bit_shift_uop, rfid, rfid, flag, rfid), Decode(opcode_bank_default),
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
                        returnVal[opcode_bank_prefix][bit_opcode].appendSlice(&[_]MicroOpData{
                            AddrIdu(.l, 0, .l, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
                            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluValue(bit_uop, .z, @intCast(bit_index), .z), Decode(opcode_bank_default),
                        }) catch unreachable;
                    }
                    else {
                        returnVal[opcode_bank_prefix][bit_opcode].appendSlice(&[_]MicroOpData{
                            AddrIdu(.l, 0, .l, false), Dbus(.dbus, .z), ApplyPins(), Nop(),
                            AddrIdu(.l, 0, .l, false), AluValue(bit_uop, .z, @intCast(bit_index), .z), Dbus(.z, .dbus), ApplyPins(),
                            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
                        }) catch unreachable;
                    }
                } else {
                    returnVal[opcode_bank_prefix][bit_opcode].appendSlice(&[_]MicroOpData{
                        AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), AluValue(bit_uop, rfid, @intCast(bit_index), rfid), Decode(opcode_bank_default),
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
        returnVal[opcode_bank_pseudo][opcode].appendSlice(&[_]MicroOpData{
            Nop(), Nop(), Nop(), Nop(),
            AddrIdu(.spl, -1, .spl, false), Nop(), Nop(), Nop(),
            AddrIdu(.spl, -1, .spl, false), Dbus(.pch, .dbus), MiscIME(false), Nop(),
            AddrIdu(.spl, 0, .spl, false), Dbus(.pcl, .dbus), MiscRST(idx), Nop(),
            AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // TODO: Placeholder: Need an actual implementation for STOP.
    // STOP
    returnVal[opcode_bank_pseudo][0x10].appendSlice(&[_]MicroOpData{
        Nop(), Nop(), Nop(), Decode(opcode_bank_pseudo),
    }) catch unreachable;

    return returnVal;

}
pub var opcode_banks: [num_opcode_banks][num_opcodes]MicroOpArray = undefined;

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
    // TODO: Maybe a function where I combine two Flags (IF and IE) and it returns which interrupt is pending?
};

pub const FlagRegister = packed union {
    f: u8,
    flags: packed struct {
        // TODO: Pseudo flags are only for the internal usage of the emulator and not part of the gameboy itself.
        // The gameboy always sees them as 0. But this adds some house keeping to make sure we don't ovewrite them with PUSH AF and POP AF.
        // Could we implement the ffids better so that this bookkeeping is not necessary?
        // For example there is another byte in the RegisterFile after the Flags for the pseudo flags.
        // FFID than has 4 unused at the start, the 4 actual flags and then the flags of the next byte you can address.
        // Pseudo flags
        temp_lsb: bool = false,
        temp_msb: bool = false,
        const_true: bool = true,
        const_false: bool = false,
        // Cpu flags
        // TODO: u1 or bool?
        carry: bool = false,
        half_bcd: bool = false,
        n_bcd: bool = false,
        zero: bool = false,
    },
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
        f: FlagRegister = .{ .flags = .{} }, a: u8 = 0,
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
    pub fn getFlag(self: *Self, ffid: FlagFileID) bool {
        const bit_index: u3 = @intFromEnum(ffid); 
        const result: u8 = (self.r8.f.f >> bit_index) & 0x01;
        return result == 0x01;
    }
};

const MemoryRequest = enum {
    none,
    read,
    write,
};

pub const State = struct {
    uop_fifo: MicroOpFifo = .{}, 

    registers: RegisterFile = .{ .r8 = .{} },
    address_bus: u16 = 0,
    dbus_source: u8 = 0,
    dbus_target: *u8 = undefined,

    interrupt_enable: InterruptFlags = .{},
    interrupt_master_enable: bool = false,

    // Differentiate the behaviour of halt when it is first encountered vs repeated hits (cpu is halted).
    halt_again: bool = false,
};

pub fn init(state: *State) void {
    opcode_banks = genOpcodeBanks();

    const opcode_bank = opcode_banks[opcode_bank_default];
    const uops: MicroOpArray = opcode_bank[state.registers.r8.ir];
    state.uop_fifo.write(uops.slice());
}

pub fn cycle(state: *State, mmu: *MMU.State) void {
    const uop: MicroOpData = state.uop_fifo.readItem().?;
    switch(uop.operation) {
        // TODO: When and how does the cpu write the result of the memory request to it's dbus?
        .addr_idu => {
            const params: AddrIduParams = uop.params.addr_idu;
            if(params.low_offset) {
                const input: u8 = state.registers.getU8(params.addr).*;
                const addr: u16 = 0xFF00 + @as(u16, input);
                state.address_bus = addr;
                const output: *u8 = state.registers.getU8(params.idu_out);
                // +% -1 <=> +% 255
                const idu_factor: u8 = @bitCast(@as(i8, params.idu));
                output.* = input +% idu_factor;

            } else {
                const addr: u16 = state.registers.getU16(params.addr).*;
                state.address_bus = addr;
                const output: *u16 = state.registers.getU16(params.idu_out);
                // +% -1 <=> +% 65535
                const idu_factor: u16 = @bitCast(@as(i16, params.idu));
                output.* = addr +% idu_factor;
            }

            applyPins(state, mmu);
        },
        // TODO: Look at all the alu implementation and see where we can use some common changes and combine them to make the code clearer and more concise.
        // TODO: Look at all of the uops and see if we can combine them. Examples
        // - Inc and Dec can be expressed the same: -1 <=> +% 255
        //      - Inc and Dec could also be expressed by add and sub respectively?
        // - Can ADD and ADC as well as SUB and SBC be combined?
        // - Can we express add and sub the same: -n <=> +% (256 - n)
        // - AND, OR, XOR are the same code. The only thing that changes is the actual operation. 
        // - Is RLC with C = 0 the same as RL? (Same for RRC with C = 0 and RR). 
        // - Can we combine sr and srl?
        .alu_adf => {
            const input_1, const input_2, _, const flag, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            const input_flag, const flag_overflow = @addWithOverflow(input_1, flag);
            const result, const overflow = @addWithOverflow(input_2, input_flag);
            output.* = result;

            // TODO: This feels extemly hacky and I don't know if this works in practice all the time.
            // ADD HL, r16 does not change the zero flag, but all other kinds of ADD instructions do?
            if(uop.params.alu.output == .a) {
                state.registers.r8.f.flags.zero = result == 0;
            }
            state.registers.r8.f.flags.n_bcd = false;
            // TODO: Research how to more easily implement half_bcd. According to gekkio it is carry_per_bit[3]. carry is carry_per_bit[7].
            const input_hbcd: bool = (((input_1 & 0x0F) +% (flag & 0x0F)) & 0x10) == 0x10;
            const input_carry_hbcd: bool = (((input_2 & 0x0F) +% (input_flag & 0x0F)) & 0x10) == 0x10;
            state.registers.r8.f.flags.half_bcd = input_hbcd or input_carry_hbcd;
            state.registers.r8.f.flags.carry = flag_overflow == 1 or overflow == 1;
            applyPins(state, mmu);
        },
        .alu_and => {
            const input_1, _, _, _, _ = AluParams.Unpack(&state.registers, uop.params.alu);
            state.registers.r8.a &= input_1;

            state.registers.r8.f.flags.zero = state.registers.r8.a == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = true;
            state.registers.r8.f.flags.carry = false;
            applyPins(state, mmu);
        },
        .alu_assign => {
            const input_1, _, _, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            output.* = input_1;
            applyPins(state, mmu);
        },
        .alu_bit => {
            const input_1, _, const input_2, _, _ = AluParams.Unpack(&state.registers, uop.params.alu);
            const result: u8 = input_1 & (@as(u8, 1) << @as(u3, @intCast(input_2)));

            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = true;
            state.registers.r8.f.flags.zero = result == 0;
            applyPins(state, mmu);
        },
        .alu_ccf => {
            state.registers.r8.f.flags.carry = !state.registers.r8.f.flags.carry;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            applyPins(state, mmu);
        },
        .alu_cp => {
            const input_1, _, _, _, _ = AluParams.Unpack(&state.registers, uop.params.alu);
            const a: u8 = state.registers.r8.a;
            const result, const overflow = @subWithOverflow(a, input_1);

            state.registers.r8.f.flags.zero = result == 0;
            state.registers.r8.f.flags.n_bcd = true;
            state.registers.r8.f.flags.half_bcd = (((a & 0x0F) -% (input_1 & 0x0F)) & 0x10) == 0x10;
            state.registers.r8.f.flags.carry = overflow == 1;
            applyPins(state, mmu);
        },
        .alu_daa_adjust => {
            // TODO: Find a simpler algorithm for this. preferably something that can use u1 instead of bool
            const a: u8 = state.registers.r8.a;
            const half_bcd = state.registers.r8.f.flags.half_bcd;
            const carry = state.registers.r8.f.flags.carry;
            const subtract = state.registers.r8.f.flags.n_bcd;

            var offset: u8 = 0;
            var should_carry: bool = false;
            if((!subtract and ((a & 0xF) > 0x09)) or half_bcd) {
                offset |= 0x06;
            }
            if((!subtract and (a > 0x99)) or carry) {
                offset |= 0x60;
                should_carry = true;
            }
            const result = if (subtract) a -% offset else a +% offset;
            state.registers.r8.a = result;

            state.registers.r8.f.flags.carry = should_carry;
            state.registers.r8.f.flags.zero = result == 0;
            state.registers.r8.f.flags.half_bcd = false;
            applyPins(state, mmu);
        },
        .alu_inc => {
            // TODO: I can probably implement alu_inc with alu_adf? If I also allow an additional u4 value that will be added.
            // TODO: Maybe use a full u8 instead of the u4? Might be more usefull?
            const input_1, _, const input_2, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            // TODO: This works but it is a type unsafe to cast a i2 to u4 and back.
            const factor: i2 = @bitCast(@as(u2, @truncate(input_2)));
            // +% -1 <=> +% 255
            const factor_inc: u8 = @bitCast(@as(i8, factor));
            output.* = input_1 +% factor_inc;

            // TODO: Maybe we create a more compact way to change the flags? Like a function?
            state.registers.r8.f.flags.zero = output.* == 0; 
            state.registers.r8.f.flags.n_bcd = if(factor < 0) true else false;
            state.registers.r8.f.flags.half_bcd = (((input_1 & 0x0F) +% factor_inc) & 0x10) == 0x10; 
            applyPins(state, mmu);
        },
        .alu_not => {
            const input_1, _, _, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            output.* = ~input_1;

            state.registers.r8.f.flags.n_bcd = true;
            state.registers.r8.f.flags.half_bcd = true;
            applyPins(state, mmu);
        },
        .alu_or => {
            const input_1, _, _, _, _ = AluParams.Unpack(&state.registers, uop.params.alu);
            state.registers.r8.a |= input_1;

            state.registers.r8.f.flags.zero = state.registers.r8.a == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            state.registers.r8.f.flags.carry = false;
            applyPins(state, mmu);
        }, 
        .alu_res => {
            const input_1, _, const input_2, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            const result: u8 = input_1 & ~(@as(u8, 1) << @as(u3, @intCast(input_2)));
            output.* = result;
            applyPins(state, mmu);
        }, 
        .alu_sbf => {
            // TODO: A lot of uops are getting the input/output from the params struct. 
            // I could provide a function that takes the params and the registers and returns a data struct for this instruction.
            // This should reduce the number of lines significantly, but also mean we would querry all possible parameters and not use some of them.
            // Is the compiler to optimize away unused variables I query?
            const input_1, _, _, const flag, _ = AluParams.Unpack(&state.registers, uop.params.alu);
            const input_flag, const flag_overflow = @addWithOverflow(input_1, flag);
            const a: u8 = state.registers.r8.a;
            const result, const overflow = @subWithOverflow(a, input_flag);

            state.registers.r8.f.flags.carry = flag_overflow == 1 or overflow == 1;
            state.registers.r8.f.flags.zero = result == 0;
            state.registers.r8.f.flags.n_bcd = true;
            // TODO: Find a better way to calculate half_bcd
            const input_hbcd: bool = (((input_1 & 0x0F) +% (flag & 0x0F)) & 0x10) == 0x10;
            const input_cary_hbcd: bool = (((a & 0x0F) -% (input_flag & 0x0F)) & 0x10) == 0x10;
            state.registers.r8.f.flags.half_bcd = input_hbcd or input_cary_hbcd;

            state.registers.r8.a = result;
            applyPins(state, mmu);
        },
        .alu_scf => {
            state.registers.r8.f.flags.carry = true;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            applyPins(state, mmu);
        },
        .alu_set => {
            const input_1, _, const input_2, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            const result: u8 = input_1 | (@as(u8, 1) << @as(u3, @intCast(input_2)));
            output.* = result;
            applyPins(state, mmu);
        },
        .alu_slf => {
            const input_1, _, _, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            var result, const shifted_bit = @shlWithOverflow(input_1, 1);
            state.registers.r8.f.flags.temp_msb = shifted_bit == 1;
            const flag: u8 = @intFromBool(state.registers.getFlag(uop.params.alu.ffid));
            result |= flag;
            output.* = result;

            state.registers.r8.f.flags.carry = shifted_bit == 1;
            // TODO: Workaround to not set the flag values for rlca. Need a better flag system.
            state.registers.r8.f.flags.zero = if(uop.params.alu.input_1 == uop.params.alu.input_2.rfid) result == 0 else false;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            applyPins(state, mmu);
        },
        .alu_srf => {
            const input_1, _, _, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            const lsb: u1 = @intCast(input_1 & 0x01); 
            const msb: u1 = @intCast(input_1 >> 7);
            state.registers.r8.f.flags.temp_lsb = lsb == 0x01;
            state.registers.r8.f.flags.temp_msb = msb == 0x01;
            const flag: u8 = @intFromBool(state.registers.getFlag(uop.params.alu.ffid));
            const result: u8 = (input_1 >> 1) | (flag << 7);
            output.* = result;

            state.registers.r8.f.flags.carry = lsb == 0x01;
            // TODO: Workaround to not set the flag values for rra. Need a better flag system.
            state.registers.r8.f.flags.zero = if(uop.params.alu.input_1 == uop.params.alu.input_2.rfid) result == 0 else false;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            applyPins(state, mmu);
        },
        .alu_swap => {
            const input_1, _, _, _, const output = AluParams.Unpack(&state.registers, uop.params.alu);
            const result = (input_1 << 4) | (input_1 >> 4);
            output.* = result;

            state.registers.r8.f.flags.carry = false;
            state.registers.r8.f.flags.zero = result == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            applyPins(state, mmu);
        },
        .alu_xor => {
            const input_1, _, _, _, _ = AluParams.Unpack(&state.registers, uop.params.alu);
            state.registers.r8.a ^= input_1;

            state.registers.r8.f.flags.zero = state.registers.r8.a == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            state.registers.r8.f.flags.carry = false;
            applyPins(state, mmu);
        },
        .apply_pins => {
            applyPins(state, mmu);
        },
        .change_ime => {
            state.interrupt_master_enable = uop.params.misc.ime_value;
            applyPins(state, mmu);
        },
        .conditional_check => {
            const params: MiscParams = uop.params.misc;
            const cc = params.cc;
            const flag: bool = switch(cc) {
                .not_zero => !state.registers.r8.f.flags.zero,
                .zero => state.registers.r8.f.flags.zero,
                .not_carry => !state.registers.r8.f.flags.carry,
                .carry => state.registers.r8.f.flags.carry,
            };

            if(!flag) { // Load next instruction
                assert((state.uop_fifo.length() % 4) == 1); // We assume that conditional_check uop is followed by another uop inside of this mcycle (Decode step).
                state.uop_fifo.clear();
                state.uop_fifo.write(&[_]MicroOpData{
                    Nop(),
                    AddrIdu(.pcl, 1, .pcl, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
                });
            }
            applyPins(state, mmu);
        },
        .dbus => {
            const params: DBusParams = uop.params.dbus;
            const source = state.registers.getU8(params.source);
            // Make sure to never overwrite the pseudo flags.
            const mask: u8 = if(params.source == .f) 0xF0 else 0xFF;
            state.dbus_source = source.* & mask;
            state.dbus_target = state.registers.getU8(params.target);
            const request: MemoryRequest = if(params.source == .dbus) .read else if(params.target == .dbus) .write else .none;
            pushPins(state, mmu, request);
        },
        .decode => {
            const params: DecodeParams = uop.params.decode;
            const opcode_bank = opcode_banks[params.bank_idx];
            const opcode: u8 = state.registers.r8.ir;
            const uops: MicroOpArray = opcode_bank[opcode];
            state.uop_fifo.write(uops.slice());

            // TODO: Consider using an external system to only check and set an interrupt signal line on the cpu when IE and IF are checked.
            // Because the CPU should not be able to access IF and IE like this!
            // And this check is done at worst every m-cycle. but it could also just happen the moment an interrupt is set.
            const interrupt_signal: u8 = mmu.memory[mem_map.interrupt_enable] & mmu.memory[mem_map.interrupt_flag];
            if(state.interrupt_master_enable and interrupt_signal != 0) {
                // https://stackoverflow.com/questions/757059/position-of-least-significant-bit-that-is-set
                const deBrujinHash: u16 = 0b0001_1101;
                const deBrujinTable = [_]u3{ 0, 1, 6, 2, 7, 5, 4, 3 }; 
                const interrupt_lowest: u8 = interrupt_signal & ~(interrupt_signal -% 1);
                const interrupt_hash: u8 = @truncate(@as(u16, interrupt_lowest) * deBrujinHash);
                const interrupt_idx: u3 = deBrujinTable[interrupt_hash >> 5];
                const interrupt_uops: MicroOpArray = opcode_banks[opcode_bank_pseudo][interrupt_idx];
                state.uop_fifo.write(interrupt_uops.slice());

                const mask: u8 = @as(u8, 1) << interrupt_idx;
                const result: u8 = mmu.memory[mem_map.interrupt_flag] & ~mask;
                mmu.memory[mem_map.interrupt_flag] = result;
            }
        },
        .halt => {
            applyPins(state, mmu);
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

            if(params.change_flags) {
                state.registers.r8.f.flags.carry = overflow == 1;
                state.registers.r8.f.flags.zero = false;
                state.registers.r8.f.flags.n_bcd = false;
                state.registers.r8.f.flags.half_bcd = ((input_low & 0x0F) +% (z & 0x0F)) > 0x0F;
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
        // TODO: Maybe rename this to reset_pc? It is only used for the rst_offsets.
        // Maybe we can also use this for the interrupt handlers?
        // Could this maybe be combined with AddrIdu?
        .set_pc => {
            const params: MiscParams = uop.params.misc;
            const new_pc: u16 = @as(u16, params.rst_idx) * 0x08;
            state.registers.r16.pc = new_pc;
            applyPins(state, mmu);
        },
        // TODO: The IDU now can have different inputs and outputs, so we can also implement this function with the IDU?
        .wz_writeback => {
            const params: MiscParams = uop.params.misc;
            const target: *u16 = state.registers.getU16(params.write_back);
            // Make sure to never overwrite the pseudo flags.
            const mask: u16 = if(params.write_back == .f) 0xFFF0 else 0xFFFF;
            target.* = (state.registers.r16.wz & mask) | (target.* & ~mask); 
            applyPins(state, mmu);
        },
        else => { 
            std.debug.print("CPU_MICRO_OP_NOT_IMPLEMENTED: {any}\n", .{uop});
            unreachable;
        },
    }
}

fn applyPins(state: *State, mmu: *MMU.State) void {
    if(mmu.request.read) |_| {
        state.dbus_target.* = mmu.request.data;
        mmu.request.read = null;
    }
}

fn pushPins(state: *State, mmu: *MMU.State, request: MemoryRequest) void {
    switch(request) {
        .read => {
            mmu.request.read = state.address_bus;
            mmu.request.write = null;
        },
        .write => {
            mmu.request.read = null;
            mmu.request.write = state.address_bus;
            mmu.request.data = state.dbus_source;
        },
        .none => {
            mmu.request.read = null;
            mmu.request.write = null;
        }
    }
}
