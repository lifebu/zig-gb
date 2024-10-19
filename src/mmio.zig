const std = @import("std");
const sf = struct {
    usingnamespace @import("sfml");
    usingnamespace sf.graphics;
};

pub fn updateJoypad(joyp: *u8) void {
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
