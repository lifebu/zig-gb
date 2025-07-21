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

pub fn request(state: *State, bus: *def.Bus) void {
    if (bus.read) |read_addr| {
        switch (read_addr) {
            mem_map.wram_low...(mem_map.wram_high - 1) => {
                const wram_addr = read_addr - mem_map.wram_low;
                bus.data.* = state.work_ram[wram_addr];
                bus.read = null;
            },
            mem_map.echo_low...mem_map.echo_high => {
                const echo_addr = read_addr - mem_map.echo_low;
                bus.data.* = state.work_ram[echo_addr];
                bus.read = null;
            },
            else => {},
        }
    } 
    else if (bus.write) |write_addr| {
        switch (write_addr) {
            mem_map.wram_low...(mem_map.wram_high - 1) => {
                const wram_addr = write_addr - mem_map.wram_low;
                state.work_ram[wram_addr] = bus.data.*;
                bus.read = null;
            },
            mem_map.echo_low...mem_map.echo_high => {
                const echo_addr = write_addr - mem_map.echo_low;
                state.work_ram[echo_addr] = bus.data.*;
                bus.read = null;
            },
            else => {},
        }
    } 
}
