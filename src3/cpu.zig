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
    c,
    b,
    e,
    d,
    l,
    h,
    z,
    w,
    pcl,
    pch,
    spl,
    sph,
    ir,
    dbus,
    alu_input_1,
    a,
};

const longest_instruction_cycles = 24;

const MicroOp = enum(u6) {
    unused,
    // General
    decode,
    apply_pins,
    halt,
    nop,
    addr_idu, 
    dbus,
    stop,
    // ALU
    alu_set_inputs,
    alu_adc, 
    alu_add, 
    alu_and, 
    alu_assign, 
    alu_bit,
    alu_ccf, 
    alu_cp, 
    alu_daa_adjust, 
    alu_dec, 
    alu_inc, 
    alu_not,
    alu_or, 
    alu_res, 
    alu_rl, 
    alu_rlc, 
    alu_rr, 
    alu_rrc, 
    alu_sbc, 
    alu_scf, 
    alu_set,
    alu_sl, 
    alu_sr, 
    alu_srl, 
    alu_sub, 
    alu_swap, 
    alu_xor, 
    // Misc
    change_ime,
    conditional_check,
    set_pc,
    wz_writeback,
};

const AddrIduParms = packed struct(u12) {
    addr: RegisterFileID,  
    low_offset: bool,
    idu: i2,
    _: u5 = 0, 
};
const DBusParams = packed struct(u12) {
    source: RegisterFileID,
    target: RegisterFileID,
    _: u4 = 0,
};
const AluParams = packed struct(u12) {
    input_1: RegisterFileID,
    input_2: packed union {
        rfid: RegisterFileID,
        value: u4,
    },
    output: RegisterFileID,
};
const DecodeParams = packed struct(u12) {
    bank_idx: u2 = opcode_bank_default,
    _: u10 = 0,
};
// TODO: Is this the best way to implement this?
const ConditionCheck = enum(u2) {
    not_zero,
    zero,
    not_carry,
    carry,
};
const MiscParams = packed struct(u12) {
    write_back: RegisterFileID = .a,
    ime_value: bool = false,
    rst_offset: u3 = 0,
    cc: ConditionCheck = .not_zero,
    _: u2 = 0,
};
const rst_addresses = [8]u16{ 0x0000, 0x0008, 0x0010, 0x018, 0x020, 0x028, 0x030, 0x038 };
const MicroOpData = struct {
    operation: MicroOp,
    params: union(enum) {
        none,
        addr_idu: AddrIduParms,
        dbus: DBusParams,
        alu: AluParams,
        misc: MiscParams,
        decode: DecodeParams,
    },
};
const MicroOpFifo = Fifo.RingbufferFifo(MicroOpData, longest_instruction_cycles);
const MicroOpArray = std.BoundedArray(MicroOpData, longest_instruction_cycles);

// TODO: IN general add more sanity checks and asserts.
fn AddrIdu(addr: RegisterFileID, idu: i2, low_offset: bool) MicroOpData {
    // TODO: Maybe add a sanity check here to see if the addr rfid is a valid 16-bit register? Because you could read 16bit between two 16bit registers.
    return .{ .operation = .addr_idu, .params = .{ .addr_idu = AddrIduParms{ .addr = addr, .idu = idu, .low_offset = low_offset } } };
}
fn Alu(func: MicroOp, input_1: RegisterFileID, input_2: RegisterFileID, output: RegisterFileID) MicroOpData {
    return .{ .operation = func, .params = .{ .alu = AluParams{ .input_1 = input_1, .input_2 = .{ .rfid = input_2 }, .output = output } } };
}
fn AluValue(func: MicroOp, input_1: RegisterFileID, input_2: u4, output: RegisterFileID) MicroOpData {
    return .{ .operation = func, .params = .{ .alu = AluParams{ .input_1 = input_1, .input_2 = .{ .value = input_2 }, .output = output } } };
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
    return .{ .operation = .wz_writeback, .params = .{ .misc = MiscParams{ .cc = cc } } };
}
fn MiscRST(rst_offset: u3) MicroOpData {
    return .{ .operation = .wz_writeback, .params = .{ .misc = MiscParams{ .rst_offset = rst_offset } } };
}
fn MiscIME(ime: bool) MicroOpData {
    return .{ .operation = .wz_writeback, .params = .{ .misc = MiscParams{ .ime_value = ime } } };
}
fn Nop() MicroOpData {
    return .{ .operation = .nop, .params = .none };
}

