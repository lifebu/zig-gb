const std = @import("std");

const MemMap = @import("mem_map.zig");

const Self = @This();
/// Record of the last write that the user (cpu) did.
pub const WriteRecord = struct {
    addr: u16,
    val: u8,
    old_val: u8,
};


const Permission = struct {
    invert: bool = false,
    start_addr: u16,
    end_addr: u16,

    // TODO: Maybe split into read and write permissions?
    read_enabled: bool = false,
    read_val: u8 = 0xFF,

};

pub const PermissionType = enum(u8) {
    DMA = 0,
    ROM,
    VRAM,
    OAM,
    UNUSED,
    LCD_Y,
    Length,
};
// TODO: While the permission system is better then the dependencies I had before it still needs a V2.
// TODO: How to do that with an array of the types, that is typesafe?
// TODO: With this global config we can get rid of the map?
// TODO: Maybe we need an order for the permissions? DMA is higher then the rest.
// TODO: Maybe remove this permission system (which is quite complicated) and just use OnWriteBehavior. MMU has OnWrite as well.
const PermissionConf = [@intFromEnum(PermissionType.Length)]Permission{
    Permission{ .start_addr = MemMap.HRAM_LOW, .end_addr = MemMap.HRAM_HIGH - 1, .invert = true}, //DMA
    Permission{ .start_addr = MemMap.ROM_LOW, .end_addr = MemMap.ROM_HIGH - 1, .read_enabled = true, .invert = false }, // ROM
    Permission{ .start_addr = MemMap.VRAM_LOW, .end_addr = MemMap.VRAM_HIGH - 1 }, // VRAM
    Permission{ .start_addr = MemMap.OAM_LOW, .end_addr = MemMap.OAM_HIGH - 1 }, // OAM
    Permission{ .start_addr = MemMap.UNUSED_LOW, .end_addr = MemMap.UNUSED_HIGH - 1, }, // UNUSED
    Permission{ .start_addr = MemMap.LCD_Y, .end_addr = MemMap.LCD_Y, .read_enabled = true }, // LCD_Y
};
const PermissionMap = std.AutoHashMap(PermissionType, Permission);

allocator: std.mem.Allocator,
memory: []u8 = undefined,
/// Record of the last write that the user (cpu) did.
write_record: ?WriteRecord = null,
permissions: PermissionMap = undefined,

pub fn init(alloc: std.mem.Allocator) !Self {
    var self = Self{ .allocator = alloc };

    self.permissions = PermissionMap.init(alloc);
    errdefer self.permissions.deinit();

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

    // TODO: Some better way so that permanent permissions are set by their respective systems? (ROM => CART, UNUSED => MMU, LCD_Y => PPU). Requires init functions?
    self.setPermission(.ROM);
    self.setPermission(.UNUSED);
    self.setPermission(.LCD_Y);

    return self;
}

pub fn deinit(self: *Self) void {
    self.permissions.deinit();
    self.allocator.free(self.memory);
}

/// User level read, 8bit unsigned. Has read protections for some hardware registers and memory regions.
pub fn read8_usr(self: *const Self, addr: u16) u8 {
    var iter = self.permissions.valueIterator();
    while(iter.next()) |permission| {
        if(permission.read_enabled) {
            continue;
        }
        if((!permission.invert and addr >= permission.start_addr and addr <= permission.end_addr) or 
           (permission.invert and (addr < permission.start_addr or addr > permission.end_addr))) {
            return permission.read_val;
        }
    } 

    return self.memory[addr];
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

    var iter = self.permissions.valueIterator();
    while(iter.next()) |permission| {
        if((!permission.invert and addr >= permission.start_addr and addr <= permission.end_addr) or 
           (permission.invert and (addr < permission.start_addr or addr > permission.end_addr))) {
            return;
        }
    } 

    self.memory[addr] = val; 
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

pub fn setPermission(self: *Self, permission_type: PermissionType) void {
    self.permissions.put(permission_type, PermissionConf[@intFromEnum(permission_type)]) catch unreachable;
}

pub fn clearPermission(self: *Self, permission_type: PermissionType) void {
    _ = self.permissions.remove(permission_type);
}
