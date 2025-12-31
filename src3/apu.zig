const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");
// TODO: Try to get rid of mmu dependency. It is currently required to read out IE and IF.
const MMU = @import("mmu.zig");

const apu_channels = 4;
// TODO: Pandocs talks about a DIV-APU that triggers those functions. When DIV is reset these might trigger again, so this is inprecise.
pub const t_cycles_per_vol_step = 65_536;
pub const t_cycles_per_freq_step = 32_768;
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

// general
pub const Control = packed struct(u8) {
    ch1_on: bool, ch2_on: bool, ch3_on: bool, ch4_on: bool,
    _: u3 = 0, enable_apu: bool,
    // TODO: When we remove the mmu like this all subsystems control their own registers and react to read/write request on the bus.
    // Then we don't need "fromMem()" and "toMem()".
    pub fn fromMem(mmu: *MMU.State) Control {
        return @bitCast(mmu.memory[mem_map.sound_control]);
    } 
    pub fn toMem(control: Control, mmu: *MMU.State) void {
        mmu.memory[mem_map.sound_control] = @bitCast(control);
    }
};
pub const Volume = packed struct(u8) {
    right_volume: u3, vin_right: bool,
    left_volume: u3,  vin_left: bool,
    pub fn fromMem(mmu: *MMU.State) Volume {
        return @bitCast(mmu.memory[mem_map.master_volume]);
    } 
};
pub const Panning = packed struct(u8) {
    ch1_right: bool, ch2_right: bool, ch3_right: bool, ch4_right: bool,
    ch1_left: bool,  ch2_left: bool,  ch3_left: bool,  ch4_left: bool,
    pub fn fromMem(mmu: *MMU.State) Panning {
        return @bitCast(mmu.memory[mem_map.sound_panning]);
    } 
};

// channel 1
pub const Channel1Sweep = packed struct(u8) {
    freq_step: u3, freq_decrease: bool, freq_pace: u3, _: u1 = 0,
    pub fn fromMem(mmu: *MMU.State) Channel1Sweep {
        return @bitCast(mmu.memory[mem_map.ch1_sweep]);
    } 
};
pub const Channel1Length = packed struct(u8) {
    length_init: u6, duty_cycle: u2,
    pub fn fromMem(mmu: *MMU.State) Channel1Length {
        return @bitCast(mmu.memory[mem_map.ch1_length]);
    } 
};
pub const Channel1Volume = packed struct(u8) {
    vol_pace: u3, vol_increase: bool, vol_initial: u4,
    pub fn fromMem(mmu: *MMU.State) Channel1Volume {
        return @bitCast(mmu.memory[mem_map.ch1_volume]);
    } 
};
pub const Channel1PeriodLow = packed struct(u8) {
    period: u8,
    pub fn fromMem(mmu: *MMU.State) Channel1PeriodLow {
        return @bitCast(mmu.memory[mem_map.ch1_low_period]);
    } 
    pub fn toMem(period_low: Channel1PeriodLow, mmu: *MMU.State) void {
        mmu.memory[mem_map.ch1_low_period] = @bitCast(period_low);
    }
};
pub const Channel1PeriodHigh = packed struct(u8) {
    period: u3, _: u3 = 0, length_enable: bool, trigger: bool,  
    pub fn fromMem(mmu: *MMU.State) Channel1PeriodHigh {
        return @bitCast(mmu.memory[mem_map.ch1_high_period]);
    } 
    pub fn toMem(period_high: Channel1PeriodHigh, mmu: *MMU.State) void {
        mmu.memory[mem_map.ch1_high_period] = @bitCast(period_high);
    }
};

