const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");
const MMU = @import("mmu.zig");

pub const State = struct {
    rom: [def.boot_rom_size]u8 = [1]u8{0} ** def.boot_rom_size,
    rom_enabled: bool = false,
};

pub fn init(state: *State) void {
    // TODO: Which boot rom to use should be an option.
    // TODO: Not hard-coded relative paths like this?
    const file = std.fs.cwd().openFile("data/bootroms/dmg_boot.bin", .{}) catch unreachable;
    const len = file.readAll(&state.rom) catch unreachable;
    std.debug.assert(len == state.rom.len);
    state.rom_enabled = true;
}

pub fn cycle(state: *State, mmu: *MMU.State) void {
    // TODO: Move this logic to the cart.zig?
    // TODO: Can I implement the mapping better, so that I don't have a late check like this?
    if(!state.rom_enabled) {
        return;
    }
    // TODO: Need a better way to communicate memory ready and requests so that other systems like the dma don't need to know the mmu.
    // And split the on-write behavior and memory request handling from the cycle function?
    if(mmu.request.write) |address| {
        if(address == mem_map.boot_rom and mmu.request.data.* != 0) {
            // disable boot rom
            state.rom_enabled = false;
            mmu.request.write = null;
        }
    } else if (mmu.request.read) |address| {
        if(address >= 0 and address < def.boot_rom_size) {
            mmu.request.data.* = state.rom[address];
            mmu.request.read = null;
        }
    }
}
