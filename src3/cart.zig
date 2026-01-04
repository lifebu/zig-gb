const std = @import("std");
const assert = std.debug.assert;

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

const header_cart_type: u16 = 0x147;
const header_rom_size: u16 = 0x148;
const header_ram_size: u16 = 0x149; 

const rom_bank_size_byte: u32 = 16 * 1024;
const rom_size_visible: u32 = 2 * rom_bank_size_byte;
const rom_bank_amount = [_]u10 { 2, 4, 8, 16, 32, 64, 128, 256, 512 };
const ram_bank_size_byte: u32 = 8 * 1024;
const ram_size_visible: u32 = ram_bank_size_byte;
const ram_bank_amount = [_]u10 { 0, 0, 1, 4, 16, 8, };

// TODO: Maybe we need more information about the supported features, like an mbc3 that supports timer or not?
const Type = enum(u3) {
    unsupported = 0, no_mbc, mbc_1, mbc_3, mbc_5,
};
const type_table: [28]Type = .{
    .no_mbc,
    .mbc_1, .mbc_1, .mbc_1,
    .unsupported, .unsupported, // mbc_2
    .unsupported, .unsupported, // unused
    .unsupported, .unsupported, .unsupported, // mmm
    .mbc_3, .mbc_3, .mbc_3, .mbc_3, .mbc_3,
    .mbc_5, .mbc_5, .mbc_5, .mbc_5, .mbc_5, .mbc_5,
    .unsupported, // mbc_6
    .unsupported, // mbc_7
    .unsupported, // pocket_camera
    .unsupported, // bandai_tama_5
    .unsupported, // huc_3
    .unsupported, // huc_1
};

const TypeRange = struct {
    low: u16, high: u16,
};
pub fn isInRange(range: ?TypeRange, value: u16) bool {
    return range != null and value >= range.?.low and value <= range.?.high; 
}
const TypeInfo = struct {
    ram_enable: ?TypeRange = null,
    rom_bank: ?TypeRange = null,
    rom_bank_msb: ?TypeRange = null,
    ram_bank: ?TypeRange = null,
    bank_mode: ?TypeRange = null,
    rtc: ?TypeRange = null,
};
const info_table: std.EnumArray(Type, TypeInfo) = .{ .values = .{
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
    },
    // mbc_3
    .{
        .ram_enable =   .{ .low = 0x0000, .high = 0x1FFF },
        .rom_bank =     .{ .low = 0x2000, .high = 0x3FFF },
        .ram_bank =     .{ .low = 0x4000, .high = 0x5FFF },
        .rtc =          .{ .low = 0x6000, .high = 0x7FFF },
    },
    // mbc_5
    .{
        .ram_enable =   .{ .low = 0x0000, .high = 0x1FFF },
        .rom_bank =     .{ .low = 0x2000, .high = 0x2FFF },
        .rom_bank_msb = .{ .low = 0x3000, .high = 0x3FFF },
        .ram_bank =     .{ .low = 0x4000, .high = 0x5FFF },
    },
}};

pub const State = struct {
    // rom
    rom_banks: [][rom_bank_size_byte]u8 = undefined,
    rom_bank_low: u9 = 0,
    rom_bank_high: u9 = 1,

    // ram
    ram_enable: bool = false,
    ram_banks: [][ram_bank_size_byte]u8 = undefined,
    ram_bank: u4 = 0,

    // mbc
    type: Type = .no_mbc,
    type_info: TypeInfo = undefined,
    bank_mode: u1 = 0,
};

pub fn init(state: *State) void {
    state.* = .{};
}

pub fn deinit(state: *State, alloc: std.mem.Allocator) void {
    alloc.free(state.rom_banks);
    alloc.free(state.ram_banks);
}