// channel 2
// TODO: Without mmu, I could use the same definition for all channel 1 and channel 2 structs!
pub const Channel2Length = packed struct(u8) {
    length_init: u6, duty_cycle: u2,
    pub fn fromMem(mmu: *MMU.State) Channel2Length {
        return @bitCast(mmu.memory[mem_map.ch2_length]);
    } 
};
pub const Channel2Volume = packed struct(u8) {
    vol_pace: u3, vol_increase: bool, vol_initial: u4,
    pub fn fromMem(mmu: *MMU.State) Channel2Volume {
        return @bitCast(mmu.memory[mem_map.ch2_volume]);
    } 
};
pub const Channel2PeriodLow = packed struct(u8) {
    period: u8,
    pub fn fromMem(mmu: *MMU.State) Channel2PeriodLow {
        return @bitCast(mmu.memory[mem_map.ch2_low_period]);
    } 
};
pub const Channel2PeriodHigh = packed struct(u8) {
    period: u3, _: u3 = 0, length_enable: bool, trigger: bool,  
    pub fn fromMem(mmu: *MMU.State) Channel2PeriodHigh {
        return @bitCast(mmu.memory[mem_map.ch2_high_period]);
    } 
};

// channel 3
pub const Channel3Dac = packed struct(u8) {
    _: u7 = 0, dac_on: bool,
    pub fn fromMem(mmu: *MMU.State) Channel3Dac {
        return @bitCast(mmu.memory[mem_map.ch3_dac]);
    } 
};
pub const Channel3Length = packed struct(u8) {
    length_init: u8,
    pub fn fromMem(mmu: *MMU.State) Channel3Length {
        return @bitCast(mmu.memory[mem_map.ch3_length]);
    } 
};
pub const Channel3Volume = packed struct(u8) {
    _: u5 = 0, vol_shift: u2, __: u1 = 0, 
    pub fn fromMem(mmu: *MMU.State) Channel3Volume {
        return @bitCast(mmu.memory[mem_map.ch3_volume]);
    } 
};
pub const Channel3PeriodLow = packed struct(u8) {
    period: u8,
    pub fn fromMem(mmu: *MMU.State) Channel3PeriodLow {
        return @bitCast(mmu.memory[mem_map.ch3_low_period]);
    } 
};
pub const Channel3PeriodHigh = packed struct(u8) {
    period: u3, _: u3 = 0, length_enable: bool, trigger: bool,
    pub fn fromMem(mmu: *MMU.State) Channel3PeriodHigh {
        return @bitCast(mmu.memory[mem_map.ch3_high_period]);
    } 
};

// channel 4
pub const Channel4Length = packed struct(u8) {
    length_init: u6, _: u2 = 0,
    pub fn fromMem(mmu: *MMU.State) Channel4Length {
        return @bitCast(mmu.memory[mem_map.ch4_length]);
    } 
};
pub const Channel4Volume = packed struct(u8) {
    vol_pace: u3, vol_increase: bool, vol_initial: u4,
    pub fn fromMem(mmu: *MMU.State) Channel4Volume {
        return @bitCast(mmu.memory[mem_map.ch4_volume]);
    } 
};
pub const Channel4Freq = packed struct(u8) {
    lfsr_divider: u3, lfsr_is_short: bool, lfsr_shift: u4,
    pub fn fromMem(mmu: *MMU.State) Channel4Freq {
        return @bitCast(mmu.memory[mem_map.ch4_freq]);
    } 
};
pub const Channel4Control = packed struct(u8) {
    __: u6 = 0, length_enable: bool, trigger: bool, 
    pub fn fromMem(mmu: *MMU.State) Channel4Control {
        return @bitCast(mmu.memory[mem_map.ch4_control]);
    } 
};

const LFSR = packed union {
    value: u16,
    bits: packed struct {
        b0: u1, b1: u1, _: u5 = 0, b7: u1, __: u7 = 0, b15: u1,
    },
};

