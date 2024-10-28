const std = @import("std");

const MemMap = @import("mem_map.zig");

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

const MBC = enum {
    NO_MBC,
    MBC_1,
};
const MBCError = error {
    MBC_NOT_SUPPORTED,
};
const MBCRegisters = struct {
    ram_enable: bool = false,
    rom_bank: u5 = 0x00,
    ram_bank: u2 = 0x0,
    bank_mode: u1 = 0x0,
};

allocator: std.mem.Allocator,
rom: []u8 = undefined,
mbc: MBC = .NO_MBC,
mbc_registers: MBCRegisters = undefined,

pub fn init(alloc: std.mem.Allocator, gbFile: ?[]const u8) !Self {
    var self = Self{ .allocator = alloc };

    if (gbFile) |filePath| {
        var file = try std.fs.cwd().openFile(filePath, .{});
        defer file.close(); 

        self.rom = try file.readToEndAlloc(alloc, std.math.maxInt(u32));
        errdefer alloc.free(self.rom);

        const header: *align(1) CartHeader = @ptrCast(&self.rom[HEADER]);
        self.mbc = try getMBC(header);
    } else {
        // Allocate an empty cartridge.
        self.rom = try alloc.alloc(u8, 0x8000);
        errdefer alloc.free(self.rom);

        @memset(self.rom, 0);
    }

    return self;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.rom);
}

fn getMBC(header: *align(1) CartHeader) !MBC {
    // TODO: Don't just use the header to get the MBC type, also get the feature set. This includes ram support, battery, 
    return switch(header.cart_features) {
        0x00 => .NO_MBC,
        0x01...0x03 => .MBC_1,
        else => blk: {
            std.debug.print("MBC NOT SUPPORTED: {x}\n", .{header.cart_features});
            break: blk MBCError.MBC_NOT_SUPPORTED;
        },
    };
} 

pub fn getCart(self: *Self) *[]u8 {
    return &self.rom;
}

pub fn onWrite(self: *Self, _: *[]u8, addr: u16, val: u8) void {
    // TODO: I don't know if this code can be adapted well to other mbcs.
    if(self.mbc == .NO_MBC) {
        return;
    }

   switch(addr) {
        // TODO: Do this ranges work for all MBCs? I assume not. okay for now.
        0x0000...0x1FFF => {
            self.mbc_registers.ram_enable = @as(u4, @truncate(val)) == 0xA;
        },
        0x2000...0x3FFF => {
            self.mbc_registers.rom_bank = @truncate(@max(1, val));
        },
        0x4000...0x5FFF => {
            self.mbc_registers.ram_bank = @truncate(val);
        },
        0x6000...0x7FFF => {
            self.mbc_registers.bank_mode = @truncate(val);
        },
        // TODO: Error?, Always test the MBC on all write?
        else => {},
    }

    // TODO: I am assuming that bank switches don't happen all the time.
    // And that it is cheaper to just copy 16kByte into the memory region then to 
    // reroute all reads into ROM and Cartridge RAM regions into the seperate piece of memory of the cartridge. 
    // But this needs to be tested!

    // apply changes to memory.
    //std.mem.copyForwards(u8, self.memory, cart.*);
}
