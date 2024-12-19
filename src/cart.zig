const std = @import("std");
const assert = std.debug.assert;

const MemMap = @import("mem_map.zig");
const MMU = @import("mmu.zig");

const Self = @This();

pub const HEADER: u16 = 0x0100;
pub const CartHeader = packed struct {
    _: u32, // entry point
    logo_0: u128,
    logo_1: u128,
    logo_2: u128,
    title_0: u64,
    title_1: u16,
    title_2: u8,
    dev: u32, // manufacturer code.
    cgb: u8, // cgb support (0x80: cgb enhanced, 0xC0: cgb required)
    licensee: u16,
    sgb: u8, // sgb support: (0x03: sgb supported)
    cart_features: u8, // cartridge features
    rom_size: u8,
    ram_size: u8,
    region: u8, // 0x00: Japan, 0x01: Overseas
    old_licensee: u8,
    version: u8,
    header_checksum: u8,
    global_checksum: u16,
};
pub const ROM_BANK_SIZE_BYTE: u32 = 16 * 1024;
pub const ROM_SIZE_BYTE = [_]u32 {
    2 * ROM_BANK_SIZE_BYTE, 4 * ROM_BANK_SIZE_BYTE, 8 * ROM_BANK_SIZE_BYTE, 
    16 * ROM_BANK_SIZE_BYTE, 32 * ROM_BANK_SIZE_BYTE, 64 * ROM_BANK_SIZE_BYTE, 
    128 * ROM_BANK_SIZE_BYTE, 256 * ROM_BANK_SIZE_BYTE, 512 * ROM_BANK_SIZE_BYTE
};

pub const RAM_BANK_SIZE_BYTE: u32 = 8 * 1024;
pub const RAM_SIZE_BYTE = [_]u32 {
    0 * RAM_BANK_SIZE_BYTE, 0 * RAM_BANK_SIZE_BYTE, // Unused and only found in unofficial docs.
    1 * RAM_BANK_SIZE_BYTE, 4 * RAM_BANK_SIZE_BYTE,
    16 * RAM_BANK_SIZE_BYTE, 8 * RAM_BANK_SIZE_BYTE,
};

// TODO: Instead of just the MBC type we can define a feature set struct that has all the features and their configuration for the cartridge in one.
// Example: Have an entry for the 00->01 Translation behavior in there and apply it if it is enabled!.
const MBC = enum {
    NO_MBC,
    MBC_1,
    MBC_3,
    MBC_5,
};
const MBCError = error {
    MBC_NOT_SUPPORTED,
};
const MBCRegisters = struct {
    ram_enable: bool = false,
    rom_bank: u9 = 0x00,
    ram_bank: u4 = 0x0,
    bank_mode: u1 = 0x0,
};

allocator: std.mem.Allocator,
rom: []u8 = undefined,
ram: ?[]u8 = null,
saveFilePath: []const u8 = undefined,

// TODO: Honestly not great, but works for now.
zero_ram_bank: []u8 = undefined,
mbc: MBC = .NO_MBC,
mbc_registers: MBCRegisters = undefined,

pub fn init(alloc: std.mem.Allocator, memory: *[]u8, gbFile: ?[]const u8) !Self {
    var self = Self{ .allocator = alloc };

    if (gbFile) |filePath| {
        var file = try std.fs.cwd().openFile(filePath, .{});
        defer file.close(); 

        self.rom = try file.readToEndAlloc(alloc, std.math.maxInt(u32));
        errdefer alloc.free(self.rom);

        // Initial copy of the first banks.
        std.mem.copyForwards(u8, memory.*[MemMap.ROM_LOW..MemMap.ROM_HIGH], self.rom[0..2 * ROM_BANK_SIZE_BYTE]);

        const header: *align(1) CartHeader = @ptrCast(&self.rom[HEADER]);
        self.mbc = try getMBC(header);

        // TODO: Check if the cart_features even support ram and don't just use the ram size.
        // TODO: Also check that the RAM size as the MBC would be able to support it.
        const ramSizeByte = RAM_SIZE_BYTE[header.ram_size];
        if(ramSizeByte != 0) {
            self.saveFilePath = self.getSaveFilename(filePath);
            errdefer alloc.free(self.saveFilePath);

            const saveFile: ?std.fs.File = std.fs.cwd().openFile(self.saveFilePath, .{}) catch null;
            if(saveFile != null) {
                // Read a savegame.
                self.ram = try saveFile.?.readToEndAlloc(alloc, ramSizeByte);
                errdefer alloc.free(self.ram.?);
            }
            else {
                self.ram = try alloc.alloc(u8, ramSizeByte); 
                @memset(self.ram.?, 0);
                errdefer alloc.free(self.ram.?);
            }
        }
    } else {
        // Allocate an empty cartridge.
        self.rom = try alloc.alloc(u8, 0x8000);
        errdefer alloc.free(self.rom);
        @memset(self.rom, 0);
    }

    self.zero_ram_bank = try alloc.alloc(u8, RAM_BANK_SIZE_BYTE);
    @memset(self.zero_ram_bank, 0xFF);
    errdefer alloc.free(self.zero_ram_bank);

    return self;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.rom);
    if(self.ram) |ram| {
        self.allocator.free(ram);
        self.allocator.free(self.saveFilePath);
    }
    self.allocator.free(self.zero_ram_bank);
}

