const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");
const MMU = @import("mmu.zig");

pub const State = struct {
    // last bit we tested for timer (used to detect falling edge).
    // TODO: Don't like how this works honestly.
    timer_last_bit: bool = false,
    // TODO: Default value is default value after dmg, for other boot roms I need other values.
    system_counter: u16 = 0xAB00,
};

const timer_mask_table = [4]u10{ 1024 / 2, 16 / 2, 64 / 2, 256 / 2 };
// TODO: Maybe just mask of the bits?
const TimerControl = packed struct(u8) {
    clock: u2,
    enable: bool,
    _: u5,
};

pub fn init(_: *State) void {

}

pub fn cycle(state: *State, mmu: *MMU.State) void {
    var timer: u8 = mmu.memory[mem_map.timer];
    const timer_control: TimerControl = @bitCast(mmu.memory[mem_map.timer_control]);

    state.system_counter +%= 1;
    // GB only sees high 8 bit => divider increments every 256 cycles. 
    mmu.memory[mem_map.divider] = @intCast(state.system_counter >> 8);

    const mask = timer_mask_table[timer_control.clock];
    const bit: bool = ((state.system_counter & mask) == mask) and timer_control.enable;
    // Can happen when timer_last_bit is true and timer_control.enable was set to false this frame (intended GB behavior). 
    const timer_falling_edge: bool = !bit and state.timer_last_bit;
    timer, const overflow = @addWithOverflow(timer, @intFromBool(timer_falling_edge));
    // TODO: Branchless?
    if(overflow == 1) {
        // TODO: After overflowing, it takes 4 cycles before the interrupt flag is set and the value from timer_mod is used.
        // During that time, timer stays 0.
        // If the cpu writes to timer during the 4 cycles, these two steps will be skipped. 
        // If cpu writes to timer on the cycle that timer is set by the overflow, the cpu write will be overwritten.
        // If cpu writes to timer_mod on the cycle that timer is set by the overflow, the overflow uses the new timer_mod.
        mmu.memory[mem_map.interrupt_flag] |= mem_map.interrupt_timer;
        timer = mmu.memory[mem_map.timer_mod];
    }
    mmu.memory[mem_map.timer] = timer;

    state.timer_last_bit = bit;
}

pub fn memory(state: *State, mmu: *MMU.State, request: *def.MemoryRequest) void {
    // TODO: Need a better way to communicate memory ready and requests so that other systems like the dma don't need to know the mmu.
    // And split the on-write behavior and memory request handling from the cycle function?
    if(request.write) |address| {
        if(address == mem_map.divider) {
            state.system_counter = 0;

            mmu.memory[address] = 0;
            request.write = null;
        }
    }
}
