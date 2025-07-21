const std = @import("std");

// input
// TODO: Is this optimal? Can we make it easier to calculate the dpad and button bytes?
pub const InputState = packed struct {
    right_pressed: bool = false,
    left_pressed: bool = false,
    up_pressed: bool = false,
    down_pressed: bool = false,

    a_pressed: bool = false,
    b_pressed: bool = false,
    select_pressed: bool = false,
    start_pressed: bool = false,
};

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

// TODO: Remove
pub const MemoryRequest = struct {
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
    pub fn getAddress(self: *Self) u16 {
        return if(self.read != null) self.read.? 
            else if(self.write != null) self.write.? 
            else 0;
    }
};

pub const FileType = enum{
    gameboy,
    dump,
    unknown
};

// graphics
pub const resolution_width = 160;
pub const resolution_height = 144;
pub const scaling = 5;

pub const window_width = resolution_width * scaling;
pub const window_height = resolution_height * scaling;

pub const tile_width = 8;
pub const overscan_width = resolution_width + tile_width;
pub const overscan_resolution = overscan_width * resolution_height;

pub const color_depth = 4;
pub const byte_per_line = 2;

// system
pub const system_freq = 4 * 1_024 * 1_024;
pub const t_cycles_in_60fps = system_freq / 60;
pub const t_cycles_per_m_cycle = 4;

// audio
// TODO: When I try to push stereo to sokol, i get super loud garbage data out? 
pub const num_channels = 1; 
pub const sample_rate = 48_000;
pub const t_cycles_per_sample = (system_freq / sample_rate);
pub const num_gb_samples = (t_cycles_in_60fps / t_cycles_per_sample) * num_channels;

// memory
pub const addr_space = 0x1_0000;
pub const boot_rom_size = 256;
