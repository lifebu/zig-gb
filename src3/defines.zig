const std = @import("std");
const Keycode = @import("sokol").app.Keycode;

const Fifo = @import("util/fifo.zig");

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

pub const Keybinds = struct {
    key_up: Keycode = .UP,
    key_down: Keycode = .DOWN,
    key_left: Keycode = .LEFT,
    key_right: Keycode = .RIGHT,
    key_start: Keycode = .W,
    key_select: Keycode = .S,
    key_a: Keycode = .A,
    key_b: Keycode = .D,
};

// memory
var void_byte: u8 = 0x00;
pub const Request = struct {
    const invalid_addr: u16 = 0xFEED;

    address: u16 = invalid_addr,
    // TODO: Some systems want to implement "only some bits are read/write". How could I do that?
    // Maybe with an optional mask bits used in apply?
    value: union(enum) {
        read: *u8,
        write: u8,
    } = .{ .read = &void_byte },
    requestor: enum {
        unknown, cpu, dma
    } = .unknown,

    /// Use the masks to specify which bits are allowed to be read from (returns 1 if not allowed) or written to.
    pub fn applyAllowedRW(self: *Request, value: anytype, mask_read: u8, mask_write: u8) void {
        if(!self.isValid()) return;
        self.address = invalid_addr;
        self.requestor = .unknown;

        const value_u8: u8 = @bitCast(value.*);
        switch (self.value) {
            .read => |read| {
                read.* = value_u8 | ~mask_read;
            },
            .write => |write| {
                const write_u8: u8 = @bitCast(write);
                value.* = @bitCast((value_u8 & ~mask_write) | (write_u8 & mask_write));
            },
        }
    }

    pub fn apply(self: *Request, value: anytype) void {
        self.applyAllowedRW(value, 0xFF, 0xFF);
    }
    pub fn reject(self: *Request) void {
        var temp: u8 = 0;
        self.applyAllowedRW(&temp, 0x00, 0x00);
    }
    pub fn isValid(self: *Request) bool {
        return self.address != invalid_addr;
    }
    pub fn isWrite(self: *Request) bool {
        return self.value == .write;
    }
    pub fn format(self: Request, writer: *std.io.Writer) std.io.Writer.Error!void {
        switch (self.value) {
            .read => |read|   try writer.print("{s}: {X:0>4} -> {any:0>2}", .{ @tagName(self.requestor), self.address, read }),
            .write => |write| try writer.print("{s}: {X:0>2} -> {X:0>4}", .{ @tagName(self.requestor), write, self.address }),
        }
    }
    pub fn logAndReject(self: *Request) void {
        if (self.isValid()) std.log.warn("r/w lost: {f}", .{ self });
        self.reject();
    }
};

// system
pub const GBModel = enum  { dmg };

// graphics
pub const Palette = struct {
    color_0: [3]u8 = .{ 224, 248, 208 },
    color_1: [3]u8 = .{ 136, 192, 112 },
    color_2: [3]u8 = .{ 52, 104, 86 },
    color_3: [3]u8 = .{ 8, 24, 32 },
};

// TODO: Make this array of u2 instead?
pub const default_color_ids: [overscan_resolution]u8 = @splat(0);

pub const resolution_width = 160;
pub const resolution_height = 144;
// TODO: configureable? How?
pub const scaling = 3;

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
pub const t_cycles_per_frame = 70_224;
pub const t_cycles_per_m_cycle = 4;
pub const config_path = "config.zon";

// audio
pub const sample_rate = 44_100;
pub const t_cycles_per_sample = (system_freq / sample_rate);
pub const samples_per_frame = t_cycles_per_frame / t_cycles_per_sample;

pub const Sample = struct {
    left: f32 = 0.0, right: f32 = 0.0,
};
pub const SampleFifo = Fifo.RingbufferFifo(Sample, samples_per_frame);

// memory
pub const addr_space = 0x1_0000;
pub const boot_rom_size = 256;