pub const State = struct {
    apu_is_on: bool = false,
    channels: [apu_channels]u4 = [_]u4{0} ** apu_channels,
    sample_counter: u16 = def.t_cycles_per_sample - 1, 

    // functions
    volume_sweep_counter: u16 = t_cycles_per_vol_step - 1,
    volume_sweep_values: [apu_channels]u4 = .{0} ** apu_channels,
    volume_sweep_pace_counter: [apu_channels]u4 = .{0} ** apu_channels,
    length_counter: u14 = t_cycles_per_length_step - 1,
    length_values: [apu_channels]u8 = .{0} ** apu_channels, // [2] is unused. Not supported by ch3.
    freq_sweep_counter: u15 = t_cycles_per_freq_step - 1,
    freq_sweep_period: u11 = 0,
    freq_sweep_pace_counter: u4 = 0,
    freq_sweep_enabled: bool = false,

    // ch1
    ch1_is_on: bool = false,
    // TODO: Should I combine period_counter for all channels?
    ch1_period_counter: u13 = 0,
    // TODO: Should I combine duty_idx and wave_ram_idx into a table? Does Channel 4 do the same? 
    // TODO: Good question to ask if I use tables or values for each channel (also see special functions).
    ch1_duty_idx: u3 = 0,
    ch1_length_on: bool = false,

    // ch2
    ch2_is_on: bool = false,
    ch2_period_counter: u13 = 0,
    ch2_duty_idx: u3 = 0,
    ch2_length_on: bool = false,

    // ch3
    ch3_is_on: bool = false,
    ch3_period_counter: u12 = 0,
    ch3_wave_ram_idx: u5 = 0,
    ch3_length_on: bool = false,

    // ch4
    ch4_is_on: bool = false,
    // TODO: This does not seem to be hardware accurate. Sameboy uses "a counter (8bit) for a counter (16bit)". Which matches the lfsr_shift being a u4.
    ch4_period_counter: u24 = 0,
    ch4_lfsr: LFSR = .{ .value = 0 },
    ch4_length_on: bool = false,
};

pub fn init(state: *State) void {
    state.* = .{};
}

pub fn request(state: *State, mmu: *MMU.State, bus: *def.Bus) void {
    var control: Control = .fromMem(mmu);
    // TODO: writes will be applied to mmu by the mmu itself which is getting called after this. This is bad design, but the mmu is getting removed soon anyway.
    if(bus.write) |address| {
        switch(address) {
            mem_map.sound_control => {
                // TODO: lower nibble is read only (channel status bits).
                state.apu_is_on = control.enable_apu;
            },
            mem_map.ch1_high_period => {
                const sweep: Channel1Sweep = .fromMem(mmu);
                const volume: Channel1Volume = .fromMem(mmu);
                const length: Channel1Length = .fromMem(mmu);
                const period_low: Channel1PeriodLow = .fromMem(mmu);
                const period_high: Channel1PeriodHigh = @bitCast(bus.data.*);
                if(period_high.trigger) {
                    const period: u11 = period_low.period | @as(u11, period_high.period) << 8;
                    state.ch1_period_counter = ch1_2_t_cycles_per_period * (2047 - @as(u13, period));
                    state.volume_sweep_pace_counter[0] = volume.vol_pace;
                    state.volume_sweep_values[0] = volume.vol_initial;
                    state.freq_sweep_period = period;
                    state.freq_sweep_pace_counter = if(sweep.freq_pace == 0) 7 else sweep.freq_pace;
                    state.freq_sweep_enabled = sweep.freq_pace != 0 or sweep.freq_step != 0;
                    state.ch1_duty_idx = 0;

                    // TODO: Enabling this immediate overflow check leads to channel 1 being muted all the time?
                    // _, const overflow = freqSweepStep(state, mmu);
                    const overflow: u1 = 0;
                    state.ch1_is_on = overflow == 0 and channel_dbg_enable[0];
                    control.ch1_on = overflow == 0 and channel_dbg_enable[0];
                }
                state.ch1_length_on = period_high.length_enable;
                if(state.ch1_is_on and state.ch1_length_on) {
                    state.length_values[0] = channel_length_table[0] - length.length_init;
                }
            },
            mem_map.ch2_high_period => {
                const volume: Channel1Volume = .fromMem(mmu);
                const length: Channel2Length = .fromMem(mmu);
                const period_low: Channel2PeriodLow = .fromMem(mmu);
                const period_high: Channel2PeriodHigh = @bitCast(bus.data.*);
                if(period_high.trigger) {
                    const period: u11 = period_low.period | @as(u11, period_high.period) << 8;
                    state.ch2_period_counter = ch1_2_t_cycles_per_period * (2047 - @as(u13, period));
                    state.volume_sweep_pace_counter[1] = volume.vol_pace;
                    state.volume_sweep_values[1] = volume.vol_initial;
                    state.ch2_duty_idx = 0;
                    state.ch2_is_on = channel_dbg_enable[1];
                    control.ch2_on = channel_dbg_enable[1];
                }
                state.ch2_length_on = period_high.length_enable;
                if(state.ch2_is_on and state.ch2_length_on) {
                    state.length_values[1] = channel_length_table[1] - length.length_init;
                }
            },
            mem_map.ch3_dac => {
                const dac: Channel3Dac = @bitCast(bus.data.*);
                if(!dac.dac_on and state.ch3_is_on) {
                    state.ch3_is_on = false;
                    control.ch2_on = false;
                }
            },
            mem_map.ch3_high_period => {
                const length: Channel3Length = .fromMem(mmu);
                const period_low: Channel3PeriodLow = .fromMem(mmu);
                const period_high: Channel3PeriodHigh = @bitCast(bus.data.*);
                if(period_high.trigger) {
                    const period: u11 = period_low.period | @as(u11, period_high.period) << 8;
                    state.ch3_period_counter = ch3_t_cycles_per_period * (2047 - @as(u12, period));
                    state.ch3_wave_ram_idx = 1; // Note: First sample read must be at idx 1.
                    state.ch3_is_on = channel_dbg_enable[2];
                    control.ch3_on = channel_dbg_enable[2];
                }
                state.ch3_length_on = period_high.length_enable;
                if(state.ch3_is_on and state.ch3_length_on) {
                    state.length_values[2] = channel_length_table[2] - length.length_init;
                }
            },
            mem_map.ch4_control => {
                const freq: Channel4Freq = .fromMem(mmu);
                const volume: Channel4Volume = .fromMem(mmu);
                const length: Channel4Length = .fromMem(mmu);
                const lfsr_control: Channel4Control = @bitCast(bus.data.*);
                if(lfsr_control.trigger) {
                    const divisor = lfsr_divisor_table[freq.lfsr_divider];
                    state.ch4_period_counter = divisor << freq.lfsr_shift;
                    state.volume_sweep_pace_counter[3] = volume.vol_pace;
                    state.volume_sweep_values[3] = volume.vol_initial;
                    state.ch4_lfsr = .{ .value = 0 };
                    state.ch4_is_on = channel_dbg_enable[3];
                    control.ch4_on = channel_dbg_enable[3];
                }
                state.ch4_length_on = lfsr_control.length_enable;
                if(state.ch4_is_on and state.ch4_length_on) {
                    state.length_values[3] = channel_length_table[3] - length.length_init;
                }
            },
            else => {},
        }
    }
    control.toMem(mmu);
}

