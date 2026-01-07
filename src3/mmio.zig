const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

const timer_mask_table = [4]u10{ 1024 / 2, 16 / 2, 64 / 2, 256 / 2 };
pub const TimerControl = packed struct(u8) {
    clock: u2 = 0,
    enable: bool = false,
    _: u5 = 0,
};

pub const SerialControl = packed struct(u8) {
    is_master_clock: bool = true,
    use_high_speed: bool = false,
    _: u5 = 0,
    transfer_enable: bool = false,
};

pub const State = struct {
    // joypad
    dpad: u4 = 0xF,
    buttons: u4 = 0xF,

    joypad: u8 = 0xFF,

    // timer
    // TODO: Try to simplify this.
    timer_last_bit: bool = false,
    overflow_detected: bool = false,
    overflow_tick: u2 = 0,
    system_counter: u16 = 0,

    divider: u8 = 0,
    timer: u8 = 0,
    timer_control: TimerControl = .{},
    timer_mod: u8 = 0,

    // serial
    serial_data: u8 = 0xFF,
    serial_control: SerialControl = .{},
};

pub fn init(state: *State) void {
    state.* = .{};
}

pub fn cycle(state: *State) struct{ bool, bool } {
    const irq_serial: bool = cycleSerial(state);
    const irq_timer: bool = cycleTimer(state);
    return .{ irq_serial, irq_timer };
}

fn cycleSerial(_: *State) bool {
    const irq_serial: bool = false;
    return irq_serial;
}

fn cycleTimer(state: *State) bool {
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
        mem_map.joypad => {
            var value: u8 = state.joypad;
            req.apply(&value);
            if(req.isWrite()) {
                state.joypad = createJoypad(state, value);
            }
        },
        mem_map.serial_control => {
            req.apply(&state.serial_control);
        },
        mem_map.serial_data => {
            req.apply(&state.serial_data);
        },
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

fn createJoypad(state: *State, value: u8) u8 {
    const joyp = (value & 0xF0) | (state.joypad & 0x0F);
    const select_dpad: bool = (joyp & 0x10) != 0x10;
    const select_buttons: bool = (joyp & 0x20) != 0x20;
    const nibble: u4 = 
    if(select_dpad and select_buttons) state.dpad & state.buttons 
        else if (select_dpad) state.dpad 
            else if (select_buttons) state.buttons
                else 0x0F;

    return (joyp & 0xF0) | nibble; 
} 

pub fn updateInputState(state: *State, input_state: *const def.InputState) bool {
    const last_dpad: u4 = state.dpad;
    const last_buttons: u4 = state.buttons;

    // TODO: Could we implement this better to make this more mathematical with the input state we have?
    state.dpad = 0xF; 
    // disable physically impossible inputs: Left and Right, Up and Down
    state.dpad &= ~(@as(u4, @intFromBool(input_state.right_pressed and !input_state.left_pressed)) << 0);
    state.dpad &= ~(@as(u4, @intFromBool(input_state.left_pressed and !input_state.right_pressed)) << 1);
    state.dpad &= ~(@as(u4, @intFromBool(input_state.up_pressed and !input_state.down_pressed)) << 2);
    state.dpad &= ~(@as(u4, @intFromBool(input_state.down_pressed and !input_state.up_pressed)) << 3);
    
    state.buttons = 0xF;
    state.buttons &= ~(@as(u4, @intFromBool(input_state.a_pressed)) << 0);
    state.buttons &= ~(@as(u4, @intFromBool(input_state.b_pressed)) << 1);
    state.buttons &= ~(@as(u4, @intFromBool(input_state.select_pressed)) << 2);
    state.buttons &= ~(@as(u4, @intFromBool(input_state.start_pressed)) << 3);

    // Interrupts
    return state.dpad < last_dpad or state.buttons < last_buttons;
}
