///! GB APU
///! Terminology: 
///! Tick: Value that is decreased each t-cycle, which executes something when it underflows.
///! Pace: Value that is decreased each function tick, executes something when it underflows.
///! Value: The current state of a channel or function.

const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

const Self = @This();

const apu_channels = 4;
// TODO: Pandocs talks about a DIV-APU that triggers those functions. When DIV is reset these might trigger again, so this is inprecise.
pub const t_cycles_per_volume_step = 65_536;
pub const t_cycles_per_period_step = 32_768;
pub const t_cycles_per_length_step = 16_384;
pub const ch1_2_t_cycles_per_period = 4;
pub const ch3_t_cycles_per_period = 2;
// TODO: Not sure if this would be correct. This value would generate a permanent -1.0 in the audio output.
pub const ch3_dac_off_value = 0;

const channel_length_table: [apu_channels]u8 = .{ 63, 63, 255, 63 };
const wave_duty_table: [4][8]u1 = .{
    .{ 1, 1, 1, 1, 1, 1, 1, 0 }, // 12.5%
    .{ 0, 1, 1, 1, 1, 1, 1, 0 }, // 25%
    .{ 0, 1, 1, 1, 1, 0, 0, 0 }, // 50%
    .{ 1, 0, 0, 0, 0, 0, 0, 1 }, // 75%
};
const lfsr_divisor_table: [8]u24 = .{ 8, 16, 32, 48, 64, 80, 16, 112 };
// TODO: Would be neat to have this debug feature user facing.
const channel_dbg_enable: [apu_channels]bool = .{ true, true, true, true };
const ch3_wave_table_size = mem_map.wave_high - mem_map.wave_low;

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

apu_on: bool = false,

sample_tick: u16 = def.t_cycles_per_sample - 1, 
channel_values: [apu_channels]u4 = @splat(0),
// TODO: duplicated with control register above.
channels_on: [apu_channels]bool = @splat(false),

func_volume_tick: u16 = t_cycles_per_volume_step - 1,
func_volume_paces: [apu_channels]u4 = @splat(0),
func_volume_values: [apu_channels]u4 = @splat(0),

func_length_tick: u14 = t_cycles_per_length_step - 1,
// Note: [2] is unused. Not support by ch3.
func_length_values: [apu_channels]u8 = @splat(0),
func_length_on: [apu_channels]bool = @splat(false),

func_period_tick: u15 = t_cycles_per_period_step - 1,
// Note: Each channel requires at least: [u13, u13, u12, u24]
// TODO: u24 does not seem to be hardware accurate. Sameboy uses "a counter (8bit) for a counter (16bit)". Which matches the lfsr_shift being a u4.
func_period_values: [apu_channels]u24 = @splat(0),
func_period_shadow: u11 = 0,
func_period_pace: u4 = 0,
func_period_on: bool = false,

ch1_duty_idx: u3 = 0,
ch2_duty_idx: u3 = 0,
ch3_wave_ram_idx: u5 = 0,
ch4_lfsr: LFSR = .{ .value = 0 },

samples: def.SampleFifo = .{},


pub fn init(self: *Self) void {
    self.* = .{};
}

