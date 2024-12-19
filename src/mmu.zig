const std = @import("std");

const APU = @import("apu.zig");
const MemMap = @import("mem_map.zig");
const MMIO = @import("mmio.zig");
const PPU = @import("ppu.zig");

const Self = @This();
/// Record of the last write that the user (cpu) did.
pub const WriteRecord = struct {
    addr: u32,
    val: u8,
    old_val: u8,
};

allocator: std.mem.Allocator,
memory: []u8 = undefined,
mmio: *MMIO,
apu: *APU,
/// Record of the last write that the user (cpu) did.
write_record: ?WriteRecord = null,

pub fn init(alloc: std.mem.Allocator, apu: *APU, mmio: *MMIO) !Self {
    // which means the CPU needs to pass it to the read functions.
    // Maybe use singletons for this?
    var self = Self{ .allocator = alloc, .apu = apu, .mmio = mmio };

    self.memory = try alloc.alloc(u8, 0x10000);
    errdefer alloc.free(self.memory);
    @memset(self.memory, 0);

    // TODO: Consider either emulating DMG, or defining initial states for every possible DMG variant.
    // state after DMG Boot rom has run.
    // https://gbdev.io/pandocs/Power_Up_Sequence.html#hardware-registers
    self.memory[MemMap.JOYPAD] = 0xCF;
    self.memory[MemMap.SERIAL_DATA] = 0xFF; // TODO: Stubbing serial communication, should be 0x00.
    self.memory[MemMap.SERIAL_CONTROL] = 0x7E;
    self.memory[MemMap.DIVIDER] = 0xAB;
    self.mmio.dividerCounter = 0xAB00;
    self.memory[MemMap.TIMER] = 0x00;
    self.memory[MemMap.TIMER_MOD] = 0x00;
    self.memory[MemMap.TIMER_CONTROL] = 0xF8;
    self.memory[MemMap.INTERRUPT_FLAG] = 0xE1;
    self.memory[MemMap.CH1_SWEEP] = 0x80;
    self.memory[MemMap.CH1_LENGTH] = 0xBF;
    self.memory[MemMap.CH1_VOLUME] = 0xF3;
    self.memory[MemMap.CH1_LOW_PERIOD] = 0xFF;
    self.memory[MemMap.CH1_HIGH_PERIOD] = 0xBF;
    self.memory[MemMap.CH2_LENGTH] = 0x20; // TODO: Should be 0x3F, workaround for audio bug.
    self.memory[MemMap.CH2_VOLUME] = 0x00;
    self.memory[MemMap.CH2_LOW_PERIOD] = 0x00; // TODO: Should be 0xFF, workaround for audio bug.
    self.memory[MemMap.CH2_HIGH_PERIOD] = 0xB0; // TODO: Should be 0xBF, workaround for audio bug.
    self.memory[MemMap.CH3_DAC] = 0x7F;
    self.memory[MemMap.CH3_LENGTH] = 0xFF;
    self.memory[MemMap.CH3_VOLUME] = 0x9F;
    self.memory[MemMap.CH3_LOW_PERIOD] = 0xFF;
    self.memory[MemMap.CH3_HIGH_PERIOD] = 0xBF;
    self.memory[MemMap.CH4_LENGTH] = 0xFF;
    self.memory[MemMap.CH4_VOLUME] = 0x00;
    self.memory[MemMap.CH4_FREQ] = 0x00;
    self.memory[MemMap.CH4_CONTROL] = 0xBF;
    self.memory[MemMap.MASTER_VOLUME] = 0x77;
    self.memory[MemMap.SOUND_PANNING] = 0xF3;
    self.memory[MemMap.SOUND_CONTROL] = 0xF1;
    self.memory[MemMap.LCD_CONTROL] = 0x91;
    self.memory[MemMap.LCD_STAT] = 0x80; // TODO: Should be 85, using 80 for now so that my ppu fake timings work
    self.memory[MemMap.SCROLL_Y] = 0x00;
    self.memory[MemMap.SCROLL_X] = 0x00;
    self.memory[MemMap.LCD_Y] = 0x00;
    self.memory[MemMap.LCD_Y_COMPARE] = 0x00;
    self.memory[MemMap.DMA] = 0xFF;
    self.memory[MemMap.BG_PALETTE] = 0xFC;
    self.memory[MemMap.OBJ_PALETTE_0] = 0xFF;
    self.memory[MemMap.OBJ_PALETTE_1] = 0xFF;
    self.memory[MemMap.WINDOW_Y] = 0x00;
    self.memory[MemMap.WINDOW_X] = 0x00;
    self.memory[MemMap.INTERRUPT_ENABLE] = 0x00;

    return self;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.memory);
}

