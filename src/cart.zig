const std = @import("std");
const assert = std.debug.assert;

const def = @import("defines.zig");

const Self = @This();

const header_cart_type: u16 = 0x147;
const header_rom_size: u16 = 0x148;
const header_ram_size: u16 = 0x149; 

const rom_bank_size_byte: u32 = 16 * 1024;
const rom_size_visible: u32 = 2 * rom_bank_size_byte;
const rom_bank_amount = [_]u10 { 2, 4, 8, 16, 32, 64, 128, 256, 512 };
const ram_bank_size_byte: u32 = 8 * 1024;
const ram_size_visible: u32 = ram_bank_size_byte;
const ram_bank_amount = [_]u10 { 0, 0, 1, 4, 16, 8, };

const MapperType = enum(u3) {
    unsupported = 0, no_mbc, mbc_1, mbc_3, mbc_5,
};
const CartFeatures = struct {
    mapper: MapperType = .unsupported,
    has_ram: bool = false,
    has_battery: bool = false,
    has_timer: bool = false,
    has_rumble: bool = false,
    has_accelerometer: bool = false,
};
const type_table: [256]CartFeatures = blk: {
    var result: [256]CartFeatures = @splat(.{});
    result[0x00] = .{ .mapper = .no_mbc };
    result[0x01] = .{ .mapper = .mbc_1 };
    result[0x02] = .{ .mapper = .mbc_1, .has_ram = true };
    result[0x03] = .{ .mapper = .mbc_1, .has_ram = true, .has_battery = true };
    result[0x05] = .{ .mapper = .mbc_3 };
    result[0x06] = .{ .mapper = .mbc_3, .has_battery = true };
    result[0x0B] = .{ .mapper = .unsupported }; // MMM01
    result[0x0C] = .{ .mapper = .unsupported, .has_ram = true }; // MMM01
    result[0x0D] = .{ .mapper = .unsupported, .has_ram = true, .has_battery = true }; // MMM01
    result[0x0F] = .{ .mapper = .mbc_3, .has_battery = true, .has_timer = true };
    result[0x10] = .{ .mapper = .mbc_3, .has_ram = true, .has_battery = true, .has_timer = true };
    result[0x11] = .{ .mapper = .mbc_3 };
    result[0x12] = .{ .mapper = .mbc_3, .has_ram = true };
    result[0x13] = .{ .mapper = .mbc_3, .has_ram = true, .has_battery = true };
    result[0x19] = .{ .mapper = .mbc_5 };
    result[0x1A] = .{ .mapper = .mbc_5, .has_ram = true };
    result[0x1B] = .{ .mapper = .mbc_5, .has_ram = true, .has_battery = true };
    result[0x1C] = .{ .mapper = .mbc_5, .has_rumble = true };
    result[0x1D] = .{ .mapper = .mbc_5, .has_ram = true, .has_rumble = true };
    result[0x1E] = .{ .mapper = .mbc_5, .has_ram = true, .has_battery = true, .has_rumble = true };
    result[0x20] = .{ .mapper = .unsupported }; // MBC6
    result[0x22] = .{ .mapper = .unsupported, .has_ram = true, .has_battery = true, .has_rumble = true, .has_accelerometer = true }; // MBC7
    result[0xFC] = .{ .mapper = .unsupported }; // Pocket Camera
    result[0xFD] = .{ .mapper = .unsupported }; // Bandai Tama5
    result[0xFE] = .{ .mapper = .unsupported }; // HuC3
    result[0xFF] = .{ .mapper = .unsupported, .has_ram = true, .has_battery = true }; // HuC1
    break :blk result;
};

const MapperRange = struct {
    low: u16, high: u16,
};
fn isInRange(range: ?MapperRange, value: u16) bool {
    return range != null and value >= range.?.low and value <= range.?.high; 
}
const MapperRanges = struct {
    ram_enable: ?MapperRange = null,
    rom_bank: ?MapperRange = null,
    rom_bank_msb: ?MapperRange = null,
    ram_bank: ?MapperRange = null,
    bank_mode: ?MapperRange = null,
    rtc: ?MapperRange = null,
    min_bank: u1 = 1,
};
const info_table: std.EnumArray(MapperType, MapperRanges) = .{ .values = .{
    // unsupported
    .{},
    // no_mbc
    .{},
    // mbc_1
    .{
        .ram_enable =   .{ .low = 0x0000, .high = 0x1FFF },
        .rom_bank =     .{ .low = 0x2000, .high = 0x3FFF },
        .ram_bank =     .{ .low = 0x4000, .high = 0x5FFF },
        .bank_mode =    .{ .low = 0x6000, .high = 0x7FFF },
        .min_bank = 1,
    },
    // mbc_3
    .{
        .ram_enable =   .{ .low = 0x0000, .high = 0x1FFF },
        .rom_bank =     .{ .low = 0x2000, .high = 0x3FFF },
        .ram_bank =     .{ .low = 0x4000, .high = 0x5FFF },
        .rtc =          .{ .low = 0x6000, .high = 0x7FFF },
        .min_bank = 1,
    },
    // mbc_5
    .{
        .ram_enable =   .{ .low = 0x0000, .high = 0x1FFF },
        .rom_bank =     .{ .low = 0x2000, .high = 0x2FFF },
        .rom_bank_msb = .{ .low = 0x3000, .high = 0x3FFF },
        .ram_bank =     .{ .low = 0x4000, .high = 0x5FFF },
        .min_bank = 0,
    },
}};