pub fn request(self: *Self, req: *def.Request) void {
    switch(req.address) {
        mem_map.sound_panning => { req.apply(&self.panning); },
        mem_map.master_volume => { req.apply(&self.volume); },
        mem_map.sound_control => { req.applyAllowedRW(&self.control, 0x8F, 0x80);
            // TODO: Turning of apu leads to:
            // all APU registers are cleared but read-only, except sound_control.
            // Wave RAM can still be written to.
            self.apu_on = self.control.enable_apu;
        },
        mem_map.ch1_sweep => { req.applyAllowedRW(&self.ch1_sweep, 0x7F, 0xFF); },
        mem_map.ch1_length => { req.applyAllowedRW(&self.ch1_length, 0xC0, 0xFF); },
        mem_map.ch1_volume => { req.apply(&self.ch1_volume); },
        mem_map.ch1_low_period => { req.applyAllowedRW(&self.ch1_period_low, 0x00, 0xFF); },
        mem_map.ch1_high_period => { req.applyAllowedRW(&self.ch1_period_high, 0x40, 0xC7 );
            if(req.isWrite()) {
                if(self.ch1_period_high.trigger) {
                    const period: u11 = self.ch1_period_low.period | @as(u11, self.ch1_period_high.period) << 8;
                    self.func_period_values[0] = ch1_2_t_cycles_per_period * (2047 - @as(u13, period));
                    self.func_volume_paces[0] = self.ch1_volume.pace;
                    self.func_volume_values[0] = self.ch1_volume.initial;
                    self.func_period_shadow = period;
                    self.func_period_pace = if(self.ch1_sweep.pace == 0) 7 else self.ch1_sweep.pace;
                    self.func_period_on = self.ch1_sweep.pace != 0 or self.ch1_sweep.step != 0;
                    self.ch1_duty_idx = 0;

                    // TODO: Enabling this immediate overflow check leads to channel 1 being muted all the time?
                    // _, const overflow = freqSweepStep(self);
                    const overflow: u1 = 0;
                    self.channels_on[0] = overflow == 0 and channel_dbg_enable[0];
                    self.control.ch1_on = overflow == 0 and channel_dbg_enable[0];
                }
                self.func_length_on[0] = self.ch1_period_high.length_on;
                if(self.channels_on[0] and self.func_length_on[0]) {
                    self.func_length_values[0] = channel_length_table[0] - self.ch1_length.length_init;
                }
            }
        },
        mem_map.ch2_length => { req.applyAllowedRW(&self.ch2_length, 0xC0, 0xFF); },
        mem_map.ch2_volume => { req.apply(&self.ch2_volume); },
        mem_map.ch2_low_period => { req.applyAllowedRW(&self.ch2_period_low, 0x00, 0xFF); },
        mem_map.ch2_high_period => { req.applyAllowedRW(&self.ch2_period_high, 0x40, 0xC7);
            if(req.isWrite()) {
                if(self.ch2_period_high.trigger) {
                    const period: u11 = self.ch2_period_low.period | @as(u11, self.ch2_period_high.period) << 8;
                    self.func_period_values[1] = ch1_2_t_cycles_per_period * (2047 - @as(u13, period));
                    self.func_volume_paces[1] = self.ch2_volume.pace;
                    self.func_volume_values[1] = self.ch2_volume.initial;
                    self.ch2_duty_idx = 0;
                    self.channels_on[1] = channel_dbg_enable[1];
                    self.control.ch2_on = channel_dbg_enable[1];
                }
                self.func_length_on[1] = self.ch2_period_high.length_on;
                if(self.channels_on[1] and self.func_length_on[1]) {
                    self.func_length_values[1] = channel_length_table[1] - self.ch2_length.length_init;
                }
            }
        },
        mem_map.ch3_length => { req.applyAllowedRW(&self.ch3_length, 0x00, 0xFF); },
        mem_map.ch3_volume => { req.applyAllowedRW(&self.ch3_volume, 0x60, 0x60); },
        mem_map.ch3_low_period => { req.applyAllowedRW(&self.ch3_period_low, 0x00, 0xFF); },
        mem_map.ch3_dac => { req.applyAllowedRW(&self.ch3_dac, 0x80, 0x80);
            if(req.isWrite()) {
                if(!self.ch3_dac.dac_on and self.channels_on[2]) {
                    self.channels_on[2] = false;
                    self.control.ch2_on = false;
                }
            }
        },
        mem_map.ch3_high_period => { req.applyAllowedRW(&self.ch3_period_high, 0x40, 0xC7);
            if(req.isWrite()) {
                if(self.ch3_period_high.trigger) {
                    const period: u11 = self.ch3_period_low.period | @as(u11, self.ch3_period_high.period) << 8;
                    self.func_period_values[2] = ch3_t_cycles_per_period * (2047 - @as(u12, period));
                    self.ch3_wave_ram_idx = 1; // Note: First sample read must be at idx 1.
                    self.channels_on[2] = channel_dbg_enable[2];
                    self.control.ch3_on = channel_dbg_enable[2];
                }
                self.func_length_on[2] = self.ch3_period_high.length_on;
                if(self.channels_on[2] and self.func_length_on[2]) {
                    self.func_length_values[2] = channel_length_table[2] - self.ch3_length.initial;
                }
            }
        },
        mem_map.wave_low...(mem_map.wave_high - 1) => {
            const wave_idx: u16 = req.address - mem_map.wave_low;
            req.apply(&self.ch3_wave_table[wave_idx]);
        },
        mem_map.ch4_length => { req.applyAllowedRW(&self.ch4_length, 0x00, 0x3F); },
        mem_map.ch4_volume => { req.apply(&self.ch4_volume); },
        mem_map.ch4_freq => { req.apply(&self.ch4_freq); },
        mem_map.ch4_control => { req.applyAllowedRW(&self.ch4_control, 0x40, 0xC0);
            if(req.isWrite()) {
                if(self.ch4_control.trigger) {
                    const divisor = lfsr_divisor_table[self.ch4_freq.divider];
                    self.func_period_values[3] = divisor << self.ch4_freq.shift;
                    self.func_volume_paces[3] = self.ch4_volume.pace;
                    self.func_volume_values[3] = self.ch4_volume.initial;
                    self.ch4_lfsr = .{ .value = 0 };
                    self.channels_on[3] = channel_dbg_enable[3];
                    self.control.ch4_on = channel_dbg_enable[3];
                }
                self.func_length_on[3] = self.ch4_control.length_on;
                if(self.channels_on[3] and self.func_length_on[3]) {
                    self.func_length_values[3] = channel_length_table[3] - self.ch4_length.initial;
                }
            }
        },
        else => {},
    }
}

