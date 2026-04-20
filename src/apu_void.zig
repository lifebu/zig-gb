const std = @import("std");

const def = @import("defines.zig");

const Self = @This();

const apu_channels = 4;
const ch3_wave_table_size = def.wave_high - def.wave_low;

// general
pub const Control = packed struct(u8) {
    ch1_on: bool = false, ch2_on: bool = false, ch3_on: bool = false, ch4_on: bool = false,
    _: u3 = 0, enable_apu: bool = false,
};
pub const Volume = packed struct(u8) {
    right_volume: u3 = 0, vin_right: bool = false,
    left_volume: u3 = 0,  vin_left: bool = false,
};
pub const Panning = packed struct(u8) {
    ch1_right: bool = false, ch2_right: bool = false, ch3_right: bool = false, ch4_right: bool = false,
    ch1_left: bool = false,  ch2_left: bool = false,  ch3_left: bool = false,  ch4_left: bool = false,
};

// channel 1, channel 2
pub const Channel1Sweep = packed struct(u8) {
    step: u3 = 0, decrease: bool = false, pace: u3 = 0, _: u1 = 0,
};
pub const Channel12Length = packed struct(u8) {
    length_init: u6 = 0, duty_cycle: u2 = 0,
};
pub const Channel124Volume = packed struct(u8) {
    pace: u3 = 0, increase: bool = false, initial: u4 = 0,
};
pub const Channel12PeriodLow = packed struct(u8) {
    period: u8 = 0,
};
pub const Channel12PeriodHigh = packed struct(u8) {
    period: u3 = 0, _: u3 = 0, length_on: bool = false, trigger: bool = false,  
};

// channel 3
pub const Channel3Dac = packed struct(u8) {
    _: u7 = 0, dac_on: bool = false,
};
pub const Channel3Length = packed struct(u8) {
    initial: u8 = 0,
};
pub const Channel3Volume = packed struct(u8) {
    _: u5 = 0, shift: u2 = 0, __: u1 = 0, 
};
pub const Channel3PeriodLow = packed struct(u8) {
    period: u8 = 0,
};
pub const Channel3PeriodHigh = packed struct(u8) {
    period: u3 = 0, _: u3 = 0, length_on: bool = false, trigger: bool = false,
};

// channel 4
pub const Channel4Length = packed struct(u8) {
    initial: u6 = 0, _: u2 = 0,
};
pub const Channel4Freq = packed struct(u8) {
    divider: u3 = 0, is_short: bool = false, shift: u4 = 0,
};
pub const Channel4Control = packed struct(u8) {
    __: u6 = 0, length_on: bool = false, trigger: bool = false, 
};
const LFSR = packed union {
    value: u16,
    bits: packed struct {
        b0: u1, b1: u1, _: u5 = 0, b7: u1, __: u7 = 0, b15: u1,
    },
};


control: Control = .{},
volume: Volume = .{},
panning: Panning = .{},

ch1_sweep: Channel1Sweep = .{},
ch1_length: Channel12Length = .{},
ch1_volume: Channel124Volume = .{},
ch1_period_low: Channel12PeriodLow = .{},
ch1_period_high: Channel12PeriodHigh = .{},

ch2_length: Channel12Length = .{},
ch2_volume: Channel124Volume = .{},
ch2_period_low: Channel12PeriodLow = .{},
ch2_period_high: Channel12PeriodHigh = .{},

ch3_dac: Channel3Dac = .{},
ch3_length: Channel3Length = .{},
ch3_volume: Channel3Volume = .{},
ch3_period_low: Channel3PeriodLow = .{},
ch3_period_high: Channel3PeriodHigh = .{},
ch3_wave_table: [ch3_wave_table_size]u8 = @splat(0),

ch4_length: Channel4Length = .{},
ch4_volume: Channel124Volume = .{},
ch4_freq: Channel4Freq = .{},
ch4_control: Channel4Control = .{},

samples: def.SampleFifo = .{},

pub const empty: Self = .{};

pub fn init(self: *Self, _: def.ApuPlugin) void {
    self.* = .{};
}

pub fn request(self: *Self, req: *def.Request) void {
    switch(req.address) {
        def.sound_panning => { req.apply(&self.panning); },
        def.master_volume => { req.apply(&self.volume); },
        def.sound_control => { req.applyAllowedRW(&self.control, 0x8F, 0x80); },
        def.ch1_sweep => { req.applyAllowedRW(&self.ch1_sweep, 0x7F, 0xFF); },
        def.ch1_length => { req.applyAllowedRW(&self.ch1_length, 0xC0, 0xFF); },
        def.ch1_volume => { req.apply(&self.ch1_volume); },
        def.ch1_low_period => { req.applyAllowedRW(&self.ch1_period_low, 0x00, 0xFF); },
        def.ch1_high_period => { req.applyAllowedRW(&self.ch1_period_high, 0x40, 0xC7); },
        def.ch2_length => { req.applyAllowedRW(&self.ch2_length, 0xC0, 0xFF); },
        def.ch2_volume => { req.apply(&self.ch2_volume); },
        def.ch2_low_period => { req.applyAllowedRW(&self.ch2_period_low, 0x00, 0xFF); },
        def.ch2_high_period => { req.applyAllowedRW(&self.ch2_period_high, 0x40, 0xC7); },
        def.ch3_length => { req.applyAllowedRW(&self.ch3_length, 0x00, 0xFF); },
        def.ch3_volume => { req.applyAllowedRW(&self.ch3_volume, 0x60, 0x60); },
        def.ch3_low_period => { req.applyAllowedRW(&self.ch3_period_low, 0x00, 0xFF); },
        def.ch3_dac => { req.applyAllowedRW(&self.ch3_dac, 0x80, 0x80); },
        def.ch3_high_period => { req.applyAllowedRW(&self.ch3_period_high, 0x40, 0xC7); },
        def.wave_low...(def.wave_high - 1) => { req.apply(&self.ch3_wave_table[req.address - def.wave_low]); },
        def.ch4_length => { req.applyAllowedRW(&self.ch4_length, 0x00, 0x3F); },
        def.ch4_volume => { req.apply(&self.ch4_volume); },
        def.ch4_freq => { req.apply(&self.ch4_freq); },
        def.ch4_control => { req.applyAllowedRW(&self.ch4_control, 0x40, 0xC0); },
        else => {},
    }
}

pub fn cycle(self: *Self) void {
    _ = self;
}

pub fn getSamples(self: *Self) *def.SampleFifo {
    return &self.samples;
}
