const std = @import("std");
const assert = std.debug.assert;

const def = @import("defines.zig");
const Fifo = @import("util/fifo.zig");
const mem_map = @import("mem_map.zig");
const MMU = @import("mmu.zig");

// Note: This assumes little-endian
const RegisterFileID = enum(u4) {
    c,
    b,
    d,
    e,
    h,
    l,
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

// TODO: Add when needed.
// TODO: Do I really want this?
pub const OpCodes = enum(u8) {
    nop = 0,
    ld_bc_imm16,
    ld_bc_mem_a,
    inc_bc,
    inc_b,
    dec_b,
    ld_b_imm8,
    rlca,
    ld_imm16_mem_sp,
    add_hl_bc,
    ld_a_bc_mem,
    dec_bc,
    inc_c,
    dec_c,
    ld_c_imm8,
    rrca,
};

const MicroOp = enum(u6) {
    unused,
    // General
    decode,
    apply_pins,
    push_pins,
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
    idu: u2,
    _: u5 = 0, 
};
const DBusParams = packed struct(u12) {
    source: RegisterFileID,
    target: RegisterFileID,
    _: u4 = 0,
};
const AluParams = packed struct(u12) {
    input_1: RegisterFileID,
    input_2: RegisterFileID,
    output: RegisterFileID,
};
const DecodeParams = packed struct(u12) {
    bank_idx: u2,
    _: u10 = 0,
};
const MicroOpData = struct {
    operation: MicroOp,
    params: union(enum) {
        none,
        addr_idu: AddrIduParms,
        dbus: DBusParams,
        alu: AluParams,
        decode: DecodeParams,
    },
};
const MicroOpFifo = Fifo.RingbufferFifo(MicroOpData, longest_instruction_cycles);
const MicroOpArray = std.BoundedArray(MicroOpData, longest_instruction_cycles);

pub const opcode_bank_default = 0;
pub const opcode_bank_prefix = 1;
// 0x76 = HALT, 0x10 = STOP, 0x00-0x04: Interrupt Handler
pub const opcode_bank_pseudo = 2;
pub const num_opcode_banks = 3;
pub const num_opcodes = 256;
// TODO: Would be nicer to create this immediately instead of creating a function, but like this it is easier to implement the instructions in any order.
fn createOpcodeBanks() [num_opcode_banks][num_opcodes]MicroOpArray {
    var returnVal: [num_opcode_banks][num_opcodes]MicroOpArray = undefined;
    @memset(&returnVal, [_]MicroOpArray{.{}} ** num_opcodes);
    
    // 0: ADDR + IDU 
    // 1: DBUS + Push Pins
    // 2: ALU/MISC + Apply Pins
    // 3: DECODE
    returnVal[opcode_bank_default][@intFromEnum(OpCodes.nop)].appendSlice(&[_]MicroOpData{
        .{ .operation = .addr_idu, .params = .{ .addr_idu = AddrIduParms{ .addr = .pcl, .idu = 1, .low_offset =  false, }} },
        .{ .operation = .dbus, .params = .{ .dbus = DBusParams{ .source = .dbus, .target = .ir }} },
        .{ .operation = .apply_pins, .params = .none },
        .{ .operation = .decode, .params = .{ .decode = DecodeParams{ .bank_idx = 0 }} },
    }) catch unreachable;

    return returnVal;
}
pub const opcode_banks = createOpcodeBanks();

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
            addr_source.* += params.idu;
        },
        .apply_pins => {
            if(mmu.request.read) |_| {
                state.dbus_target.* = mmu.request.data;
                mmu.request.read = null;
            }
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
        else => { 
            std.debug.print("CPU_MICRO_OP_NOT_IMPLEMENTED: {any}\n", .{uop});
            unreachable;
        },
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
