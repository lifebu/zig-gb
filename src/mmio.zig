const std = @import("std");
const sf = struct {
    usingnamespace @import("sfml");
    usingnamespace sf.graphics;
};

const Self = @This();

// Used to trigger interrupts from high->low transitions.
lastDpadState: u4 = 0xF,
lastButtonState: u4 = 0xF,

timerCounter: u10 = 0,
// 2^14 = 16.384Hz
dividerCounter: u14 = 0,
// TODO: Testing, remove this!
interruptFlag: u8 = 0,

pub fn updateJoypad(self: *Self, joyp: *u8) void {
    // 0 means pressed for gameboy => 0xF nothing is pressed
    var dpad: u4 = 0xF; 
    // TODO: Would be good to remove sfml dependency from inside the emulator, fine for now.
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

    // TODO: Can we do this branchless?
    // Interrupts
    if (self.lastDpadState < dpad or self.lastButtonState < buttons) {
        self.requestInterrupt(.JOYPAD);
    }
    self.lastDpadState = dpad;
    self.lastButtonState = buttons;
}

const TIMER_FREQ_TABLE = [4]u10{1023, 16, 64, 256};
const TIMER_INCR_TABLE = [4]u10{ 1023 / 1023, 1023 / 16, 1023 / 64, 1023 / 256};

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
        timer.* += @intCast(self.timerCounter / currentFreq);
        const currentIncrement = TIMER_INCR_TABLE[timerControl & 0x3];
        var overflow: u1 = 0;
        self.timerCounter, overflow = @addWithOverflow(self.timerCounter, currentIncrement);
        if(overflow == 1) {
            self.requestInterrupt(.TIMER);
            self.timerCounter = timerMod;
        }
    }
}

// TODO: Interrupt Handler.
    // Reset IME and corresponding bit in IF.
    // Wait 8 cycles.
    // Push PC register onto stack: 8 cycles
    // Set PC to the address of the handler: 4 Cycle.  
    //https://gist.github.com/SonoSooS/c0055300670d678b5ae8433e20bea595#user-content-isr-and-nmi
// TODO: Multiple interrupts: service them in the order of the bits ascending (Vblank first, Joypad last).
// TODO: Where should interrupts live? They do execute special instructions, so they are like a program the CPU executes.
    // But I don't like that requesting interrupts requires access to the CPU. It feels better to have this system handled here.
    // Unless the Interrupt Handler (20 Cycles of work for CPU) and Requester is split (also meh). 
// TODO: Where does the interrupt handler code live?
    // It cannot be a set of instructions the cpu executes where we need to jump to it. We need to save the program counter in the interrupt handler.
    // Maybe we can "memory map" the interrupt handler to the current programm counter position?
    // If we have an MMU system it would be able to "overlay" the interrupt handler code anywhere, where the cpu currently exists.
    // I mean I already require this behaviour for the BootROM? 
// Interrupts
pub const InterruptTypes = enum(u5) {
    VBLANK      = 0x01,
    LCD         = 0x02,
    TIMER       = 0x04,
    SERIAL      = 0x08,
    JOYPAD      = 0x10,
};
// TODO: Given how simple this function is, can I remove it? Requires memory access. Who owns the memory anyway? a MMU?
pub fn requestInterrupt(self: *Self, interruptType: InterruptTypes) void {
    // TODO: This requires access to the memory or at least the byte for the Interrupt Flag: (xFF0F):wa
    self.interruptFlag |= @intFromEnum(interruptType);
}
