const std = @import("std");

const MemMap = @import("mem_map.zig");

const Self = @This();

memory: []u8 = undefined,
allocator: std.mem.Allocator,

pub fn init(alloc: std.mem.Allocator, gbFile: ?[]const u8) !Self {
    var self = Self{ .allocator = alloc };

    self.memory = try alloc.alloc(u8, 0x10000);
    errdefer alloc.free(self.memory);
    @memset(self.memory, 0);
    if (gbFile) |file| {
        _ = try std.fs.cwd().readFile(file, self.memory);
    }

    // state after DMG Boot rom has run.
    // https://gbdev.io/pandocs/Power_Up_Sequence.html#hardware-registers
    self.memory[MemMap.JOYPAD] = 0xCF;
    self.memory[MemMap.SERIAL_DATA] = 0xFF; // TODO: Stubbing serial communication, should be 0x00.
    self.memory[MemMap.SERIAL_CONTROL] = 0x7E;
    self.memory[MemMap.DIVIDER] = 0xAB;
    self.memory[MemMap.TIMER_CONTROL] = 0xF8;
    self.memory[MemMap.INTERRUPT_FLAG] = 0xE1;
    // TODO: Audio register are skipped for now.
    self.memory[MemMap.LCD_CONTROL] = 0x91;
    self.memory[MemMap.LCD_STAT] = 0x85;
    self.memory[MemMap.DMA] = 0xFF;
    self.memory[MemMap.BG_PALETTE] = 0xFC;

    return self;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.memory);
}

// TODO: How can I support the current way the cpu wants to read/write?
pub fn read8(self: *Self, addr: u16) u8 {
   return self.memory[addr];
}

pub fn write8(self: *Self, addr: u16, val: u8) void {
    switch(addr) {
        MemMap.DIVIDER => {
            self.memory[addr] = 0; 
        },
        else => {
            self.memory[addr] = val; 
        }
    }
}

pub fn read16(self: *Self, addr: u16) u16 {
    std.debug.assert(addr <= 0xFFFF);
    const elem: *align(1) u16 = @ptrCast(&self.memory[addr]);
    return elem.*;
}

pub fn write16(self: *Self, addr: u16, val: u16) void {
    const elem: *align(1) u16 = @ptrCast(&self.memory[addr]);
    elem.* = val;
}

/// Use this function if you know you can bypass all the mmu side-effects.
pub fn getRaw(self: *Self) *[]u8 {
    return &self.memory;
}