pub const opcode_bank_default = 0;
pub const opcode_bank_prefix = 1;
// 0x76 = HALT, 0x10 = STOP, 0x00-0x04: Interrupt Handler
pub const opcode_bank_pseudo = 2;
pub const num_opcode_banks = 3;
pub const num_opcodes = 256;
// TODO: Would be nicer to create this immediately instead of creating a function, but like this it is easier to implement the instructions in any order.
fn genOpcodeBanks() [num_opcode_banks][num_opcodes]MicroOpArray {
    // TODO: Consider doing this on inizialization and not during compile time?
    @setEvalBranchQuota(5000);
    var returnVal: [num_opcode_banks][num_opcodes]MicroOpArray = undefined;
    @memset(&returnVal, [_]MicroOpArray{.{}} ** num_opcodes);
    
    // TODO: I think I have to switch ALU/MISC with DBUS + Push Pins. Why? Set ,b [HL] requires that the output of the ALU can be used for this cycles memory request.
    // This also means before we decode, we need to apply the pins, because Decode requires that the pins have been applied before decode runs.
    // But then Again some instructions might need read result immediate as ALU input.
    // So the order of DBUS and ALU can be switched depending on the need?
    // 0: ADDR + IDU 
    // 1: DBUS + Push Pins
    // 2: ALU/MISC + Apply Pins
    // 3: DECODE
    var curr_opcode: u8 = 0;

    // NOP
    returnVal[opcode_bank_default][0x00].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD r16, imm16
    curr_opcode = 0x01;
    const ld_r16_imm_rfids = [_]RegisterFileID{ .c, .e, .l, .spl }; 
    for (ld_r16_imm_rfids) |rfid| {
        returnVal[opcode_bank_default][curr_opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(.pcl, 1, false), Dbus(.dbus, .z),  ApplyPins(),  Nop(),
            AddrIdu(.pcl, 1, false), Dbus(.dbus, .w),  ApplyPins(),  Nop(),
            AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), MiscWB(rfid), Decode(opcode_bank_default),
        }) catch unreachable;
        curr_opcode += 0x10;
    }

    // LD r16mem, a
    curr_opcode = 0x02;
    const ld_r16mem_a_rfids = [_]RegisterFileID{ .c, .e, .l, .l }; 
    const ld_r16mem_a_idu = [_]i2{ 0, 0, 1, -1 }; 
    for(ld_r16mem_a_rfids, ld_r16mem_a_idu) |rfid, idu| {
        returnVal[opcode_bank_default][curr_opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(rfid, idu, false), Dbus(.dbus, .z),  ApplyPins(),                  Nop(),
            AddrIdu(.pcl, 1, false),   Dbus(.dbus, .ir), Alu(.alu_assign, .z, .z, .a), Decode(opcode_bank_default),
        }) catch unreachable;
        curr_opcode += 0x10;
    }

    // Inc r16
    curr_opcode = 0x03;
    const inc_r16_rfids = [_]RegisterFileID{ .c, .e, .l, .spl }; 
    for(inc_r16_rfids) |rfid| {
        returnVal[opcode_bank_default][curr_opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(rfid, 1, false), Nop(),            Nop(), Nop(),
            AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
        }) catch unreachable;
        curr_opcode += 0x10;
    }

    // INC r8
    const inc_r8_opcodes = [_]u8{ 0x04, 0x14, 0x24, 0x34, 0x0C, 0x1C, 0x2C, 0x3C };
    // TODO: Missing the [HL] Variant (0x34)
    const inc_r8_rfids = [_]RegisterFileID{ .b, .d, .h, .l, .c, .e, .l, .a  }; 
    for(inc_r8_opcodes, inc_r8_rfids) |opcode, rfid| {
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), Alu(.alu_inc, rfid, rfid, rfid), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // DEC r8
    const dec_r8_opcodes = [_]u8{ 0x05, 0x15, 0x25, 0x35, 0x0D, 0x1D, 0x2D, 0x3D };
    // TODO: Missing the [HL] Variant (0x34)
    const dec_r8_rfids = [_]RegisterFileID{ .b, .d, .h, .l, .c, .e, .l, .a  }; 
    for(dec_r8_opcodes, dec_r8_rfids) |opcode, rfid| {
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), Alu(.alu_dec, rfid, rfid, rfid), Decode(opcode_bank_default),
        }) catch unreachable;
    }

    // LD r8, imm8
    const ld_r8_imm8_opcodes = [_]u8{ 0x06, 0x16, 0x26, 0x36, 0x0E, 0x1E, 0x2E, 0x3E };
    // TODO: Missing the [HL] Variant (0x34)
    // TODO: Those rfids are the same for all of the variants of the same type. Define them once?
    const ld_r8_imm8_rfids = [_]RegisterFileID{ .b, .d, .h, .l, .c, .e, .l, .a  }; 
    for(ld_r8_imm8_opcodes, ld_r8_imm8_rfids) |opcode, rfid| {
        returnVal[opcode_bank_default][opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(.pcl, 1, false), Dbus(.dbus, .z),  ApplyPins(),                    Nop(),
            AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), Alu(.alu_assign, .z, .z, rfid), Decode(opcode_bank_prefix),
        }) catch unreachable;
    }

    // RLCA
    returnVal[opcode_bank_default][0x07].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), Alu(.alu_rlc, .a, .a, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD (imm16),SP
    returnVal[opcode_bank_default][0x08].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .z),   ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .w),   ApplyPins(), Nop(),
        AddrIdu(.z, 1, false),   Dbus(.dbus, .spl), ApplyPins(), Nop(),
        AddrIdu(.z, 0, false),   Dbus(.dbus, .sph), ApplyPins(), Nop(),
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir),  ApplyPins(), Decode(opcode_bank_default),
    }) catch unreachable;

    // LD a, r16mem
    returnVal[opcode_bank_default][0x09].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .z),   ApplyPins(),               Nop(),
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .w),   ApplyPins(),               Nop(),
        AddrIdu(.z, 0, false),   Dbus(.dbus, .z),   ApplyPins(),               Nop(),
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir),  Alu(.alu_set, .z, .z, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // DEC r16
    curr_opcode = 0x0B;
    // TODO: Define the variant rfid sets once and use the correct set instead of defining it everywhere.
    const dec_r16_rfids = [_]RegisterFileID{ .c, .e, .l, .spl }; 
    for(dec_r16_rfids) |rfid| {
        returnVal[opcode_bank_default][curr_opcode].appendSlice(&[_]MicroOpData{
            AddrIdu(rfid, -1, false), Nop(),           Nop(), Nop(),
            AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), Nop(), Decode(opcode_bank_default),
        }) catch unreachable;
        curr_opcode += 0x10;
    }

    // ADD HL, R16
    curr_opcode = 0x09;
    const add_hl_r16_rfids = [_]RegisterFileID{ .c, .e, .l, .spl }; 
    for(add_hl_r16_rfids) |rfid| {
        // TODO: Needs to be tested if this actually works.
        const r16_msb: RegisterFileID = @enumFromInt((@intFromEnum(rfid) + 1));
        returnVal[opcode_bank_default][curr_opcode].appendSlice(&[_]MicroOpData{
            // TODO: In gekkio it shows + and then +_c, so I think I need add and add+carry? Test this!
            Nop(), Nop(), Alu(.alu_add, .l, rfid, .l), Nop(),
            AddrIdu(.pcl, 1, false),   Dbus(.dbus, .ir), Alu(.alu_adc, .h, r16_msb, .h), Decode(opcode_bank_default),
        }) catch unreachable;
        curr_opcode += 0x10;
    }

    // RRCA
    returnVal[opcode_bank_default][0x0F].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), Alu(.alu_rrc, .a, .a, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // STOP
    returnVal[opcode_bank_default][0x10].appendSlice(&[_]MicroOpData{
        Nop(), Nop(), Nop(), Decode(opcode_bank_pseudo),
    }) catch unreachable;

    // RLA
    returnVal[opcode_bank_default][0x17].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), Alu(.alu_rl, .a, .a, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // JR r8
    // TODO: Missing JR r8, because I need to implement an adjust function for the IDU.
    // It increments or decrements the based on the 7th carry bit and the sign of the r8 (SIGNED!) value.

    // TODO: RRA, RLA, RRCA and so on are all extremly similar, combine their uops?
    // RRA
    returnVal[opcode_bank_default][0x1F].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), Alu(.alu_rr, .a, .a, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // JR cond imm8
    // TODO: Missing JR cond imm8, because I need to implement an adjust function for the IDU.
    // It increments or decrements the based on the 7th carry bit and the sign of the r8 (SIGNED!) value.

    // DAA
    returnVal[opcode_bank_default][0x27].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), Alu(.alu_daa_adjust, .a, .a, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // CPL
    returnVal[opcode_bank_default][0x2F].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), Alu(.alu_not, .a, .a, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // SCF
    returnVal[opcode_bank_default][0x37].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), Alu(.alu_scf, .a, .a, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // CCF
    returnVal[opcode_bank_default][0x37].appendSlice(&[_]MicroOpData{
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), Alu(.alu_ccf, .a, .a, .a), Decode(opcode_bank_default),
    }) catch unreachable;

    // Prefix
    returnVal[opcode_bank_default][0xCB].appendSlice(&[_]MicroOpData{ // prefix
        AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), ApplyPins(), Decode(opcode_bank_prefix),
    }) catch unreachable;



    // TODO: We don't have SLA and SRA. So what is the difference, do we need a new uop for this?
    const bit_shift_uops = [_]MicroOp{ .alu_rlc, .alu_rrc, .alu_rl, .alu_rr, .alu_sl, .alu_sr, .alu_swap, .alu_srl }; 
    curr_opcode = 0x00;
    for(bit_shift_uops) |bit_shift_uop| {
        // TODO: We are missing the Set bit, [HL] Variant instead of the second h.
        const rfid_variants = [_]RegisterFileID{ .b, .c, .d, .e, .h, .l, .h, .a };
        for(rfid_variants) |rfid| {
            returnVal[opcode_bank_prefix][curr_opcode].appendSlice(&[_]MicroOpData{
                AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), Alu(bit_shift_uop, rfid, rfid, rfid), Decode(opcode_bank_default),
            }) catch unreachable;
            curr_opcode += 1;
        }
    }

    const bit_uops = [_]MicroOp{ .alu_bit, .alu_res, .alu_set };  
    // TODO: This should not be necessary. It should be enough to start at 0x40 and iterate over all of them. But this has a bug, why?
    const bit_opcodes = [_]u8{ 0x40, 0x80, 0xC0 };
    for(bit_uops, 0..) |bit_uop, i| {
        var bit_opcode: u8 = bit_opcodes[i];
        for(0..7) |bit_index| {
            // TODO: We are missing the Set bit, [HL] Variant instead of the second h.
            const rfid_variants = [_]RegisterFileID{ .b, .c, .d, .e, .h, .l, .h, .a };
            for(rfid_variants) |rfid| {
                returnVal[opcode_bank_prefix][bit_opcode].appendSlice(&[_]MicroOpData{
                    AddrIdu(.pcl, 1, false), Dbus(.dbus, .ir), AluValue(bit_uop, rfid, bit_index, rfid), Decode(opcode_bank_default),
                }) catch unreachable;
                bit_opcode += 1;
            }
        }
    }
    return returnVal;
}
pub const opcode_banks = genOpcodeBanks();

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