// TODO: Remove dependency to the memory array.
pub fn cycle(state: *State, mmu: *MMU.State) ?def.Sample {
    if(!state.apu_is_on) {
        return sample(state, mmu);
    }

    var control: Control = .fromMem(mmu);
    state.freq_sweep_counter, var overflow: u1 = @subWithOverflow(state.freq_sweep_counter, 1);
    if(overflow == 1) {
        state.freq_sweep_pace_counter, overflow = @subWithOverflow(state.freq_sweep_pace_counter, 1);
        if(state.ch1_is_on and overflow == 1 and state.freq_sweep_enabled) {
            const sweep: Channel1Sweep = .fromMem(mmu);
            var period_low: Channel1PeriodLow = .fromMem(mmu);
            var period_high: Channel1PeriodHigh = .fromMem(mmu);

            var overflow_second: u1 = 0;
            const new_period: u11, overflow = freqSweepStep(state, mmu);
            if(sweep.freq_step > 0 and overflow == 0) {
                state.freq_sweep_period = new_period;
                period_low.period = @truncate(new_period);
                period_high.period = @truncate(new_period >> 8);
                period_low.toMem(mmu);
                period_high.toMem(mmu);

                _, overflow_second = freqSweepStep(state, mmu);
            }

            const keep_on: bool = overflow == 0 and overflow_second == 0;
            state.ch1_is_on = keep_on;
            control.ch1_on = keep_on;
        }
    }

    state.volume_sweep_counter, overflow = @subWithOverflow(state.volume_sweep_counter, 1);
    if(overflow == 1) {
        inline for(0..4) |channel_idx| {
            const channel_pace: u4, const increase: bool = switch(channel_idx) {
                inline 0 => .{ Channel1Volume.fromMem(mmu).vol_pace, false },
                inline 1 => .{ Channel2Volume.fromMem(mmu).vol_pace, false },
                inline 2 => .{ 0, false }, // Unsupported by channel 3.
                inline 3 => .{ Channel4Volume.fromMem(mmu).vol_pace, false},
                else => unreachable,
            };
            if(channel_pace != 0) {
                state.volume_sweep_pace_counter[channel_idx], overflow = @subWithOverflow(state.volume_sweep_pace_counter[channel_idx], 1);
                if(overflow == 1) {
                    const current: u4 = state.volume_sweep_values[channel_idx];
                    state.volume_sweep_values[channel_idx] = if(increase) current +| 1 else current -| 1;
                    state.volume_sweep_pace_counter[channel_idx] = channel_pace;
                }
            }
        }
    }

    // TODO: We are duplicating the mmu control with the chx_is_on values (another case for removing mmu!).
    state.length_counter, overflow = @subWithOverflow(state.length_counter, 1);
    if(overflow == 1) {
        inline for(0..4) |channel_idx| {
            // TODO: Where should we use a table of channel values and where a value for each channel?
            state.length_values[channel_idx], overflow = @subWithOverflow(state.length_values[channel_idx], 1);
            switch (channel_idx) {
                inline 0 => if(overflow == 1 and state.ch1_is_on and state.ch1_length_on) { state.ch1_is_on = false; control.ch1_on = false; },
                inline 1 => if(overflow == 1 and state.ch2_is_on and state.ch2_length_on) { state.ch2_is_on = false; control.ch2_on = false; },
                inline 2 => if(overflow == 1 and state.ch3_is_on and state.ch3_length_on) { state.ch3_is_on = false; control.ch3_on = false; },
                inline 3 => if(overflow == 1 and state.ch4_is_on and state.ch4_length_on) { state.ch4_is_on = false; control.ch4_on = false; },
                else => unreachable,
            }
        }
    }
    control.toMem(mmu);

    state.ch1_period_counter, overflow = @subWithOverflow(state.ch1_period_counter, 1);
    if(state.ch1_is_on and overflow == 1) {
        const length: Channel1Length = .fromMem(mmu);
        const period_low: Channel1PeriodLow = .fromMem(mmu);
        const period_high: Channel1PeriodHigh = .fromMem(mmu);

        const ch1_bit: u4 = wave_duty_table[length.duty_cycle][state.ch1_duty_idx];
        state.channels[0] = state.volume_sweep_values[0] * ch1_bit;

        const period: u11 = period_low.period | @as(u11, period_high.period) << 8;
        state.ch1_period_counter = ch1_2_t_cycles_per_period * (2047 - @as(u13, period));
        state.ch1_duty_idx +%= 1;
    }

    state.ch2_period_counter, overflow = @subWithOverflow(state.ch2_period_counter, 1);
    if(state.ch2_is_on and overflow == 1) {
        const length: Channel2Length = .fromMem(mmu);
        const period_low: Channel2PeriodLow = .fromMem(mmu);
        const period_high: Channel2PeriodHigh = .fromMem(mmu);

        const ch2_bit: u4 = wave_duty_table[length.duty_cycle][state.ch2_duty_idx];
        state.channels[1] = state.volume_sweep_values[1] * ch2_bit;

        const period: u11 = period_low.period | @as(u11, period_high.period) << 8;
        state.ch2_period_counter = ch1_2_t_cycles_per_period * (2047 - @as(u13, period));
        state.ch2_duty_idx +%= 1;
    }

    state.ch3_period_counter, overflow = @subWithOverflow(state.ch3_period_counter, 1);
    if(state.ch3_is_on and overflow == 1) {
        const dac: Channel3Dac = .fromMem(mmu);
        const period_low: Channel3PeriodLow = .fromMem(mmu);
        const period_high: Channel3PeriodHigh = .fromMem(mmu);
        const volume: Channel3Volume = .fromMem(mmu);

        var ch3_value: u4 = ch3_dac_off_value;
        if(dac.dac_on) {
            const byte_idx: u4 = @intCast(state.ch3_wave_ram_idx / 2);
            const mem_idx: u16 = mem_map.wave_low + @as(u16, byte_idx);
            const byte: u8 = mmu.memory[mem_idx];

            const nibble_idx: u3 = @intCast(state.ch3_wave_ram_idx % 2);
            const shift: u3 = nibble_idx * 4;
            const mask: u8 = @as(u8, 0xF0) >> shift;
            ch3_value = @intCast((byte & mask) >> (4 - shift));
        }
        ch3_value = if(volume.vol_shift == 0b00) 0 else ch3_value >> (volume.vol_shift - 1);
        state.channels[2] = ch3_value;

        const period: u11 = period_low.period | @as(u11, period_high.period) << 8;
        state.ch3_period_counter = ch3_t_cycles_per_period * (2047 - @as(u12, period));
        state.ch3_wave_ram_idx +%= 1;
    }

    state.ch4_period_counter, overflow = @subWithOverflow(state.ch4_period_counter, 1);
    if(state.ch4_is_on and overflow == 1) {
        const freq: Channel4Freq = .fromMem(mmu);

        const xor: u1 = ~(state.ch4_lfsr.bits.b0 ^ state.ch4_lfsr.bits.b1);
        state.ch4_lfsr.bits.b15 = xor;
        state.ch4_lfsr.bits.b7 = if(freq.lfsr_is_short) xor else state.ch4_lfsr.bits.b7;
        state.ch4_lfsr.value >>= 1;

        const ch4_bit: u1 = state.ch4_lfsr.bits.b0;
        state.channels[3] = state.volume_sweep_values[3] * ch4_bit;

        const divisor = lfsr_divisor_table[freq.lfsr_divider];
        state.ch4_period_counter = divisor << freq.lfsr_shift;
    }

    return sample(state, mmu);
}

