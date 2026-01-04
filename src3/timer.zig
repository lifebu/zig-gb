const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

const timer_mask_table = [4]u10{ 1024 / 2, 16 / 2, 64 / 2, 256 / 2 };

pub const TimerControl = packed struct(u8) {
    clock: u2 = 0,
    enable: bool = false,
    _: u5 = 0,
};

pub const State = struct {
    // last bit we tested for timer (used to detect falling edge).
    // TODO: Try to simplify this.
    timer_last_bit: bool = false,
    overflow_detected: bool = false,
    overflow_tick: u2 = 0,
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
    state.timer, var overflow = @addWithOverflow(state.timer, @intFromBool(timer_falling_edge));
    // TODO: Branchless?
    if(overflow == 1 and state.overflow_detected == false) {
        state.overflow_detected = true;
        state.overflow_tick = 3;
    } else if(state.overflow_detected) {
        // TODO: The timing is exactly 4 cycles. Is this connected to reason for t-cycles and m-cycles?
        // The reason it is delayed is because the cpu can only read it 4 cycles later?
        state.overflow_tick, overflow = @subWithOverflow(state.overflow_tick, 1);
        if(overflow == 1) {
            state.overflow_detected = false;
            irq_timer = true;
            state.timer = state.timer_mod;
        }
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
            if(req.isWrite() and state.overflow_tick > 0) {
                state.overflow_detected = false;
            }
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
