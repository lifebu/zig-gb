const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

pub const State = struct {
    soc_bus: def.Bus = .{},
    external_bus: def.Bus = .{},
    interrupt_flag: u8 = 0,
};

pub fn init(_: *State) void {
}

pub fn cycle(state: *State, single_bus: def.Bus) void {
    if(single_bus.address()) |address| {
        switch (address) {
            0x0000...0xFEFF => {
                state.external_bus = single_bus;
            },
            0xFF00...0xFFFF => {
                state.soc_bus = single_bus;
            },
        }
    }
}

pub fn request(state: *State, bus: *def.Bus) void {
    if (bus.read) |read_addr| {
        switch (read_addr) {
            mem_map.interrupt_flag => {
                bus.data.* = state.interrupt_flag;
                bus.read = null;
            },
            else => {},
        }
    } 

    if (bus.write) |write_addr| {
        switch (write_addr) {
            mem_map.interrupt_flag => {
                state.interrupt_flag = bus.data.*;
                bus.write = null;
            },
            else => {},
        }
    } 
}