fn getSaveFilename(self: *Self, gbFile: []const u8) []const u8 {
    var saveFilePath = std.ArrayList(u8).init(self.allocator);
    defer saveFilePath.deinit();

    var iter = std.mem.splitScalar(u8, gbFile, '.');
    saveFilePath.appendSlice(iter.first()) catch return "";
    saveFilePath.appendSlice(".sav") catch return "";
    const path = saveFilePath.toOwnedSlice() catch return "";
    return path;
}

fn getMBC(header: *align(1) CartHeader) !MBC {
    // TODO: Don't just use the header to get the MBC type, also get the feature set. This includes ram support, battery, 
    return switch(header.cart_features) {
        0x00 => .NO_MBC,
        0x01...0x03 => blk: {
            // This Cartridge uses MBC1 with the alternative wiring. This is not supported yet!
            std.debug.assert(ROM_SIZE_BYTE[header.rom_size] <= 512 * 1024);
            break: blk .MBC_1;
        },
        0x0F...0x13 => blk: {
            break: blk .MBC_3;
        },
        0x19...0x1E => blk: {
            break: blk .MBC_5;
        },
        else => blk: {
            std.debug.print("MBC NOT SUPPORTED: {x}\n", .{header.cart_features});
            break: blk MBCError.MBC_NOT_SUPPORTED;
        },
    };
} 

pub fn getCart(self: *Self) *[]u8 {
    return &self.rom;
}

