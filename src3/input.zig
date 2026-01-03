const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

pub const State = struct {
    joypad: u8 = 0xFF,

    dpad: u4 = 0xF,
    buttons: u4 = 0xF,
};

pub fn init(_: *State) void {
}

pub fn request(state: *State, req: *def.Request) void {
    switch (req.address) {
        mem_map.joypad => {
            var value: u8 = state.joypad;
            req.apply(&value);
            if(req.isWrite()) {
                const joyp = (value & 0xF0) | (state.joypad & 0x0F);
                const select_dpad: bool = (joyp & 0x10) != 0x10;
                const select_buttons: bool = (joyp & 0x20) != 0x20;
                const nibble: u4 = 
                    if(select_dpad and select_buttons) state.dpad & state.buttons 
                    else if (select_dpad) state.dpad 
                    else if (select_buttons) state.buttons
                    else 0x0F;

                state.joypad = (joyp & 0xF0) | nibble; 
            }
        },
        else => {},
    }
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