const FlagRegister = packed union {
    f: u8,
    flags: packed struct {
        _: u4 = 0,
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
        c: u8 = 0,
        b: u8 = 0,
        e: u8 = 0,
        d: u8 = 0,
        l: u8 = 0,
        h: u8 = 0,
        z: u8 = 0,
        w: u8 = 0,
        pcl: u8 = 0,
        pch: u8 = 0,
        spl: u8 = 0,
        sph: u8 = 0,
        ir: u8 = 0,
        dbus: u8 = 0,
        f: FlagRegister = . { .f = 0 },
        a: u8 = 0,
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
};

const MemoryRequest = enum {
    none,
    read,
    write,
};

pub const State = struct {
    uop_fifo: MicroOpFifo = .{}, 

    registers: RegisterFile = .{ .r16 = .{} },
    address_bus: u16 = 0,
    dbus_source: *u8 = undefined,
    dbus_target: *u8 = undefined,

    interrupt_enable: InterruptFlags = .{},
    interrupt_master_enable: bool = false,
};

pub fn init(state: *State) void {
    const opcode_bank = opcode_banks[opcode_bank_default];
    const uops: MicroOpArray = opcode_bank[state.registers.r8.ir];
    state.uop_fifo.write(uops.slice());
}

pub fn cycle(state: *State, mmu: *MMU.State) void {
    const uop: MicroOpData = state.uop_fifo.readItem().?;
    switch(uop.operation) {
        // TODO: When and how does the cpu write the result of the memory request to it's dbus?
        .addr_idu => {
            const params: AddrIduParms = uop.params.addr_idu;
            // TODO: Implement low_offset.
            const addr_source: *u16 = state.registers.getU16(params.addr);
            state.address_bus = addr_source.*;

            // +% -1 <=> +% 65535
            addr_source.* +%= @bitCast(@as(i16, params.idu));
            applyPins(state, mmu);
        },
        // TODO: Look at all the alu implementation and see where we can use some common changes and combine them to make the code clearer and more concise.
        // TODO: Look at all of the uops and see if we can combine them. Examples
        // - Inc and Dec can be expressed the same: -1 <=> +% 255
        // - Can ADD and ADC as well as SUB and SBC be combined?
        // - Can we express add and sub the same: -n <=> +% (256 - n)
        // - AND, OR, XOR are the same code. The only thing that changes is the actual operation.
        // - Is RLC with C = 0 the same as RL? (Same for RRC with C = 0 and RR). 
        // - Can we combine sr and srl?
        .alu_adc => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const a: u8 = state.registers.r8.a;
            const carry: u8 = @intFromBool(state.registers.r8.f.flags.carry);
            const input_carry, const carry_overflow = @addWithOverflow(input, carry);
            const result, const overflow = @addWithOverflow(a, input_carry);
            
            state.registers.r8.f.flags.zero = result == 0;
            state.registers.r8.f.flags.n_bcd = false;
            const input_hbcd: bool = (((input & 0x0F) +% (carry & 0x0F)) & 0x10) == 0x10;
            const input_carry_hbcd: bool = (((a & 0x0F) +% (input_carry & 0x0F)) & 0x10) == 0x10;
            state.registers.r8.f.flags.half_bcd = input_hbcd or input_carry_hbcd;
            state.registers.r8.f.flags.carry = carry_overflow == 1 or overflow == 1;

            state.registers.r8.a = result;
            applyPins(state, mmu);
        },
        .alu_add => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const a: u8 = state.registers.r8.a;
            const result, const overflow = @addWithOverflow(a, input);

            state.registers.r8.f.flags.zero = result == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = ((a & 0x0F) +% (input & 0x0F)) > 0x0F;
            state.registers.r8.f.flags.carry = overflow == 1;

            state.registers.r8.a = result;
            applyPins(state, mmu);
        },
        .alu_and => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            state.registers.r8.a &= input;

            state.registers.r8.f.flags.zero = state.registers.r8.a == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = true;
            state.registers.r8.f.flags.carry = false;
            applyPins(state, mmu);
        },
        .alu_assign => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const output: *u8 = state.registers.getU8(params.output);
            output.* = input;
            applyPins(state, mmu);
        },
        .alu_bit => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const bit_index: u3 = @intCast(params.input_2.value); 
            const result: u8 = input & (@as(u8, 1) << bit_index);
            const output: *u8 = state.registers.getU8(params.output);
            output.* = result;

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
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const a: u8 = state.registers.r8.a;
            _, const overflow = @subWithOverflow(a, input);

            state.registers.r8.f.flags.zero = a == 0;
            state.registers.r8.f.flags.n_bcd = true;
            state.registers.r8.f.flags.half_bcd = (((a & 0x0F) -% (input & 0x0F)) & 0x10) == 0x10;
            state.registers.r8.f.flags.carry = overflow == 1;
            applyPins(state, mmu);
        },
        .alu_daa_adjust => {
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
        .alu_dec => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const output: *u8 = state.registers.getU8(params.output);
            output.* -%= 1;

            state.registers.r8.f.flags.zero = output.* == 0;
            state.registers.r8.f.flags.n_bcd = true;
            state.registers.r8.f.flags.half_bcd = (((input & 0x0F) -% 1) & 0x10) == 0x10; 
            applyPins(state, mmu);
        },
        .alu_inc => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const output: *u8 = state.registers.getU8(params.output);
            output.* = input +% 1;

            // TODO: Maybe we create a more compact way to change the flags? Like a function?
            state.registers.r8.f.flags.zero = output.* == 0; 
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = (((input & 0x0F) +% 1) & 0x10) == 0x10; 
            applyPins(state, mmu);
        },
        .alu_not => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const result: u8 = ~input;
            const output: *u8 = state.registers.getU8(params.output);
            output.* = result;

            state.registers.r8.f.flags.n_bcd = true;
            state.registers.r8.f.flags.half_bcd = true;
            applyPins(state, mmu);
        },
        .alu_or => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            state.registers.r8.a |= input;

            state.registers.r8.f.flags.zero = state.registers.r8.a == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            state.registers.r8.f.flags.carry = false;
            applyPins(state, mmu);
        }, 
        .alu_res => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const bit_index: u3 = @intCast(params.input_2.value); 
            const result: u8 = input & ~(@as(u8, 1) << bit_index);
            const output: *u8 = state.registers.getU8(params.output);
            output.* = result;
            applyPins(state, mmu);
        }, 
        .alu_rl => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const shifted_bit: bool = (input & 0x80) == 0x80;
            const carry: u8 = @intFromBool(state.registers.r8.f.flags.carry);
            const result: u8 = (input << 1) | carry;
            const output: *u8 = state.registers.getU8(params.output);
            output.* = result;

            state.registers.r8.f.flags.carry = shifted_bit;
            state.registers.r8.f.flags.zero = result == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            applyPins(state, mmu);
        }, 
        .alu_rlc => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const shifted_bit: u8 = input & 0x80;
            const result: u8 = (input << 1) | (shifted_bit >> 7);
            const output: *u8 = state.registers.getU8(params.output);
            output.* = result;

            state.registers.r8.f.flags.carry = shifted_bit == 0x80;
            state.registers.r8.f.flags.zero = result == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            applyPins(state, mmu);
        },
        .alu_rr => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const shifted_bit: bool = (input & 0x01) == 0x01;
            const carry: u8 = @intFromBool(state.registers.r8.f.flags.carry);
            const result: u8 = (input >> 1) | (carry << 7);
            const output: *u8 = state.registers.getU8(params.output);
            output.* = result;

            state.registers.r8.f.flags.carry = shifted_bit;
            state.registers.r8.f.flags.zero = result == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            applyPins(state, mmu);
        },
        .alu_rrc => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const shifted_bit: u8 = (input & 0x01);
            const result: u8 = (input >> 1) | (shifted_bit << 7);
            const output: *u8 = state.registers.getU8(params.output);
            output.* = result;

            state.registers.r8.f.flags.carry = shifted_bit == 1;
            state.registers.r8.f.flags.zero = result == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            applyPins(state, mmu);
        },
        .alu_sbc => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const carry: u8 = @intFromBool(state.registers.r8.f.flags.carry);
            const input_carry, const carry_overflow = @addWithOverflow(input, carry);
            const a: u8 = state.registers.r8.a;
            const result, const overflow = @subWithOverflow(a, input_carry);

            state.registers.r8.f.flags.carry = carry_overflow == 1 or overflow == 1;
            state.registers.r8.f.flags.zero = result == 0;
            state.registers.r8.f.flags.n_bcd = true;
            const input_hbcd: bool = (((input & 0x0F) +% (carry & 0x0F)) & 0x10) == 0x10;
            const input_cary_hbcd: bool = (((a & 0x0F) -% (input_carry & 0x0F)) & 0x10) == 0x10;
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
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const bit_index: u3 = @intCast(params.input_2.value); 
            const result: u8 = input | (@as(u8, 1) << bit_index);
            const output: *u8 = state.registers.getU8(params.output);
            output.* = result;
            applyPins(state, mmu);
        },
        .alu_sl => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const shifted_bit: bool = (input & 0x80) == 0x80;
            const result: u8 = input << 1;
            const output: *u8 = state.registers.getU8(params.output);
            output.* = result;

            state.registers.r8.f.flags.carry = shifted_bit;
            state.registers.r8.f.flags.zero = input == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            applyPins(state, mmu);
        }, 
        .alu_sr => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const shifted_bit: bool = (input & 0x01) == 0x01;
            const result: u8 = (input >> 1) | (input & 0x80);
            const output: *u8 = state.registers.getU8(params.output);
            output.* = result;

            state.registers.r8.f.flags.carry = shifted_bit;
            state.registers.r8.f.flags.zero = input == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            applyPins(state, mmu);
        },
        .alu_srl => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const shifted_bit: bool = (input & 0x01) == 0x01;
            const result: u8 = (input >> 1);
            const output: *u8 = state.registers.getU8(params.output);
            output.* = result;

            state.registers.r8.f.flags.carry = shifted_bit;
            state.registers.r8.f.flags.zero = input == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            applyPins(state, mmu);
        }, 
        .alu_sub => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const a: u8 = state.registers.r8.a;
            const result, const overflow = @subWithOverflow(a, input);

            state.registers.r8.f.flags.zero = result == 0;
            state.registers.r8.f.flags.n_bcd = true;
            state.registers.r8.f.flags.half_bcd = (((a & 0x0F) -% (input & 0x0F)) & 0x10) == 0x10;
            state.registers.r8.f.flags.carry = overflow == 1;

            state.registers.r8.a = result;
            applyPins(state, mmu);
        }, 
        .alu_swap => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            const result = (input << 4) | (input >> 4);
            const output: *u8 = state.registers.getU8(params.output);
            output.* = result;

            state.registers.r8.f.flags.carry = false;
            state.registers.r8.f.flags.zero = result == 0;
            state.registers.r8.f.flags.n_bcd = false;
            state.registers.r8.f.flags.half_bcd = false;
            applyPins(state, mmu);
        },
        .alu_xor => {
            const params: AluParams = uop.params.alu;
            const input: u8 = state.registers.getU8(params.input_1).*;
            state.registers.r8.a ^= input;

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
            const flag: bool = switch(params.cc) {
                .not_zero => !state.registers.r8.f.flags.zero,
                .zero => state.registers.r8.f.flags.zero,
                .not_carry => !state.registers.r8.f.flags.carry,
                .carry => state.registers.r8.f.flags.carry,
            };
            if(flag) {}
            // TODO: Need to think about how we need to implement the CC. 
            // If true we keep the rest of the uops.
            // If false we load the next instruction?
            applyPins(state, mmu);
        },
        .dbus => {
            const params: DBusParams = uop.params.dbus;
            state.dbus_source = state.registers.getU8(params.source);
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
        },
        .nop => {
        },
        .set_pc => {
            const params: MiscParams = uop.params.misc;
            const new_pc: u16 = rst_addresses[params.rst_offset];
            state.registers.r16.pc = new_pc;
            applyPins(state, mmu);
        },
        .wz_writeback => {
            const params: MiscParams = uop.params.misc;
            const input: u16 = state.registers.getU16(params.write_back).*;
            state.registers.r16.wz = input; 
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
            mmu.request.data = state.registers.r8.dbus;
        },
        .none => {
            mmu.request.read = null;
            mmu.request.write = null;
        }
    }
}
