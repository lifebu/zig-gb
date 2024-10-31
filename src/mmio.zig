const std = @import("std");

const Def = @import("def.zig");
const MMU = @import("mmu.zig");
const MemMap = @import("mem_map.zig");

const Self = @This();

// Used to trigger interrupts from high->low transitions.
lastDpadState: u4 = 0xF,
lastButtonState: u4 = 0xF,

timerCounter: u16 = 0,
// 2^14 = 16.384Hz
dividerCounter: u14 = 0,

dmaIsRunning: bool = false,
dmaStartAddr: u16 = 0x0000,
dmaCurrentOffset: u16 = 0,

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
        joyp = (joyp & 0xF0) | dpad; 
    } else if(selectButtons) { 
        joyp = (joyp & 0xF0) | buttons; 
    } else { 
        joyp = (joyp & 0xF0) | 0x0F; 
    }
    mmu.write8(MemMap.JOYPAD, joyp);

    // TODO: Can we do this branchless?
    // Interrupts
    if (self.lastDpadState < dpad or self.lastButtonState < buttons) {
        mmu.setFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_JOYPAD);
    }
    self.lastDpadState = dpad;
    self.lastButtonState = buttons;
}

const TIMER_FREQ_TABLE = [4]u16{ 1024, 16, 64, 256 };
const TIMER_INCR_TABLE = [4]u8{ 1024 / 1024, 1024 / 16, 1024 / 64, 1024 / 256};

pub fn updateTimers(self: *Self, mmu: *MMU) void {
    // TODO: Accessing these every cycle is expensive. Maybe read it once as a packed struct?
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
        const currentIncrement = TIMER_INCR_TABLE[timerControl & 0x3];
        const addToTimer: u1 = @intCast(self.timerCounter / (currentFreq - 1)); 
        timer.*, const overflow = @addWithOverflow(timer.*, addToTimer * currentIncrement);
        self.timerCounter += 1;
        self.timerCounter %= currentFreq;

        if(overflow == 1) {
            mmu.setFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_TIMER);
            timer.* = timerMod;
        }
    }
}

pub fn initiateDMA(self: *Self, offset: u16) void {
    self.dmaIsRunning = true;
    self.dmaStartAddr = offset << 8;
    self.dmaCurrentOffset = 0;
}

pub fn updateDMA(self: *Self, mmu: *MMU) void {
    // TODO: Branchless?
    if (!self.dmaIsRunning) {
        return;
    }

    const sourceAddr: u16 = self.dmaStartAddr + self.dmaCurrentOffset;
    const destAddr: u16 = MemMap.OAM_LOW + self.dmaCurrentOffset;
    mmu.write8(destAddr, mmu.read8(sourceAddr));

    self.dmaCurrentOffset += 1;
    self.dmaIsRunning = (destAddr + 1) < MemMap.OAM_HIGH;
}