pub fn cycle(self: *Self) void {
    if(!self.apu_on) {
        sample(self);
    }

    self.func_period_tick, var overflow: u1 = @subWithOverflow(self.func_period_tick, 1);
    if(overflow == 1) {
        self.func_period_pace, overflow = @subWithOverflow(self.func_period_pace, 1);
        if(self.channels_on[0] and overflow == 1 and self.func_period_on) {
            var overflow_second: u1 = 0;
            const new_period: u11, overflow = freqSweepStep(self);
            if(self.ch1_sweep.step > 0 and overflow == 0) {
                self.func_period_shadow = new_period;
                self.ch1_period_low.period = @truncate(new_period);
                self.ch1_period_high.period = @truncate(new_period >> 8);
                _, overflow_second = freqSweepStep(self);
            }

            const keep_on: bool = overflow == 0 and overflow_second == 0;
            self.channels_on[0] = keep_on;
            self.control.ch1_on = keep_on;
        }
    }

    self.func_volume_tick, overflow = @subWithOverflow(self.func_volume_tick, 1);
    if(overflow == 1) {
        inline for(0..apu_channels) |channel_idx| {
            const channel_pace: u4, const increase: bool = switch(channel_idx) {
                inline 0 => .{ self.ch1_volume.pace, self.ch1_volume.increase },
                inline 1 => .{ self.ch2_volume.pace, self.ch2_volume.increase },
                inline 2 => .{ 0, false }, // Unsupported by channel 3.
                inline 3 => .{ self.ch4_volume.pace, self.ch4_volume.increase },
                else => unreachable,
            };
            if(channel_pace != 0) {
                self.func_volume_paces[channel_idx], overflow = @subWithOverflow(self.func_volume_paces[channel_idx], 1);
                if(overflow == 1) {
                    const current: u4 = self.func_volume_values[channel_idx];
                    self.func_volume_values[channel_idx] = if(increase) current +| 1 else current -| 1;
                    self.func_volume_paces[channel_idx] = channel_pace;
                }
            }
        }
    }

    self.func_length_tick, overflow = @subWithOverflow(self.func_length_tick, 1);
    if(overflow == 1) {
        inline for(0..apu_channels) |channel_idx| {
            self.func_length_values[channel_idx], overflow = @subWithOverflow(self.func_length_values[channel_idx], 1);
            if(overflow == 1 and self.channels_on[channel_idx] and self.func_length_on[channel_idx]) {
                self.channels_on[channel_idx] = false;
                switch (channel_idx) {
                    inline 0 => self.control.ch1_on = false,
                    inline 1 => self.control.ch2_on = false,
                    inline 2 => self.control.ch3_on = false,
                    inline 3 => self.control.ch4_on = false,
                    else => unreachable,
                }
            }
        }
    }

    self.func_period_values[0], overflow = @subWithOverflow(self.func_period_values[0], 1);
    if(self.channels_on[0] and overflow == 1) {
        const ch1_bit: u4 = wave_duty_table[self.ch1_length.duty_cycle][self.ch1_duty_idx];
        self.channel_values[0] = self.func_volume_values[0] * ch1_bit;

        const period: u11 = self.ch1_period_low.period | @as(u11, self.ch1_period_high.period) << 8;
        self.func_period_values[0] = ch1_2_t_cycles_per_period * (2047 - @as(u13, period));
        self.ch1_duty_idx +%= 1;
    }

    self.func_period_values[1], overflow = @subWithOverflow(self.func_period_values[1], 1);
    if(self.channels_on[1] and overflow == 1) {
        const ch2_bit: u4 = wave_duty_table[self.ch2_length.duty_cycle][self.ch2_duty_idx];
        self.channel_values[1] = self.func_volume_values[1] * ch2_bit;

        const period: u11 = self.ch2_period_low.period | @as(u11, self.ch2_period_high.period) << 8;
        self.func_period_values[1] = ch1_2_t_cycles_per_period * (2047 - @as(u13, period));
        self.ch2_duty_idx +%= 1;
    }

    self.func_period_values[2], overflow = @subWithOverflow(self.func_period_values[2], 1);
    if(self.channels_on[2] and overflow == 1) {
        var ch3_value: u4 = ch3_dac_off_value;
        if(self.ch3_dac.dac_on) {
            const byte_idx: u4 = @intCast(self.ch3_wave_ram_idx / 2);
            const byte: u8 = self.ch3_wave_table[byte_idx];

            const nibble_idx: u3 = @intCast(self.ch3_wave_ram_idx % 2);
            const shift: u3 = nibble_idx * 4;
            const mask: u8 = @as(u8, 0xF0) >> shift;
            ch3_value = @intCast((byte & mask) >> (4 - shift));
        }
        ch3_value = if(self.ch3_volume.shift == 0b00) 0 else ch3_value >> (self.ch3_volume.shift - 1);
        self.channel_values[2] = ch3_value;

        const period: u11 = self.ch3_period_low.period | @as(u11, self.ch3_period_high.period) << 8;
        self.func_period_values[2] = ch3_t_cycles_per_period * (2047 - @as(u12, period));
        self.ch3_wave_ram_idx +%= 1;
    }

    self.func_period_values[3], overflow = @subWithOverflow(self.func_period_values[3], 1);
    if(self.channels_on[3] and overflow == 1) {
        const xor: u1 = ~(self.ch4_lfsr.bits.b0 ^ self.ch4_lfsr.bits.b1);
        self.ch4_lfsr.bits.b15 = xor;
        self.ch4_lfsr.bits.b7 = if(self.ch4_freq.is_short) xor else self.ch4_lfsr.bits.b7;
        self.ch4_lfsr.value >>= 1;

        const ch4_bit: u1 = self.ch4_lfsr.bits.b0;
        self.channel_values[3] = self.func_volume_values[3] * ch4_bit;

        const divisor = lfsr_divisor_table[self.ch4_freq.divider];
        self.func_period_values[3] = divisor << self.ch4_freq.shift;
    }

    sample(self);
}

