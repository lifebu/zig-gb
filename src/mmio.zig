const std = @import("std");

const Def = @import("def.zig");
const MMU = @import("mmu.zig");
const MemMap = @import("mem_map.zig");

const Self = @This();

// Used to trigger interrupts from high->low transitions.
dpadState: u4 = 0xF,
buttonState: u4 = 0xF,

// last bit we tested for timer (used to detect falling edge).
timerLastBit: bool = false,
// TODO: Maybe rename to "systemCounter"? 
// TODO: Default value is default value after dmg, for other boot roms I need other values.
dividerCounter: u16 = 0xAB00,

dmaIsRunning: bool = false,
dmaStartAddr: u16 = 0x0000,
dmaCurrentOffset: u16 = 0,
dmaCounter: u3 = 0,

pub fn onWrite(self: *Self, mmu: *MMU) void {
    const write_record: MMU.WriteRecord = mmu.write_record orelse {
        return;
    };

    switch(write_record.addr) {
        MemMap.JOYPAD => {
            const joyp: u8 = (write_record.val & 0xF0) | (write_record.old_val & 0x0F);
            mmu.write8_sys(MemMap.JOYPAD, joyp);
            self.updateJoypad(mmu);
        },
        MemMap.DIVIDER => {
            mmu.memory[write_record.addr] = 0;
            self.dividerCounter = 0;
        },
        MemMap.DMA => {
            // Start DMA
            self.dmaIsRunning = true;
            self.dmaStartAddr = @as(u16, write_record.val) << 8;
            self.dmaCurrentOffset = 0;
            self.dmaCounter = 0;
            mmu.setPermission(.DMA);
        },
        else => {
            return;
        }
    }
}

pub fn updateInputState(self: *Self, mmu: *MMU, inputState: Def.InputState) void {
    const lastDpadState: u4 = self.dpadState;
    const lastButtonState: u4 = self.buttonState;

    self.dpadState = 0xF; 
    // disable physically impossible inputs: Left and Right, Up and Down
    self.dpadState &= ~(@as(u4, @intFromBool(inputState.isRightPressed and !inputState.isLeftPressed)) << 0);
    self.dpadState &= ~(@as(u4, @intFromBool(inputState.isLeftPressed and !inputState.isRightPressed)) << 1);
    self.dpadState &= ~(@as(u4, @intFromBool(inputState.isUpPressed and !inputState.isDownPressed)) << 2);
    self.dpadState &= ~(@as(u4, @intFromBool(inputState.isDownPressed and !inputState.isUpPressed)) << 3);
    
    self.buttonState = 0xF;
    self.buttonState &= ~(@as(u4, @intFromBool(inputState.isAPressed)) << 0);
    self.buttonState &= ~(@as(u4, @intFromBool(inputState.isBPressed)) << 1);
    self.buttonState &= ~(@as(u4, @intFromBool(inputState.isSelectPressed)) << 2);
    self.buttonState &= ~(@as(u4, @intFromBool(inputState.isStartPressed)) << 3);

    // Interrupts
    if (self.dpadState < lastDpadState or self.buttonState < lastButtonState) {
        mmu.setFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_JOYPAD);
    }
}

pub fn updateJoypad(self: *Self, mmu: *MMU) void {
    var joyp: u8 = mmu.read8_sys(MemMap.JOYPAD); 
    const selectDpad: bool = (joyp & 0x10) != 0x10;
    const selectButtons: bool = (joyp & 0x20) != 0x20;
    const nibble: u4 = 
        if(selectDpad and selectButtons) self.dpadState & self.buttonState 
        else if (selectDpad) self.dpadState 
        else if (selectButtons) self.buttonState
        else 0x0F;

    joyp = (joyp & 0xF0) | nibble; 
    mmu.write8_sys(MemMap.JOYPAD, joyp);
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
    if(!self.dmaIsRunning) {
        mmu.clearPermission(.DMA);
    }
}