pub fn onWrite(self: *Self, mmu: *MMU, addr: u16, val: u8) void {
    // TODO: I don't know if this code can be adapted well to other mbcs.
    const header: *align(1) CartHeader = @ptrCast(&self.rom[HEADER]);
    var ramChanged: bool = false;
    var romChanged: bool = false;

    // TODO: horrible double switch.
    switch(self.mbc) {
        .NO_MBC => {
            return;
        },
        .MBC_1 => {
            switch(addr) {
                0x0000...0x1FFF => {
                    self.mbc_registers.ram_enable = @as(u4, @truncate(val)) == 0xA;
                    ramChanged = true;
                },
                0x2000...0x3FFF => {
                    const romSizeByte = ROM_SIZE_BYTE[header.rom_size];
                    const numBanks: u9 = @truncate(romSizeByte / ROM_BANK_SIZE_BYTE);
                    const mask: u9 = @intCast(numBanks - 1);
                    self.mbc_registers.rom_bank = @truncate(@max(1, val) & mask);
                    romChanged = true;
                },
                0x4000...0x5FFF => {
                    const ramSizeByte = RAM_SIZE_BYTE[header.ram_size];
                    const numBanks: u6 = @truncate(ramSizeByte / RAM_BANK_SIZE_BYTE);
                    if(numBanks == 1) {
                        return; // Nothing to switch on 
                    }

                    const mask: u9 = @intCast(numBanks - 1);
                    self.mbc_registers.ram_bank = @truncate(val & mask);
                    ramChanged = true;
                },
                0x6000...0x7FFF => {
                    self.mbc_registers.bank_mode = @truncate(val);
                },
                // TODO: Error?, Always test the MBC on all write?
                else => {},
            }
        },
        .MBC_3 => {
            switch(addr) {
                // TODO: Implement RTC
                0x0000...0x1FFF => {
                    // TODO: This also enables access to the RTC registers.
                    self.mbc_registers.ram_enable = @as(u4, @truncate(val)) == 0xA;
                    ramChanged = true;
                },
                0x2000...0x3FFF => {
                    const romSizeByte = ROM_SIZE_BYTE[header.rom_size];
                    const numBanks: u9 = @truncate(romSizeByte / ROM_BANK_SIZE_BYTE);
                    const mask: u9 = @intCast(numBanks - 1);
                    self.mbc_registers.rom_bank = @truncate(@max(1, val) & mask);
                    romChanged = true;
                },
                0x4000...0x5FFF => {
                    // TODO: Writing 0x08-0x0C to this register does not map a ram bank to A000-BFFF but a single RTC Register to that range (read/write).
                    // Depending on what you write you can access different registers.
                    const ramSizeByte = RAM_SIZE_BYTE[header.ram_size];
                    const numBanks: u6 = @truncate(ramSizeByte / RAM_BANK_SIZE_BYTE);
                    if(numBanks == 1) {
                        return; // Nothing to switch on 
                    }

                    const mask: u9 = @intCast(numBanks - 1);
                    self.mbc_registers.ram_bank = @truncate(val & mask);
                    ramChanged = true;
                },
                0x6000...0x7FFF => {
                    // TODO: Writing 00 followed by 01. The current time becomes "latched" into the RTC registers.
                    // That "latched" data will not change until you do it again by repeating this pattern.
                    // This way you can read the RTC registers while the clocks keeps ticking.
                },
                // TODO: Error?, Always test the MBC on all write?
                else => {},
            }
        },
        .MBC_5 => {
            switch(addr) {
                0x0000...0x1FFF => {
                    self.mbc_registers.ram_enable = @as(u4, @truncate(val)) == 0xA;
                    ramChanged = true;
                },
                0x2000...0x2FFF => {
                    // TODO: first 8 bits of rom bank.
                    const romSizeByte = ROM_SIZE_BYTE[header.rom_size];
                    const numBanks: u9 = @truncate(romSizeByte / ROM_BANK_SIZE_BYTE);
                    const mask: u9 = @intCast(numBanks - 1);
                    self.mbc_registers.rom_bank = @truncate(@max(1, val) & mask);
                    romChanged = true;
                },
                0x3000...0x3FFF => {
                    // TODO: highest 1 bit of rom bank.
                    std.debug.print("Highest ROM bit not supported! \n", .{});
                    assert(false);
                },
                0x4000...0x5FFF => {
                    const ramSizeByte = RAM_SIZE_BYTE[header.ram_size];
                    const numBanks: u6 = @truncate(ramSizeByte / RAM_BANK_SIZE_BYTE);
                    if(numBanks == 1) {
                        return; // Nothing to switch on 
                    }

                    const mask: u9 = @intCast(numBanks - 1);
                    self.mbc_registers.ram_bank = @truncate(val & mask);
                    ramChanged = true;
                },
                // TODO: Error?, Always test the MBC on all write?
                else => {},
            }
        },
    }
    
    // TODO: I am assuming that bank switches don't happen all the time.
    // And that it is cheaper to just copy 16kByte into the memory region then to 
    // reroute all reads into ROM and Cartridge RAM regions into the seperate piece of memory of the cartridge. 
    // But this needs to be tested!
    if(ramChanged) {
        if(self.ram) |ram| {
            if(self.mbc_registers.ram_enable) {
                const ramStart: u32 = self.mbc_registers.ram_bank * RAM_BANK_SIZE_BYTE;
                const ramEnd: u32 = ramStart + RAM_BANK_SIZE_BYTE;
                std.mem.copyForwards(u8, mmu.memory[MemMap.CART_RAM_LOW..MemMap.CART_RAM_HIGH], ram[ramStart..ramEnd]);
            } else {
                std.mem.copyForwards(u8, mmu.memory[MemMap.CART_RAM_LOW..MemMap.CART_RAM_HIGH], self.zero_ram_bank);
            }
        }
    }

    if(romChanged) {
        const romStart: u32 = self.mbc_registers.rom_bank * ROM_BANK_SIZE_BYTE;
        const romEnd: u32 = romStart + ROM_BANK_SIZE_BYTE;
        std.mem.copyForwards(u8, mmu.memory[MemMap.ROM_MIDDLE..MemMap.ROM_HIGH], self.rom[romStart..romEnd]);
    }

    if(ramChanged and !self.mbc_registers.ram_enable) {
        if(self.ram) |_| {
            //const createFlags = std.fs.File.CreateFlags{ .exclusive = false };
            //const writeFlags = std.fs.Dir.WriteFileOptions{ .sub_path = self.saveFilePath, .data = self.ram.?, .flags = createFlags };
            //std.fs.cwd().writeFile(writeFlags) catch unreachable;
        }
    }
}
