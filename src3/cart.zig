const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");
// TODO: Remove that dependency.
const MMU = @import("mmu.zig");

const header_cart_type = 0x147;
const header_rom_size = 0x148;
const header_ram_size = 0x149; 

const rom_bank_size_byte: u32 = 16 * 1024;
const rom_bank_amount = [_]u10 { 2, 4, 8, 16, 32, 64, 128, 256, 512 };
const ram_bank_size_byte: u32 = 8 * 1024;
const ram_bank_amount = [_]u10 { 0, 0, 1, 4, 16, 8, };

const MBC = enum(u3) {
    unsupported = 0,
    no_mbc, mbc_1, mbc_3, mbc_5,
};
//- MBC Register ranges for: RAM Enable, Rom Bank Low, Rom Bank High (1bit), Ram Bank, Bank mode (MBC1).
const MBCTypeInfo = struct {
    ram_enable_low: u16 = 0xFFFF, ram_enable_high: u16 = 0xFFFF,
    rom_bank_low: u16 = 0xFFFF, rom_bank_high: u16 = 0xFFFF,
    rom_bank_msb_low: u16 = 0xFFFF, rom_bank_msb_high: u16 = 0xFFFF,
    ram_bank_low: u16 = 0xFFFF, ram_bank_high: u16 = 0xFFFF,
    bank_mode_low: u16 = 0xFFFF, bank_mode_high: u16 = 0xFFFF,
    rtc_low: u16 = 0xFFFF, rtc_high: u16 = 0xFFFF,
};
const mbc_type_table = [_]MBCTypeInfo {
    // unsupported
    MBCTypeInfo{ }, 
    // no_mbc
    MBCTypeInfo{ }, 
    // mbc_1
    MBCTypeInfo{ 
        .ram_enable_low = 0x0000, .ram_enable_high = 0x1FFF, 
        .rom_bank_low = 0x2000, .rom_bank_high = 0x3FFF, 
        .ram_bank_low = 0x4000, .ram_bank_high = 0x5FFF, 
        .bank_mode_low = 0x6000, .bank_mode_high = 0x7FFF 
    },
    // mbc_3
    MBCTypeInfo{ 
        .ram_enable_low = 0x0000, .ram_enable_high = 0x1FFF, 
        .rom_bank_low = 0x2000, .rom_bank_high = 0x3FFF, 
        .ram_bank_low = 0x4000, .ram_bank_high = 0x5FFF, 
        .rtc_low = 0x6000, .rtc_high = 0x7FFF 
    },
    // mbc_5
    MBCTypeInfo{ 
        .ram_enable_low = 0x0000, .ram_enable_high = 0x1FFF, 
        .rom_bank_low = 0x2000, .rom_bank_high = 0x2FFF, 
        .rom_bank_msb_low = 0x3000, .rom_bank_msb_high = 0x3FFF, 
        .ram_bank_low = 0x4000, .ram_bank_high = 0x5FFF, 
    },
};
// TODO: Maybe we need more information about the supported features, like an mbc3 that supports timer or not?
const cart_type_table = [_]MBC {
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

pub const State = struct {
    // TODO: Can we do this without an allocator?
    allocator: std.mem.Allocator = undefined,

    rom: []u8 = undefined,
    ram: ?[]u8 = null,

    mbc: MBC = .no_mbc,
    mbc_type_info: MBCTypeInfo = undefined,
    rom_size_byte: u32 = 0,
    ram_size_byte: u32 = 0,

    // TODO: Honestly not great, but works for now.
    zero_ram_bank: []u8 = undefined,
    // bool or u1?
    ram_enable: bool = false,
    rom_bank: u9 = 0x00,
    ram_bank: u4 = 0x0,
    bank_mode: u1 = 0x0,
};

pub fn init(state: *State, alloc: std.mem.Allocator) void {
    state.allocator = alloc;
}

pub fn deinit(state: *State) void {
    state.allocator.free(state.rom);
    if(state.ram) |ram| {
        state.allocator.free(ram);
    }
    state.allocator.free(state.zero_ram_bank);
}

pub fn cycle(state: *State, mmu: *MMU.State, request: *def.MemoryRequest) void {
    // TODO: Need a better way to communicate memory ready and requests so that other systems like the dma don't need to know the mmu.
    // And split the on-write behavior and memory request handling from the cycle function?
    if (request.write) |address| {
        if (address >= mem_map.rom_high ) {
            return;
        } 

        const data = request.data.*;
        if (address >= state.mbc_type_info.ram_enable_low and address <= state.mbc_type_info.ram_bank_high ) {
            // TODO: This also enables access to the RTC registers.
            state.ram_enable = @as(u4, @truncate(data)) == 0xA;
            ramChanged(state, mmu);
        } else if (address >= state.mbc_type_info.rom_bank_low and address <= state.mbc_type_info.rom_bank_high ) {
            // TODO: first 8 bits of rom bank.
            const num_banks: u9 = @truncate(state.rom_size_byte / rom_bank_size_byte);
            const mask: u9 = @intCast(num_banks - 1);
            state.rom_bank = @truncate(@max(1, data) & mask);
            romChanged(state, mmu);
        } else if (address >= state.mbc_type_info.rom_bank_msb_low and address <= state.mbc_type_info.rom_bank_msb_high ) {
            // TODO: highest 1 bit of rom bank.
            std.debug.print("Highest ROM bit not supported! \n", .{});
            unreachable;
        } else if (address >= state.mbc_type_info.ram_bank_low and address <= state.mbc_type_info.ram_bank_high ) {
            // TODO: MBC_3 Writing 0x08-0x0C to this register does not map a ram bank to A000-BFFF but a single RTC Register to that range (read/write).
            // Depending on what you write you can access different registers.
            const num_banks: u6 = @truncate(state.ram_size_byte / ram_bank_size_byte);
            // TODO: this better, this is just num_banks - 1 would underflow for one bank.
            if(num_banks == 1) {
                return; // Nothing to switch on 
            }

            const mask: u9 = @intCast(num_banks - 1);
            state.ram_bank = @truncate(data & mask);
            ramChanged(state, mmu);
        } else if (address >= state.mbc_type_info.rtc_low and address <= state.mbc_type_info.rtc_high ) {
            // TODO: Writing 00 followed by 01. The current time becomes "latched" into the RTC registers.
            // That "latched" data will not change until you do it again by repeating this pattern.
            // This way you can read the RTC registers while the clocks keeps ticking.
        }

        request.write = null;
    }
}

fn romChanged(state: *State, mmu: *MMU.State) void {
    // TODO: I am assuming that bank switches don't happen all the time.
    // And that it is cheaper to just copy 16kByte into the memory region then to 
    // reroute all reads into ROM and Cartridge RAM regions into the seperate piece of memory of the cartridge. 
    // But this needs to be tested!
    const rom_start: u32 = state.rom_bank * rom_bank_size_byte;
    const rom_end: u32 = rom_start + rom_bank_size_byte;
    std.mem.copyForwards(u8, mmu.memory[mem_map.rom_middle..mem_map.rom_high], state.rom[rom_start..rom_end]);
}

fn ramChanged(state: *State, mmu: *MMU.State) void {
    const ram = state.ram orelse {
        return;
    };

    // TODO: I am assuming that bank switches don't happen all the time.
    // And that it is cheaper to just copy 16kByte into the memory region then to 
    // reroute all reads into ROM and Cartridge RAM regions into the seperate piece of memory of the cartridge. 
    // But this needs to be tested!
    if(state.ram_enable) {
        const ram_start: u32 = state.ram_bank * ram_bank_size_byte;
        const ram_end: u32 = ram_start + ram_bank_size_byte;
        std.mem.copyForwards(u8, mmu.memory[mem_map.cart_ram_low..mem_map.cart_ram_high], ram[ram_start..ram_end]);
    } else {
        std.mem.copyForwards(u8, mmu.memory[mem_map.cart_ram_low..mem_map.cart_ram_high], state.zero_ram_bank);
    }
}

// TODO: not a great solution to handle the loading and initializing of the emulator, okay for now.
pub fn loadDump(state: *State, path: []const u8, file_type: def.FileType, mmu: *MMU.State) void {
    switch(file_type) {
        .gameboy => {
            const file = std.fs.openFileAbsolute(path, .{}) catch unreachable;

            // TODO: How to handle errors in the emulator?
            state.rom = file.readToEndAlloc(state.allocator, std.math.maxInt(u32)) catch unreachable;
            errdefer state.allocator.free(state.rom);

            // TODO: Check if the cart_features even support ram and don't just use the ram size.
            // TODO: Also check that the RAM size as the MBC would be able to support it.
            const rom_size: u8 = state.rom[header_rom_size];
            state.rom_size_byte = rom_bank_size_byte * rom_bank_amount[rom_size];
            const ram_size: u8 = state.rom[header_ram_size];
            state.ram_size_byte = ram_bank_size_byte * ram_bank_amount[ram_size];

            const cart_type: u8 = state.rom[header_cart_type];
            state.mbc = cart_type_table[cart_type];
            state.mbc_type_info = mbc_type_table[@intFromEnum(state.mbc)];

            // TODO: Do we really want to copy the content?
            // Initial copy of the first banks.
            std.mem.copyForwards(u8, mmu.memory[mem_map.rom_low..mem_map.rom_high], state.rom[0..2 * rom_bank_size_byte]);

            if(state.ram_size_byte != 0) {
                state.ram = state.allocator.alloc(u8, state.ram_size_byte) catch unreachable; 
                @memset(state.ram.?, 0);
                errdefer state.allocator.free(state.ram.?);
            }

            // TODO: This only exists if we don't have ram support. can I do this better?
            state.zero_ram_bank = state.allocator.alloc(u8, ram_bank_size_byte) catch unreachable;
            @memset(state.zero_ram_bank, 0xFF);
            errdefer state.allocator.free(state.zero_ram_bank);
        },
        .dump => {
        },
        .unknown => {
        }
    }
}
