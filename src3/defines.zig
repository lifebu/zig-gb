const std = @import("std");
const Keycode = @import("sokol").app.Keycode;

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
pub const open_bus: u8 = 0xFF;
pub const Request = struct {
    const invalid_addr: u16 = 0xFEED;

    address: u16 = invalid_addr,
    // TODO: Some systems want to implement "only some bits are read/write". How could I do that?
    value: union(enum) {
        read: *u8,
        write: u8,
    } = .{ .read = &void_byte },
    requestor: enum {
        unknown, cpu, dma
    } = .unknown,

    pub fn apply(self: *Request, value: anytype) void {
        if(!self.isValid()) {
            return; // TODO: Should this be an error?
        }

        switch (self.value) {
            .read => |read| read.* = @bitCast(value.*),
            .write => |write| value.* = @bitCast(write),
        }
        self.address = invalid_addr;
    }
    pub fn reject(self: *Request) void {
        var value: u8 = open_bus;
        self.apply(&value);
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

// graphics
pub const Palette = struct {
    color_0: [3]u8 = .{ 224, 248, 208 },
    color_1: [3]u8 = .{ 136, 192, 112 },
    color_2: [3]u8 = .{ 52, 104, 86 },
    color_3: [3]u8 = .{ 8, 24, 32 },
};

pub const resolution_width = 160;
pub const resolution_height = 144;
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
pub const t_cycles_per_m_cycle = 4;
pub const config_path = "config.zon";

// audio
pub const sample_rate = 44_100;
pub const t_cycles_per_sample = (system_freq / sample_rate);

pub const Sample = struct {
    left: f32 = 0.0, right: f32 = 0.0,
};

// memory
pub const addr_space = 0x1_0000;
pub const boot_rom_size = 256;