// rom
rom_banks: [][rom_bank_size_byte]u8 = &.{},
rom_bank_low: u9 = 0,
rom_bank_high: u9 = 1,
rom_bank_highest_bit: u1 = 0,

// ram
ram_enable: bool = false,
ram_banks: [][ram_bank_size_byte]u8 = &.{},
ram_bank: u4 = 0,

// mbc
features: CartFeatures = .{},
ranges: MapperRanges = .{},
bank_mode: u1 = 0,


pub fn init(self: *Self) void {
    self.* = .{};
}

pub fn deinit(self: *Self, io: std.Io, alloc: std.mem.Allocator, rom_path: []const u8, disable_saves: bool) void {
    const save_path: []const u8 = getSavePath(alloc, rom_path);
    defer alloc.free(save_path);

    if(self.features.has_battery and self.features.has_ram and !disable_saves) {
        // TODO: Try to rewrite this using std.Io.Dir.cwd().writeFile()
        const save_file: std.Io.File = std.Io.Dir.cwd().createFile(io, save_path, .{}) catch unreachable;
        defer save_file.close(io);

        for(self.ram_banks) |bank| {
            _ = save_file.writeStreamingAll(io, &bank) catch unreachable;
        }
    }

    alloc.free(self.rom_banks);
    alloc.free(self.ram_banks);
}

pub fn request(self: *Self, req: *def.Request) void {
    // TODO: Having this very different code section for mbc only and the witch case below feels like not the best code structure?
    // The "IsInRange() and isWrite()" feels very microoptimized.
    // mbc
    if (isInRange(self.ranges.ram_enable, req.address) and req.isWrite()) {
        // TODO: This also enables access to the RTC registers.
        self.ram_enable = @as(u4, @truncate(req.value.write)) == 0xA;
        // TODO: Write to savefile every time we disable the ram bank?

    } else if (isInRange(self.ranges.rom_bank, req.address) and req.isWrite()) {
        // TODO: This truncation for each mbc gives further evidence that I should split this better?
        const register_sized: u8 = switch(self.features.mapper) {
            .mbc_1 => @as(u5, @truncate(req.value.write)),
            .mbc_3 => @as(u8, @truncate(req.value.write)),
            .mbc_5, .no_mbc => req.value.write,
            .unsupported => unreachable,
        };
        const mask: u9 = @intCast(self.rom_banks.len - 1);
        self.rom_bank_high = @truncate(@max(self.ranges.min_bank, register_sized) & mask);

    } else if (isInRange(self.ranges.rom_bank_msb, req.address) and req.isWrite()) {
        self.rom_bank_highest_bit = @truncate(req.value.write);

    } else if (isInRange(self.ranges.ram_bank, req.address) and req.isWrite()) {
        // TODO: MBC_3 Writing 0x08-0x0C to this register does not map a ram bank to A000-BFFF but a single RTC Register to that range (read/write).
        // Depending on what you write you can access different registers.
        if(self.ram_banks.len > 1) {
            const mask: u9 = @intCast(self.ram_banks.len - 1);
            self.ram_bank = @truncate(req.value.write & mask);
        }

    } else if (isInRange(self.ranges.bank_mode, req.address) and req.isWrite()) {
        // TODO: Implement banking mode for mbc_1 when alternative wiring is used.
        self.bank_mode = @truncate(req.value.write);

    } else if (isInRange(self.ranges.rtc, req.address) and req.isWrite()) {
        // TODO: Writing 00 followed by 01. The current time becomes "latched" into the RTC registers.
        // That "latched" data will not change until you do it again by repeating this pattern.
        // This way you can read the RTC registers while the clocks keeps ticking.
    }

    // memory
    switch(req.address) {
        def.rom_low...(def.rom_middle - 1) => {
            const rom_idx: u16 = req.address - def.rom_low;
            req.applyAllowedRW(&self.rom_banks[self.rom_bank_low][rom_idx], 0xFF, 0x00);
        },
        def.rom_middle...(def.rom_high - 1) => {
            const rom_idx: u16 = req.address - def.rom_middle;
            const bank_highest: u10 = self.rom_bank_highest_bit;
            const bank_idx: u10 = self.rom_bank_high | (bank_highest << 8);
            req.applyAllowedRW(&self.rom_banks[bank_idx][rom_idx], 0xFF, 0x00);
        },
        def.cart_ram_low...(def.cart_ram_high - 1) => {
            if(!self.features.has_ram or self.ram_banks.len == 0) {
                std.log.info("Cart has no ram, but game tried to access to cart ram?. {f}", .{ req });
                req.reject();
                return;
            }
            const allowed: u8 = if(self.ram_enable) 0xFF else 0x00;
            const ram_idx: u16 = req.address - def.cart_ram_low;
            const mbc1_bank_idx: u16 = if(self.bank_mode == 1) self.ram_bank else 0;
            const bank_idx: u16 = if(self.features.mapper == .mbc_1) mbc1_bank_idx else self.ram_bank;
            req.applyAllowedRW(&self.ram_banks[bank_idx][ram_idx], allowed, allowed);
        },
        else => {},
    }
}

