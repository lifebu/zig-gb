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

pub fn cycle(_: *State) void {
}

pub fn request(state: *State) void {
    if (state.soc_bus.read) |read_addr| {
        switch (read_addr) {
            mem_map.interrupt_flag => {
                state.soc_bus.data.* = state.interrupt_flag;
                state.soc_bus.read = null;
            },
            else => {},
        }
    } 

    if (state.soc_bus.write) |write_addr| {
        switch (write_addr) {
            mem_map.interrupt_flag => {
                state.interrupt_flag = state.soc_bus.data.*;
                state.soc_bus.write = null;
            },
            else => {},
        }
    } 
}
