const std = @import("std");

const Def = @import("def.zig");
const MMU = @import("mmu.zig");
const MemMap = @import("mem_map.zig");

const Self = @This();

// Used to trigger interrupts from high->low transitions.
lastDpadState: u4 = 0xF,
lastButtonState: u4 = 0xF,

timerCounter: u10 = 0,
// 2^14 = 16.384Hz
dividerCounter: u14 = 0,
// TODO: Testing, remove this!
interruptFlag: u8 = 0,

pub fn updateJoypad(self: *Self, mmu: *MMU, inputState: Def.InputState) void {
    // 0 means pressed for gameboy => 0xF nothing is pressed
    var dpad: u4 = 0xF; 
    dpad &= ~(@as(u4, @intFromBool(inputState.isRightPressed)) << 0);
    dpad &= ~(@as(u4, @intFromBool(inputState.isLeftPressed)) << 1);
    dpad &= ~(@as(u4, @intFromBool(inputState.isUpPressed)) << 2);
    dpad &= ~(@as(u4, @intFromBool(inputState.isDownPressed)) << 3);
    
    var buttons: u4 = 0xF;
    buttons &= ~(@as(u4, @intFromBool(inputState.isAPressed)) << 0);
    buttons &= ~(@as(u4, @intFromBool(inputState.isBPressed)) << 1);
    buttons &= ~(@as(u4, @intFromBool(inputState.isSelectPressed)) << 2);
    buttons &= ~(@as(u4, @intFromBool(inputState.isStartPressed)) << 3);

    var joyp: u8 = mmu.read8(MemMap.JOYPAD); 
    const selectDpad: bool = (joyp & 0x10) != 0x10;
    const selectButtons: bool = (joyp & 0x20) != 0x20;
    if(selectDpad and selectButtons)  { 
        joyp = (joyp & 0xF0) | (dpad & buttons); 
    } else if(selectDpad) { 
        joyp = (joyp & 0xF0) & dpad; 
    } else if(selectButtons) { 
        joyp = (joyp & 0xF0) & buttons; 
    } else { 
        joyp = (joyp & 0xF0) & 0x0F; 
    }
    mmu.write8(MemMap.JOYPAD, joyp);

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

pub fn updateTimers(self: *Self, mmu: *MMU) void {
    const rawMemory: *[]u8 = mmu.getRaw();
    const divider: *u8 = &rawMemory.*[MemMap.DIVIDER];
    const timer: *u8 = &rawMemory.*[MemMap.TIMER];
    const timerMod: u8 = mmu.read8(MemMap.TIMER_MOD); 
    const timerControl: u8 = mmu.read8(MemMap.TIMER_CONTROL); 

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
    // The actual routine lives in a range of memory that is usually inacessible by the gameboy (unused or echo ram).
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
