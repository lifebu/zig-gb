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
};
const MBCError = error {
    MBC_NOT_SUPPORTED,
};

allocator: std.mem.Allocator,
cart: []u8 = undefined,
mbc: MBC = .NO_MBC,

pub fn init(alloc: std.mem.Allocator, gbFile: ?[]const u8) !Self {
    var self = Self{ .allocator = alloc };

    if (gbFile) |filePath| {
        var file = try std.fs.cwd().openFile(filePath, .{});
        defer file.close(); 

        self.cart = try file.readToEndAlloc(alloc, std.math.maxInt(u32));
        errdefer alloc.free(self.cart);

        const header: *align(1) CartHeader = @ptrCast(&self.cart[HEADER]);
        self.mbc = try getMBC(header);
    } else {
        // Allocate an empty cartridge.
        self.cart = try alloc.alloc(u8, 0x8000);
        errdefer alloc.free(self.cart);

        @memset(self.cart, 0);
    }

    return self;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.cart);
}

fn getMBC(header: *align(1) CartHeader) !MBC {
    return switch(header.cart_features) {
        0x0 => .NO_MBC,
        else => blk: {
            std.debug.print("MBC NOT SUPPORTED: {x}\n", .{header.cart_features});
            break: blk MBCError.MBC_NOT_SUPPORTED;
        },
    };
} 

pub fn getCart(self: *Self) *[]u8 {
    return &self.cart;
}