fn sample(state: *State, mmu: *MMU.State) ?def.Sample {
    state.sample_counter, const overflow = @subWithOverflow(state.sample_counter, 1);
    if(overflow == 0) {
        return null;
    }

    state.sample_counter = def.t_cycles_per_sample - 1;
    const panning = Panning.fromMem(mmu);
    const volume = Volume.fromMem(mmu);
    return mixChannels(state.channels, panning, volume);
}

fn mixChannels(channels: [apu_channels]u4, panning: Panning, volume: Volume) def.Sample {
    const panning_left: [apu_channels]bool = .{ panning.ch1_left, panning.ch2_left, panning.ch3_left, panning.ch4_left };
    const panning_right: [apu_channels]bool = .{ panning.ch1_right, panning.ch2_right, panning.ch3_right, panning.ch4_right };
    // TODO: This leads to each channel having 1/4 of their expected volume.
    const scaling: f32 = 1.0 / @as(f32, @floatFromInt(apu_channels));

    var mix_left: f32 = 0.0;
    var mix_right: f32 = 0.0;
    for(channels, panning_left, panning_right) |state, left, right| {
        const channel: f32 = @floatFromInt(state);
        const normalized: f32 = channel / 15.0;
        const value: f32 = normalized * 2.0 - 1.0;
        mix_left += if(left) value * scaling else 0.0;
        mix_right += if(right) value * scaling else 0.0;
    }

    const volume_left: f32 = @floatFromInt(volume.left_volume);
    const volume_left_normal: f32 = (volume_left + 1.0) / 8.0;
    const state_left: f32 = mix_left * volume_left_normal;

    const volume_right: f32 = @floatFromInt(volume.right_volume);
    const volume_right_normal: f32 = (volume_right + 1.0) / 8.0;
    const state_right: f32 = mix_right * volume_right_normal;

    return .{ .left = state_left, .right = state_right };
}

fn freqSweepStep(state: *State, mmu: *MMU.State) struct{ u11, u1 } {
    const sweep: Channel1Sweep = .fromMem(mmu);
    const delta: u11 = state.freq_sweep_period >> sweep.freq_step;
    if(sweep.freq_decrease) {
        return @subWithOverflow(state.freq_sweep_period, delta);
    } else {
        return @addWithOverflow(state.freq_sweep_period, delta);
    }
}
