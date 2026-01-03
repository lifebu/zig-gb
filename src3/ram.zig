const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

const work_ram_size = mem_map.wram_high - mem_map.wram_low;

pub const State = struct {
    work_ram: [work_ram_size]u8 = undefined,
};

pub fn init(state: *State) void {
    state.work_ram = [_]u8{ 0 } ** work_ram_size;
}

pub fn cycle(_: *State) void {
}

pub fn request(state: *State, req: *def.Request) void {
    switch (req.address) {
        mem_map.wram_low...(mem_map.wram_high - 1) => {
            const wram_idx: u16 = req.address - mem_map.wram_low;
            req.apply(&state.work_ram[wram_idx]);
        },
        mem_map.echo_low...(mem_map.echo_high - 1) => {
            const wram_idx: u16 = req.address - mem_map.echo_low;
            req.apply(&state.work_ram[wram_idx]);
        },
        else => {},
    }
}
