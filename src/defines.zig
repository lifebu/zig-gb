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
    // TODO: Use an optional address or something. This invalid address creates issues with tests.
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
            .read => |read|   try writer.print("{s}: {X:0>4} ({s}) -> {any:0>2}", .{ @tagName(self.requestor), self.address, getMemoryRangeName(self.address), read }),
            .write => |write| try writer.print("{s}: {X:0>2} -> {X:0>4} ({s})", .{ @tagName(self.requestor), write, self.address, getMemoryRangeName(self.address) }),
        }
    }
    pub fn logAndReject(self: *Request) void {
        if (self.isValid()) std.log.info("r/w lost: {f}", .{ self });
        self.reject();
    }
};

// Ranges are: [LOW, HIGH) (high excluding!). 
pub const rom_low: u16          = 0x0000;
pub const rom_middle: u16       = 0x4000;
pub const rom_high: u16         = 0x8000;
pub const rom_header: u16       = 0x0100;

pub const vram_low: u16         = 0x8000;
pub const vram_high: u16        = 0xA000;

pub const cart_ram_low: u16     = 0xA000;
pub const cart_ram_high: u16    = 0xC000;

pub const wram_low: u16         = 0xC000;
pub const wram_high: u16        = 0xE000;

pub const echo_low: u16         = 0xE000;
pub const echo_high: u16        = 0xFE00;

pub const oam_low: u16          = 0xFE00;
pub const oam_high: u16         = 0xFEA0;

pub const unused_low: u16       = 0xFEA0;
pub const unused_high: u16      = 0xFF00;

pub const high_page: u16        = 0xFF00;

pub const hram_low: u16         = 0xFF80;
pub const hram_high: u16        = 0xFFFF;

pub const audio_low: u16        = 0xFF10;
pub const audio_high: u16       = 0xFF40;

pub const io_low: u16           = 0xFF00;
pub const io_high: u16          = 0xFF80;

pub fn getMemoryRangeName(addr: u16) []const u8 {
    return switch(addr) {
        rom_low...(rom_middle - 1) => "rom_low",
        rom_middle...(rom_high - 1) => "rom_high",
        vram_low...(vram_high - 1) => "vram",
        cart_ram_low...(cart_ram_high - 1) => "cart_ram",
        wram_low...(wram_high - 1) => "wram",
        echo_low...(echo_high - 1) => "echo",
        oam_low...(oam_high - 1) => "oam",
        unused_low...(unused_high - 1) => "unused",
        hram_low...(hram_high - 1) => "hram",
        io_low...(io_high - 1) => "io",
        else => "undefined",
    };
}

// io
pub const joypad: u16           = 0xFF00;
pub const serial_data: u16      = 0xFF01;
pub const serial_control: u16   = 0xFF02;
pub const divider: u16          = 0xFF04;
pub const timer: u16            = 0xFF05;
pub const timer_mod: u16        = 0xFF06;
pub const timer_control: u16    = 0xFF07;
pub const interrupt_flag: u16   = 0xFF0F;

pub const ch1_low: u16          = 0xFF10;
pub const ch1_sweep: u16        = 0xFF10;
pub const ch1_length: u16       = 0xFF11;
pub const ch1_volume: u16       = 0xFF12;
pub const ch1_low_period: u16   = 0xFF13;
pub const ch1_high_period: u16  = 0xFF14;
pub const ch1_high: u16         = 0xFF14;

pub const ch2_low: u16          = 0xFF16;
pub const ch2_length: u16       = 0xFF16;
pub const ch2_volume: u16       = 0xFF17;
pub const ch2_low_period: u16   = 0xFF18;
pub const ch2_high_period: u16  = 0xFF19;
pub const ch2_high: u16         = 0xFF19;

pub const ch3_low: u16          = 0xFF1A;
pub const ch3_dac: u16          = 0xFF1A;
pub const ch3_length: u16       = 0xFF1B;
pub const ch3_volume: u16       = 0xFF1C;
pub const ch3_low_period: u16   = 0xFF1D;
pub const ch3_high_period: u16  = 0xFF1E;
pub const ch3_high: u16         = 0xFF1E;

pub const ch4_low: u16          = 0xFF20;
pub const ch4_length: u16       = 0xFF20;
pub const ch4_volume: u16       = 0xFF21;
pub const ch4_freq: u16         = 0xFF22;
pub const ch4_control: u16      = 0xFF23;
pub const ch4_high: u16         = 0xFF23;

pub const master_volume: u16    = 0xFF24;
pub const sound_panning: u16    = 0xFF25;
pub const sound_control: u16    = 0xFF26;
pub const wave_low: u16         = 0xFF30;
pub const wave_high: u16        = 0xFF40;

pub const lcd_control: u16      = 0xFF40;
pub const lcd_stat: u16         = 0xFF41;
pub const scroll_y: u16         = 0xFF42;
pub const scroll_x: u16         = 0xFF43;
pub const lcd_y: u16            = 0xFF44;
pub const lcd_y_compare: u16    = 0xFF45;
pub const dma: u16              = 0xFF46;
pub const bg_palette: u16       = 0xFF47;
pub const obj_palettes_dmg: u16 = 0xFF48;
pub const obj_palette_0: u16    = 0xFF48;
pub const obj_palette_1: u16    = 0xFF49;
pub const boot_rom: u16         = 0xFF50;
pub const window_y: u16         = 0xFF4A;
pub const window_x: u16         = 0xFF4B;

pub const interrupt_enable: u16 = 0xFFFF;

// interrupts
pub const interrupt_vblank: u8  = 0x01; 
pub const interrupt_lcd: u8     = 0x02; 
pub const interrupt_timer: u8   = 0x04; 
pub const interrupt_serial: u8  = 0x08; 
pub const interrupt_joypad: u8  = 0x10; 

// vram
pub const vram_size = vram_high - vram_low;
pub const oam_size_byte = oam_high - oam_low;

pub const tile_map_9800 = 0x9800;
pub const tile_map_9C00 = 0x9C00;
pub const vram_tile_map_9800 = tile_map_9800 - vram_low;
pub const vram_tile_map_9C00 = tile_map_9C00 - vram_low;

pub const tile_8000 = 0x8000;
pub const tile_8800 = 0x8800;
pub const vram_tile_8000 = tile_8000 - vram_low;
pub const vram_tile_8800 = tile_8800 - vram_low;

pub const tile_size_x = 8;
pub const tile_size_y = 8;
pub const tile_size_byte = 16;

pub const tile_map_size_x = 32;
pub const tile_map_size_y = 32;
pub const tile_map_size_byte = tile_map_size_x * tile_map_size_y;
pub const tile_map_pixel_size_x = tile_map_size_x * tile_size_x;
pub const tile_map_pixel_size_y = tile_map_size_y * tile_size_y;


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
pub const scaling = 4;

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
// Note: GB: 59.73Hz, Platform: 60Hz
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
pub const SampleFifo = Fifo.RingbufferFifo(Sample, samples_per_frame); // ~70

// memory
pub const addr_space = 0x1_0000;
pub const boot_rom_size = 256;
