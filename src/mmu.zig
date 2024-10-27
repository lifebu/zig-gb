const std = @import("std");

const MemMap = @import("mem_map.zig");
const MMIO = @import("mmio.zig");

const Self = @This();

memory: []u8 = undefined,
allocator: std.mem.Allocator,
mmio: *MMIO,

pub fn init(alloc: std.mem.Allocator, mmio: *MMIO, gbFile: ?[]const u8) !Self {
    var self = Self{ .allocator = alloc, .mmio = mmio };

    self.memory = try alloc.alloc(u8, 0x10000);
    errdefer alloc.free(self.memory);
    @memset(self.memory, 0);
    if (gbFile) |file| {
        _ = try std.fs.cwd().readFile(file, self.memory);

        const header: *align(1) MemMap.CartHeader = @ptrCast(&self.memory[MemMap.HEADER]);
        std.debug.print("Cart Features: {X}\n", .{header.cart_features});
    }

    // TODO: Consider either emulating DMG, or defining initial states for every possible DMG variant.
    // state after DMG Boot rom has run.
    // https://gbdev.io/pandocs/Power_Up_Sequence.html#hardware-registers
    self.memory[MemMap.JOYPAD] = 0xCF;
    self.memory[MemMap.SERIAL_DATA] = 0xFF; // TODO: Stubbing serial communication, should be 0x00.
    self.memory[MemMap.SERIAL_CONTROL] = 0x7E;
    self.memory[MemMap.DIVIDER] = 0xAB;
    self.memory[MemMap.TIMER] = 0x00;
    self.memory[MemMap.TIMER_MOD] = 0x00;
    self.memory[MemMap.TIMER_CONTROL] = 0xF8;
    self.memory[MemMap.INTERRUPT_FLAG] = 0xE1;
    self.memory[MemMap.CH1_SWEEP] = 0x80;
    self.memory[MemMap.CH1_LENGTH] = 0xBF;
    self.memory[MemMap.CH1_VOLUME] = 0xF3;
    self.memory[MemMap.CH1_LOW_PERIOD] = 0xFF;
    self.memory[MemMap.CH1_HIGH_PERIOD] = 0xBF;
    self.memory[MemMap.CH2_LENGTH] = 0x3F;
    self.memory[MemMap.CH2_VOLUME] = 0x00;
    self.memory[MemMap.CH2_LOW_PERIOD] = 0xFF;
    self.memory[MemMap.CH2_HIGH_PERIOD] = 0xBF;
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
    self.memory[MemMap.SOUND_TOGGLE] = 0xF1;
    self.memory[MemMap.LCD_CONTROL] = 0x91;
    self.memory[MemMap.LCD_STAT] = 0x85;
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

pub fn read8(self: *const Self, addr: u16) u8 {
   return self.memory[addr];
}

pub fn readi8(self: *const Self, addr: u16) i8 {
   return @bitCast(self.memory[addr]);
}

pub fn write8(self: *Self, addr: u16, val: u8) void {
    switch(addr) {
        MemMap.ROM_LOW...MemMap.ROM_HIGH => {
            // TODO: Missing MBC
            return;
        },
        MemMap.DIVIDER => {
            self.memory[addr] = 0;
        },
        MemMap.DMA => {
            // TODO: Disallow access to almost all memory, when a dma is running.
            self.mmio.initiateDMA(val);
            return;
        },
        else => {
            self.memory[addr] = val; 
        }
    }
}

pub fn read16(self: *const Self, addr: u16) u16 {
    // TODO: Implement something that allows reads on the memory boundary.
    std.debug.assert(addr <= 0xFFFF);
    const elem: *align(1) u16 = @ptrCast(&self.memory[addr]);
    return elem.*;
}

pub fn write16(self: *Self, addr: u16, val: u16) void {
    // TODO: Implement something that allows writes on the memory boundary.
    std.debug.assert(addr <= 0xFFFF);
    const elem: *align(1) u16 = @ptrCast(&self.memory[addr]);
    elem.* = val;
}

pub fn setFlag(self: *const Self, addr: u16, value: u8) void {
    const flag: *u8 = &self.memory[addr];
    flag.* |= value;
}

/// Use this function if you know you can bypass all the mmu side-effects.
pub fn getRaw(self: *Self) *[]u8 {
    return &self.memory;
}
