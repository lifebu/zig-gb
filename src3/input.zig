const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");
// TODO: Remove that dependency.
const MMU = @import("mmu.zig");

pub const State = struct {
    joypad: u8 = 0xFF,

    dpad: u4 = 0xF,
    buttons: u4 = 0xF,
};

pub fn init(_: *State) void {
}

pub fn cycle(_: *State) void {

}

pub fn request(state: *State, bus: *def.Bus) void {
    if(bus.read) |address| {
        switch (address) {
            mem_map.joypad => {
                bus.data.* = state.joypad;
                bus.read = null;
            },
            else => {},
        }
    }
    else if(bus.write) |address| {
        switch (address) {
            mem_map.joypad => {
                const joyp = (bus.data.* & 0xF0) | (state.joypad & 0x0F);
                const select_dpad: bool = (joyp & 0x10) != 0x10;
                const select_buttons: bool = (joyp & 0x20) != 0x20;
                const nibble: u4 = 
                    if(select_dpad and select_buttons) state.dpad & state.buttons 
                    else if (select_dpad) state.dpad 
                    else if (select_buttons) state.buttons
                    else 0x0F;

                state.joypad = (joyp & 0xF0) | nibble; 
                bus.write = null;
            },
            else => {},
        }
    }
}

pub fn updateInputState(state: *State, mmu: *MMU.State, input_state: *const def.InputState) void {
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
    // TODO: Can we do this without an if statement? creating u1 and shifting it up?
    if (state.dpad < last_dpad or state.buttons < last_buttons) {
        mmu.memory[mem_map.interrupt_flag] |= mem_map.interrupt_joypad;
    }
}