fn sample(self: *Self) void {
    self.sample_tick, const overflow = @subWithOverflow(self.sample_tick, 1);
    if(overflow == 0) {
        return;
    }

    self.sample_tick = def.t_cycles_per_sample - 1;
    const result: def.Sample = mixChannels(self.channel_values, self.panning, self.volume);
    self.samples.writeItemDiscardWhenFull(result);
}

fn mixChannels(channels: [apu_channels]u4, panning: Panning, volume: Volume) def.Sample {
    const panning_left: [apu_channels]bool = .{ panning.ch1_left, panning.ch2_left, panning.ch3_left, panning.ch4_left };
    const panning_right: [apu_channels]bool = .{ panning.ch1_right, panning.ch2_right, panning.ch3_right, panning.ch4_right };
    // TODO: This leads to each channel having 1/4 of their expected volume.
    const scaling: f32 = 1.0 / @as(f32, @floatFromInt(apu_channels));

    var mix_left: f32 = 0.0;
    var mix_right: f32 = 0.0;
    for(channels, panning_left, panning_right) |self, left, right| {
        const channel: f32 = @floatFromInt(self);
        const normalized: f32 = channel / 15.0;
        const value: f32 = normalized * 2.0 - 1.0;
        mix_left += if(left) value * scaling else 0.0;
        mix_right += if(right) value * scaling else 0.0;
    }

    const volume_left: f32 = @floatFromInt(volume.left_volume);
    const volume_left_normal: f32 = (volume_left + 1.0) / 8.0;
    const self_left: f32 = mix_left * volume_left_normal;

    const volume_right: f32 = @floatFromInt(volume.right_volume);
    const volume_right_normal: f32 = (volume_right + 1.0) / 8.0;
    const self_right: f32 = mix_right * volume_right_normal;

    return .{ .left = self_left, .right = self_right };
}

fn freqSweepStep(self: *Self) struct{ u11, u1 } {
    const delta: u11 = self.func_period_shadow >> self.ch1_sweep.step;
    if(self.ch1_sweep.decrease) {
        return @subWithOverflow(self.func_period_shadow, delta);
    } else {
        return @addWithOverflow(self.func_period_shadow, delta);
    }
}
