const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

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

pub fn request(state: *State, req: *def.Request) void {
    // TODO: Move this logic to the cart.zig?
    // TODO: Can I implement the mapping better, so that I don't have a late check like this?
    if(!state.rom_enabled) {
        return;
    }

    switch (req.address) {
        0...(def.boot_rom_size - 1) => {
            if(req.isWrite()) {
                req.reject();
            } else {
                const rom_idx: u16 = req.address - 0;
                req.apply(&state.rom[rom_idx]);
            }
        },
        mem_map.boot_rom => {
            req.reject(); // TODO: Should subsequent reads be able to read this?
            if(req.isWrite()) {
                state.rom_enabled = false;
            }
        },
        else => {},
    }
}