/// User level read, 8bit unsigned. Has read protections for some hardware registers and memory regions.
pub fn read8_usr(self: *const Self, addr: u16) u8 {
    // TODO: Branchless?
    // During DMA, only HRAM is writeable
    if(self.mmio.dmaIsRunning) {
        if(addr < MemMap.HRAM_LOW or addr >= MemMap.HRAM_HIGH) {
            return 0xFF;
        }
    }

    switch(addr) {
        MemMap.VRAM_LOW...MemMap.VRAM_HIGH - 1 => {
            // TODO: Better if the subsystem makes sure of that?
            const lcd_stat: PPU.LCDStat = @bitCast(self.memory[MemMap.LCD_STAT]);
            if(lcd_stat.ppu_mode == .DRAW) {
                return 0xFF; 
            }

            return self.memory[addr];
        },
        MemMap.ECHO_LOW...MemMap.ECHO_HIGH - 1 => {
            const echo_diff: u16 = comptime MemMap.ECHO_LOW - MemMap.WRAM_LOW;
            return self.memory[addr - echo_diff]; 
        },
        MemMap.OAM_LOW...MemMap.OAM_HIGH - 1 => {
            // TODO: Better if the subsystem makes sure of that?
            const lcd_stat: PPU.LCDStat = @bitCast(self.memory[MemMap.LCD_STAT]);
            if(lcd_stat.ppu_mode == .OAM_SCAN or lcd_stat.ppu_mode == .DRAW) {
                return 0xFF; 
            }

            return self.memory[addr];
        },
        MemMap.UNUSED_LOW...MemMap.UNUSED_HIGH - 1 => {
            return 0x00;
        },
        else => {
            return self.memory[addr]; 
        }
    }
}
/// System level read, 8bit unsigned. No read protections
pub fn read8_sys(self: *const Self, addr: u16) u8 {
   return self.memory[addr];
}

/// User level read, 8bit signed. Has read protections for some hardware registers and memory regions.
pub fn readi8_usr(self: *const Self, addr: u16) i8 {
   return @bitCast(self.read8_usr(addr));
}

