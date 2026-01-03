const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

const timer_mask_table = [4]u10{ 1024 / 2, 16 / 2, 64 / 2, 256 / 2 };

const TimerControl = packed struct(u8) {
    clock: u2 = 0,
    enable: bool = false,
    _: u5 = 0,
};

pub const State = struct {
    // last bit we tested for timer (used to detect falling edge).
    // TODO: Don't like how this works honestly.
    timer_last_bit: bool = false,
    system_counter: u16 = 0,

    divider: u8 = 0,
    timer: u8 = 0,
    timer_control: TimerControl = .{},
    timer_mod: u8 = 0,
};

pub fn init(state: *State) void {
    state.* = .{};
}

pub fn cycle(state: *State) bool {
    var irq_timer: bool = false;

    state.system_counter +%= 1;
    state.divider = @truncate(state.system_counter >> 8);

    const mask = timer_mask_table[state.timer_control.clock];
    const bit: bool = ((state.system_counter & mask) == mask) and state.timer_control.enable;
    // Can happen when timer_last_bit is true and timer_control.enable was set to false this frame (intended GB behavior). 
    const timer_falling_edge: bool = !bit and state.timer_last_bit;
    state.timer, const overflow = @addWithOverflow(state.timer, @intFromBool(timer_falling_edge));
    // TODO: Branchless?
    if(overflow == 1) {
        // TODO: After overflowing, it takes 4 cycles before the interrupt flag is set and the value from timer_mod is used.
        // During that time, timer stays 0.
        // If the cpu writes to timer during the 4 cycles, these two steps will be skipped. 
        // If cpu writes to timer on the cycle that timer is set by the overflow, the cpu write will be overwritten.
        // If cpu writes to timer_mod on the cycle that timer is set by the overflow, the overflow uses the new timer_mod.
        irq_timer = true;
        state.timer = state.timer_mod;
    }

    state.timer_last_bit = bit;
    return irq_timer;
}

pub fn request(state: *State, req: *def.Request) void {
    switch (req.address) {
        mem_map.divider => {
            req.apply(&state.divider);
            if(req.isWrite()) {
                state.system_counter = 0;
                state.divider = 0;
            }
        },
        mem_map.timer => {
            req.apply(&state.timer);
        },
        mem_map.timer_control => {
            req.apply(&state.timer_control);
        },
        mem_map.timer_mod => {
            req.apply(&state.timer_mod);
        },
        else => {},
    }
}
