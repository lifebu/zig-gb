const std = @import("std");
const sf = struct {
    usingnamespace @import("sfml");
    usingnamespace sf.graphics;
};

const Self = @This();

// TODO: Maybe one function for all updates of the I/O systems?

pub fn updateJoypad(_: *Self, joyp: *u8) void {
    // 0 means pressed for gameboy => 0xF nothing is pressed
    var dpad: u4 = 0xF; 
    dpad &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.right))) << 0); // Right
    dpad &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.left))) << 1); // Left
    dpad &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.up))) << 2); // Up
    dpad &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.down))) << 3); // Down
    
    var buttons: u4 = 0xF;
    buttons &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.A))) << 0); // A
    buttons &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.D))) << 1); // B
    buttons &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.S))) << 2); // Select
    buttons &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.W))) << 3); // Start

    const selectDpad: bool = (joyp.* & 0x10) != 0x10;
    const selectButtons: bool = (joyp.* & 0x20) != 0x20;
    if(selectDpad and selectButtons)  { 
        joyp.* = (joyp.* & 0xF0) | (dpad & buttons); 
    } else if(selectDpad) { 
        joyp.* = (joyp.* & 0xF0) & dpad; 
    } else if(selectButtons) { 
        joyp.* = (joyp.* & 0xF0) & buttons; 
    } else { 
        joyp.* = (joyp.* & 0xF0) & 0x0F; 
    }
}

const TIMER_FREQ_TABLE = [4]u10{1024, 16, 64, 256};
// This Table defines by how much you need to increment the timer each step to trigger the overflow.
// TODO: This setup requires, that the timer counter is correctly set to aligned values, when you change the timer frequency. I don't think this will work?
const TIMER_INCREMENT_TABLE = [4]u10{ 1024 / 1024, 1024 / 16, 1024 / 64, 1024 / 256};

timerCounter: u10 = 0,
// 2^14 = 16.384Hz
dividerCounter: u14 = 0,
// TODO: This can alias, not good for the compiler. Better solution?
pub fn updateTimers(self: *Self, divider: *u8, timer: *u8, timerMod: u8, timerControl: u8) void {
    // TODO: Writing to the divider register will reset it.
    const DIVIDER_FREQ: u14 = 16_383;
    divider.* +%= @intCast(self.dividerCounter / DIVIDER_FREQ);
    self.dividerCounter +%= 1;

    // TODO: Can this be done branchless?
    const timerEnabled: bool = (timerControl & 0x4) == 0x4;
    if(timerEnabled) {
        const currentFreq = TIMER_FREQ_TABLE[timerControl & 0x3];
        timer.* += self.timerCounter / currentFreq;
        const currentIncrement = TIMER_INCREMENT_TABLE[timerControl & 0x3];
        self.timerCounter +%= currentIncrement;
        // TODO: How to set when it overflows to the module value?
        timerMod += 1;
    }
}