pub fn loadFile(self: *Self, io: std.Io, alloc: std.mem.Allocator, rom_path: []const u8, disable_saves: bool) void {
    // file
    const rom: []u8 = std.Io.Dir.cwd().readFileAlloc(io, rom_path, alloc, .unlimited) catch unreachable;
    defer alloc.free(rom);

    const rom_size: u8 = rom[header_rom_size];
    const header_rom_size_byte: u32 = rom_bank_size_byte * rom_bank_amount[rom_size];
    assert(header_rom_size_byte == rom.len);

    // rom
    const num_rom_banks: usize = rom.len / rom_bank_size_byte;
    self.rom_banks = alloc.alloc([rom_bank_size_byte]u8, num_rom_banks) catch unreachable;
    errdefer alloc.free(self.rom_banks);

    for(0..num_rom_banks) |bank_idx| {
        const start: u32 = @intCast(bank_idx * rom_bank_size_byte);
        const end: u32 = start + rom_bank_size_byte;
        @memcpy(&self.rom_banks[bank_idx], rom[start..end]);
    }

    self.rom_bank_low = 0;
    self.rom_bank_high = 1;
    self.rom_bank_highest_bit = 0;

    // ram
    const ram_size: u8 = rom[header_ram_size];
    const ram_size_byte: u32 = ram_bank_size_byte * ram_bank_amount[ram_size];
    const num_ram_banks: usize = ram_size_byte / ram_bank_size_byte;
    self.ram_banks = alloc.alloc([ram_bank_size_byte]u8, num_ram_banks) catch unreachable;
    errdefer alloc.free(self.ram_banks);

    self.ram_bank = 0;
    self.ram_enable = false;

    // mbc
    const cart_type: u8 = rom[header_cart_type];
    self.features = type_table[cart_type];
    self.ranges = info_table.get(self.features.mapper);
    self.bank_mode = 0;

    std.log.info("Rom Features: type: {X:0>2}, mapper: {}, rom_size: {}kByte, has_ram: {}, ram_size: {}kByte", .{ 
        cart_type, self.features.mapper, header_rom_size_byte / 1024, self.features.has_ram, ram_size_byte / 1024,
    });
    if((self.features.has_ram and self.ram_banks.len == 0) or 
        (!self.features.has_ram and self.ram_banks.len != 0)) {
        std.log.info("Cart Header and Ram size do not match. Would be ignored by real gameboy.", .{});
    }
    assert(self.features.mapper != .unsupported);
    if(self.features.mapper == .mbc_1 and rom.len > (512 * 1024)) {
        std.log.err("MBC1 Rom with more than 512kByte is not supported (alternative wiring)", .{});
        unreachable;
    }

    // savegame
    const save_path: []const u8 = getSavePath(alloc, rom_path);
    defer alloc.free(save_path);

    // TODO: Consider just using std.Io.Dir.cwd().readFileAlloc() and do nothing on the file not found error?
    const save_file: ?std.Io.File = std.Io.Dir.cwd().openFile(io, save_path, .{}) catch |err| blk: {
        switch(err) { error.FileNotFound => break: blk null, else => unreachable, }
    };
    defer if(save_file) |file| file.close(io);

    if(self.features.has_battery and self.features.has_ram and save_file != null and !disable_saves) { // Savegame ram.
        var file_reader: std.Io.File.Reader = save_file.?.reader(io, &.{});
        const save_content: []const u8 = file_reader.interface.allocRemaining(alloc, .unlimited) catch unreachable;
        defer alloc.free(save_content);

        for(0..num_ram_banks) |bank_idx| {
            const start: u32 = @intCast(bank_idx * ram_bank_size_byte);
            const end: u32 = start + ram_bank_size_byte;
            @memcpy(&self.ram_banks[bank_idx], save_content[start..end]);
        }
    } else { // Default ram.
        for(0..num_ram_banks) |bank_idx| {
            @memset(&self.ram_banks[bank_idx], 0);
        }
    }
}

pub fn getSavePath(alloc: std.mem.Allocator, rom_path: []const u8) []const u8 {
    var iter = std.mem.splitAny(u8, rom_path, ".");
    return std.fmt.allocPrint(alloc, "{s}.{s}", .{ iter.first(), "sav" }) catch unreachable;
}
