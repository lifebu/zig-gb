const std = @import("std");

const mem_map = @import("mem_map.zig");

pub const Bus = struct {
    // TODO: As the bus can be either read or write, not both, could we make this struct smaller by having a tagged union / variant of read/write?
    read: ?u16 = null,
    write: ?u16 = null,
    data: *u8 = undefined,

    const Self = @This();
    pub fn print(self: *Self) []u8 {
        var buf: [3]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{s}{s}{s}", .{ 
            if(self.read == null) "-" else "R", 
            if(self.write == null) "-" else "W", 
            if(self.read == null and self.write == null) "-" else "M" 
        }) catch unreachable;
        return &buf;
    }

    // TODO: Try to implement all reads/writes of the bus and then decide how we can create functions to reduce boilerplate!
    pub fn address(self: *Self) ?u16 {
        return if(self.read != null) self.read.? 
            else if(self.write != null) self.write.? 
            else null;
    }
    pub fn apply(self: *Self, value: u8) u8 {
        if(self.read) |_| {
            self.data.* = value;
            self.read = null;
            return value;
        }
        if(self.write) |_| {
            self.write = null;
            return self.data.*;
        }
        unreachable; 
    }
};

pub const State = struct {
    soc_bus: Bus = .{},
    external_bus: Bus = .{},
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