/// User level write, 8bit unsigned. Has write protections for some hardware registers and memory regions.
pub fn write8_usr(self: *Self, addr: u16, val: u8) void {
    self.write_record = WriteRecord{ .addr = addr, .val = val, .old_val = self.memory[addr]};

    // TODO: Branchless?
    // During DMA, only HRAM is writeable
    if(self.mmio.dmaIsRunning) {
        if(addr < MemMap.HRAM_LOW or addr >= MemMap.HRAM_HIGH) {
            return;
        }
    }

    switch(addr) {
        MemMap.ROM_LOW...MemMap.ROM_HIGH - 1 => {
            // TODO: Use Read/Write flags for this!
            return;
        },
        MemMap.VRAM_LOW...MemMap.VRAM_HIGH - 1 => {
            // TODO: Better if the subsystem makes sure of that?
            const lcd_stat: PPU.LCDStat = @bitCast(self.memory[MemMap.LCD_STAT]);
            if(lcd_stat.ppu_mode == .DRAW) {
                return; 
            }

            self.memory[addr] = val;
        },
        MemMap.ECHO_LOW...MemMap.ECHO_HIGH - 1 => {
            const echo_diff: u16 = comptime MemMap.ECHO_LOW - MemMap.WRAM_LOW;
            self.memory[addr - echo_diff] = val; 
        },
        MemMap.OAM_LOW...MemMap.OAM_HIGH - 1 => {
            // TODO: Better if the subsystem makes sure of that?
            const lcd_stat: PPU.LCDStat = @bitCast(self.memory[MemMap.LCD_STAT]);
            if(lcd_stat.ppu_mode == .OAM_SCAN or lcd_stat.ppu_mode == .DRAW) {
                return; 
            }

            self.memory[addr] = val;
        },
        MemMap.UNUSED_LOW...MemMap.UNUSED_HIGH - 1 => {
            return; // Read-Only
        },
        MemMap.JOYPAD => {
            // TODO: Better if the subsystem makes sure of that?
            // Only the lower nibble can be written to!
            const old_joyp: u8 = self.memory[MemMap.JOYPAD];
            self.memory[addr] = (val & 0xF0) | (old_joyp & 0x0F);
        },
        MemMap.DIVIDER => {
            self.memory[addr] = 0;
            self.mmio.dividerCounter = 0;
        },
        MemMap.LCD_Y => {
            // TODO: Better if the subsystem makes sure of that?
            return; // Read-Only
        },
        MemMap.LCD_STAT => {
            // TODO: Better if the subsystem makes sure of that?
            // low 3 bits are read only.
            const old: u8 = self.memory[MemMap.LCD_STAT];
            const result: u8 = (val & 0xF8) | (old & 0x07);
            self.memory[addr] = result;
        },
        MemMap.DMA => {
            // TODO: Disallow access to almost all memory, when a dma is running.
            self.mmio.initiateDMA(val);
            return;
        },
        MemMap.AUDIO_LOW...MemMap.AUDIO_HIGH - 1 => {
            self.apu.onAPUWrite(self, addr, val);
            return;
        },
        else => {
            self.memory[addr] = val; 
        }
    }
}
/// System level write, 8bit unsigned. No write protections
pub fn write8_sys(self: *Self, addr: u16, val: u8) void {
    self.memory[addr] = val;
}

/// User level read, 16bit unsigned. Has read protections for some hardware registers and memory regions.
pub fn read16_usr(self: *const Self, addr: u16) u16 {
    // TODO: Implement something that allows reads on the memory boundary.
    std.debug.assert(addr <= 0xFFFF);
    const elem: *align(1) u16 = @ptrCast(&self.memory[addr]);
    return elem.*;
}
/// System level read, 16bit unsigned. No read protections.
pub fn read16_sys(self: *const Self, addr: u16) u16 {
    // TODO: Implement something that allows reads on the memory boundary.
    std.debug.assert(addr <= 0xFFFF);
    const elem: *align(1) u16 = @ptrCast(&self.memory[addr]);
    return elem.*;
}

/// User level write, 16bit unsigned. Has write protections for some hardware registers and memory regions.
pub fn write16_usr(self: *Self, addr: u16, val: u16) void {
    // TODO: Do we need the same write behaviour as write8?
    // TODO: Implement something that allows writes on the memory boundary.
    std.debug.assert(addr <= 0xFFFF);

    const elem: *align(1) u16 = @ptrCast(&self.memory[addr]);
    elem.* = val;
}
/// System level write, 16bit unsigned. No write protections
pub fn write16_sys(self: *Self, addr: u16, val: u16) void {
    // TODO: Implement something that allows writes on the memory boundary.
    std.debug.assert(addr <= 0xFFFF);

    const elem: *align(1) u16 = @ptrCast(&self.memory[addr]);
    elem.* = val;
}

pub fn setFlag(self: *const Self, addr: u16, value: u8) void {
    const flag: *u8 = &self.memory[addr];
    flag.* |= value;
}

pub fn testFlag(self: *const Self, addr: u16, value: u8) bool {
    const flag: *u8 = &self.memory[addr];
    return flag.* & value == value;
}

pub fn clearWriteRecord(self: *Self) void {
    self.write_record = null;
}
