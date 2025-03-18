const std = @import("std");
const assert = std.debug.assert;

const def = @import("defines.zig");
const Fifo = @import("util/fifo.zig");
const mem_map = @import("mem_map.zig");

const longest_instruction_cycles = 24;

const MicroOp = enum(u8) {
    unused,
    // General
    decode,
    halt,
    nop,
    set_addr_idu, 
    set_dbus,
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
// TODO: Super unsure how the different uops handle the 8bit I have for the parameters.
const DecodeParams = packed struct(u8) {
    instruction_register: bool = false,
    interrupt: bool = false,
    _: u6 = 0,

    pub fn toU8(self: DecodeParams) u8 {
        return @bitCast(self);
    }
    pub fn fromU8(value: u8) DecodeParams {
        return @bitCast(value);
    }
};

const MicroOpData = struct {
    operation: MicroOp,
    params: u8,
};
const MicroOpFifo = Fifo.RingbufferFifo(MicroOpData, longest_instruction_cycles);


const MicroOpArray = std.BoundedArray(MicroOpData, longest_instruction_cycles);
// TODO: Would be nicer to create this immediately instead of creating a function, but like this it is easier to implement the instructions in any order.
fn createInstructionSet() [256]MicroOpArray {
    var returnVal: [256]MicroOpArray = [_]MicroOpArray{.{}} ** 256;
    
    // TODO: Need to check my documentation if that is what I need to do.
    // ## Timing:
    // 0: ADDR => IDU 
    // 1: DBUS
    // 2: ALU/MISC
    // 3: DECODE
    returnVal[0].appendSlice(&[_]MicroOpData{
        MicroOpData{ .operation = .decode, .params = DecodeParams.toU8(.{ .instruction_register = true }) },
        MicroOpData{ .operation = .nop, .params = 0 },
        MicroOpData{ .operation = .nop, .params = 0 },
        MicroOpData{ .operation = .nop, .params = 0 },
    }) catch unreachable;

    return returnVal;
}
const instruction_set = createInstructionSet();

pub const State = struct {
    uop_fifo: MicroOpFifo = .{}, 
};

pub fn init(state: *State) void {
    state.uop_fifo.write(instruction_set[0].slice());
}

pub fn cycle(state: *State, _: *[def.addr_space]u8) void {
    const uop: MicroOpData = state.uop_fifo.readItem().?;
    switch(uop.operation) {
        .decode => {
            const decode_param: DecodeParams = DecodeParams.fromU8(uop.params);
            assert(decode_param.instruction_register);
            // TODO: When and how do we add new instructions to the uop_fifo? Extra decode operation? Add r8,r8 does not have a decode step?
            state.uop_fifo.write(instruction_set[0].slice());
        },
        .nop => {
        },
        else => { 
            std.debug.print("CPU_MICRO_OP_NOT_IMPLEMENTED: {any}\n", .{uop});
            unreachable;
        },
    }
}