pub fn request(state: *State, req: *def.Request) void {
    // mbc
    if (isInRange(state.type_info.ram_enable, req.address) and req.isWrite()) {
        // TODO: This also enables access to the RTC registers.
        state.ram_enable = @as(u4, @truncate(req.value.write)) == 0xA;

    } else if (isInRange(state.type_info.rom_bank, req.address) and req.isWrite()) {
        const mask: u9 = @intCast(state.rom_banks.len - 1);
        state.rom_bank_high = @truncate(@max(1, req.value.write) & mask);

    } else if (isInRange(state.type_info.rom_bank_msb, req.address) and req.isWrite()) {
        std.debug.print("Highest ROM bit not supported!\n", .{});
        unreachable;

    } else if (isInRange(state.type_info.ram_bank, req.address) and req.isWrite()) {
        // TODO: MBC_3 Writing 0x08-0x0C to this register does not map a ram bank to A000-BFFF but a single RTC Register to that range (read/write).
        // Depending on what you write you can access different registers.
        if(state.ram_banks.len == 0 or state.ram_banks.len == 1) {
            return;
        }
        const mask: u9 = @intCast(state.ram_banks.len - 1);
        state.ram_bank = @truncate(req.value.write & mask);

    } else if (isInRange(state.type_info.bank_mode, req.address) and req.isWrite()) {
        // TODO: Implement banking mode for mbc_1.
        state.bank_mode = @truncate(req.value.write);
        std.debug.print("MBC1 Bankmode not supported!\n", .{});
        unreachable;

    } else if (isInRange(state.type_info.rtc, req.address) and req.isWrite()) {
        // TODO: Writing 00 followed by 01. The current time becomes "latched" into the RTC registers.
        // That "latched" data will not change until you do it again by repeating this pattern.
        // This way you can read the RTC registers while the clocks keeps ticking.

    }

    // memory
    switch(req.address) {
        mem_map.rom_low...(mem_map.rom_middle - 1) => {
            if(req.isWrite()) {
                req.reject();
            } else {
                const rom_idx: u16 = req.address - mem_map.rom_low;
                req.apply(&state.rom_banks[state.rom_bank_low][rom_idx]);
            }
        },
        mem_map.rom_middle...(mem_map.rom_high - 1) => {
            if(req.isWrite()) {
                req.reject();
            } else {
                const rom_idx: u16 = req.address - mem_map.rom_middle;
                req.apply(&state.rom_banks[state.rom_bank_high][rom_idx]);
            }
        },
        mem_map.cart_ram_low...(mem_map.cart_ram_high - 1) => {
            if(!state.ram_enable or state.ram_banks.len == 0) {
                req.reject();
            } else {
                const ram_idx: u16 = req.address - mem_map.cart_ram_low;
                req.apply(&state.ram_banks[state.ram_bank][ram_idx]);
            }
        },
        else => {},
    }
}

// TODO: not a great solution to handle the loading and initializing of the emulator, okay for now.
pub fn loadDump(state: *State, path: []const u8, file_type: def.FileType, alloc: std.mem.Allocator) void {
    switch(file_type) {
        .gameboy => {
            // TODO: Check if the cart_features even support ram and don't just use the ram size.
            // TODO: Also check that the RAM size as the MBC would be able to support it.

            // file
            const file = std.fs.openFileAbsolute(path, .{}) catch unreachable;
            defer file.close();

            const rom: []u8 = file.readToEndAlloc(alloc, std.math.maxInt(u32)) catch unreachable;
            defer alloc.free(rom);

            const rom_size: u8 = rom[header_rom_size];
            const header_rom_size_byte: u32 = rom_bank_size_byte * rom_bank_amount[rom_size];
            assert(header_rom_size_byte == rom.len);

            // rom
            const num_rom_banks: usize = rom.len / rom_bank_size_byte;
            state.rom_banks = alloc.alloc([rom_bank_size_byte]u8, num_rom_banks) catch unreachable;
            errdefer alloc.free(state.rom_banks);

            for(0..num_rom_banks) |bank_idx| {
                const start: u32 = @intCast(bank_idx * rom_bank_size_byte);
                const end: u32 = start + rom_bank_size_byte;
                @memcpy(&state.rom_banks[bank_idx], rom[start..end]);
            }

            state.rom_bank_low = 0;
            state.rom_bank_high = 1;

            // ram
            const ram_size: u8 = rom[header_ram_size];
            const ram_size_byte: u32 = ram_bank_size_byte * ram_bank_amount[ram_size];
            const num_ram_banks: usize = ram_size_byte / ram_bank_size_byte;
            state.ram_banks = alloc.alloc([ram_bank_size_byte]u8, num_ram_banks) catch unreachable;
            errdefer alloc.free(state.ram_banks);

            for(0..num_ram_banks) |bank_idx| {
                @memset(&state.ram_banks[bank_idx], 0);
            }

            state.ram_bank = 0;
            state.ram_enable = false;

            // mbc
            const cart_type: u8 = rom[header_cart_type];
            state.type = type_table[cart_type];
            state.type_info = info_table.get(state.type);
            state.bank_mode = 0;
        },
        .dump => {},
        .unknown => {},
    }
}
