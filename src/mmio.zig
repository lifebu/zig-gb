const std = @import("std");

const Def = @import("def.zig");
const MMU = @import("mmu.zig");
const MemMap = @import("mem_map.zig");

const Self = @This();

// Used to trigger interrupts from high->low transitions.
lastDpadState: u4 = 0xF,
lastButtonState: u4 = 0xF,

// last bit we tested for timer (used to detect falling edge).
timerLastBit: bool = false,
// TODO: Maybe rename to "systemCounter"? 
dividerCounter: u16 = 0,

dmaIsRunning: bool = false,
dmaStartAddr: u16 = 0x0000,
dmaCurrentOffset: u16 = 0,
dmaCounter: u3 = 0,

pub fn updateJoypad(self: *Self, mmu: *MMU, inputState: Def.InputState) void {
    // TODO: Maybe we can just update the joypad on write?
    // And store the last InputState in the mmio? 
    // This would also allow that we move the code that disallows changing the lower nibble to here!
    // Also update when the actual input changed from platform (sfml events: key_pressed, key_released)
    // Or just: Update once per frame (before cycle loop) and once on every write.

    // 0 means pressed for gameboy => 0xF nothing is pressed
    var dpad: u4 = 0xF; 
    // disable phsysically impossible inputs: Left and Right, Up and Down
    dpad &= ~(@as(u4, @intFromBool(inputState.isRightPressed and !inputState.isLeftPressed)) << 0);
    dpad &= ~(@as(u4, @intFromBool(inputState.isLeftPressed and !inputState.isRightPressed)) << 1);
    dpad &= ~(@as(u4, @intFromBool(inputState.isUpPressed and !inputState.isDownPressed)) << 2);
    dpad &= ~(@as(u4, @intFromBool(inputState.isDownPressed and !inputState.isUpPressed)) << 3);
    
    var buttons: u4 = 0xF;
    buttons &= ~(@as(u4, @intFromBool(inputState.isAPressed)) << 0);
    buttons &= ~(@as(u4, @intFromBool(inputState.isBPressed)) << 1);
    buttons &= ~(@as(u4, @intFromBool(inputState.isSelectPressed)) << 2);
    buttons &= ~(@as(u4, @intFromBool(inputState.isStartPressed)) << 3);

    var joyp: u8 = mmu.read8_sys(MemMap.JOYPAD); 
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
    mmu.write8_sys(MemMap.JOYPAD, joyp);

    // TODO: Can we do this branchless?
    // Interrupts
    if (dpad < self.lastDpadState or buttons < self.lastButtonState) {
        mmu.setFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_JOYPAD);
    }
    self.lastDpadState = dpad;
    self.lastButtonState = buttons;
}

const TIMER_MASK_TABLE = [4]u10{ 1024 / 2, 16 / 2, 64 / 2, 256 / 2 };
const TimerControl = packed struct(u8) {
    clock: u2,
    enable: bool,
    _: u5,
};

pub fn updateTimers(self: *Self, mmu: *MMU) void {
    var timer: u8 = mmu.read8_sys(MemMap.TIMER);
    const timerControl: TimerControl = @bitCast(mmu.read8_sys(MemMap.TIMER_CONTROL));

    self.dividerCounter +%= 1;
    // GB only sees high 8 bit => divider increments every 256 cycles. 
    mmu.write8_sys(MemMap.DIVIDER, @intCast(self.dividerCounter >> 8));

    const timerMask = TIMER_MASK_TABLE[timerControl.clock];
    const timerBit: bool = ((self.dividerCounter & timerMask) == timerMask) and timerControl.enable;
    // Can happen when timerLastBit is true and timerControl.enable was set to false this frame (intended GB behavior). 
    const timerFallingEdge: bool = !timerBit and self.timerLastBit;
    timer, const overflow = @addWithOverflow(timer, @intFromBool(timerFallingEdge));
    // TODO: Branchless?
    if(overflow == 1) {
        // TODO: After overflowing, it takes 4 cycles before the interrupt flag is set and the value from timer_mod is used.
        // During that time, timer stays 0.
        // If the cpu writes to timer during the 4 cycles, these two steps will be skipped. 
        // If cpu writes to timer on the cycle that timer is set by the overflow, the cpu write will be overwritten.
        // If cpu writes to timer_mod on the cycle that timer is set by the overflow, the overflow uses the new timer_mod.
        mmu.setFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_TIMER);
        timer = mmu.read8_sys(MemMap.TIMER_MOD);
    }
    mmu.write8_sys(MemMap.TIMER, timer);

    self.timerLastBit = timerBit;
}

pub fn initiateDMA(self: *Self, offset: u16) void {
    self.dmaIsRunning = true;
    self.dmaStartAddr = offset << 8;
    self.dmaCurrentOffset = 0;
    self.dmaCounter = 0;
}

pub fn updateDMA(self: *Self, mmu: *MMU) void {
    // TODO: Branchless?
    if (!self.dmaIsRunning) {
        return;
    }

    // first time we overflow after 8 cycles for first write.
    self.dmaCounter, const overflow = @addWithOverflow(self.dmaCounter, 1);
    if(overflow == 0) {
        return;
    }

    // Setting to 4 means that after the first time, we overflow every 4 cycles.
    self.dmaCounter = 4;
    const sourceAddr: u16 = self.dmaStartAddr + self.dmaCurrentOffset;
    const destAddr: u16 = MemMap.OAM_LOW + self.dmaCurrentOffset;
    mmu.write8_sys(destAddr, mmu.read8_sys(sourceAddr));

    self.dmaCurrentOffset += 1;
    self.dmaIsRunning = (destAddr + 1) < MemMap.OAM_HIGH;
}
