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
pub const ch3_t_cycles_per_period = 2;
// TODO: Not sure if this would be correct. This value would generate a permanent -1.0 in the audio output.
pub const ch3_dac_off_value = 0;

const channel_length_table: [apu_channels]u8 = .{ 63, 63, 255, 63 };

// general
pub const Control = packed struct(u8) {
    ch1_on: bool, ch2_on: bool, ch3_on: bool, ch4_on: bool,
    _: u3, enable_apu: bool,
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

// TODO: Does splitting these channel registers make memory requests easier?
pub const Channel1 = packed struct(u40) {
    freq_step: u3, freq_decrease: bool, freq_pace: u3, _: u1 = 0,
    length_init: u6, duty_cycle: u2,
    vol_step: u3, vol_increase: bool, vol_initial: u4,
    period: u11, 
    __: u3 = 0, length_enable: bool, trigger: bool,  
    pub fn fromMem(mmu: *MMU.State) Channel1 {
        return std.mem.bytesToValue(Channel1, mmu.memory[mem_map.ch1_low..mem_map.ch1_high]);
    } 
};
pub const Channel2 = packed struct(u32) {
    length_init: u6, duty_cycle: u2,
    vol_step: u3, vol_increase: bool, vol_initial: u4,
    period: u11, 
    _: u3 = 0, length_enable: bool, trigger: bool,  
    pub fn fromMem(mmu: *MMU.State) Channel2 {
        return std.mem.bytesToValue(Channel2, mmu.memory[mem_map.ch2_low..mem_map.ch2_high]);
    } 
};

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
pub const Channel4 = packed struct(u32) {
    length_init: u6, _: u2 = 0,
    vol_step: u3, vol_increase: bool, vol_initial: u4,
    lfsr_divider: u3, lfsr_width: u1, lfsr_shift: u4,
    __: u6 = 0, length_enable: bool, trigger: bool, 
    pub fn fromMem(mmu: *MMU.State) Channel4 {
        return std.mem.bytesToValue(Channel4, mmu.memory[mem_map.ch4_low..mem_map.ch4_high]);
    } 
};

pub const State = struct {
    channels: [apu_channels]u4 = [_]u4{0} ** apu_channels,
    sample_counter: u16 = def.t_cycles_per_sample - 1, 

    // functions
    volume_sweep_counter: u16 = t_cycles_per_vol_step - 1,
    freq_sweep_counter: u15 = t_cycles_per_freq_step - 1,
    length_counter: u14 = t_cycles_per_length_step - 1,
    length_values: [apu_channels]u8 = .{0} ** apu_channels,

    // ch1
    ch1_is_on: bool = false,
    ch1_length_on: bool = false,

    // ch2
    ch2_is_on: bool = false,
    ch2_length_on: bool = false,

    // ch3
    ch3_is_on: bool = false,
    ch3_period_counter: u12 = 0,
    ch3_wave_ram_idx: u5 = 0,
    ch3_length_on: bool = false,

    // ch4
    ch4_is_on: bool = false,
    ch4_length_on: bool = false,
};

pub fn init(state: *State) void {
    state.* = .{};
}

pub fn request(state: *State, mmu: *MMU.State, bus: *def.Bus) void {
    if(bus.write) |address| {
        switch(address) {
            mem_map.ch3_dac => {
                mmu.memory[address] = bus.data.*;
                bus.write = null;
            },
            mem_map.ch3_length => {
                mmu.memory[address] = bus.data.*;
                bus.write = null;
            },
            mem_map.ch3_volume => {
                mmu.memory[address] = bus.data.*;
                bus.write = null;
            },
            mem_map.ch3_low_period => {
                mmu.memory[address] = bus.data.*;
                bus.write = null;
            },
            mem_map.ch3_high_period => {
                mmu.memory[address] = bus.data.*;
                bus.write = null;

                const length: Channel3Length = .fromMem(mmu);
                const period_low: Channel3PeriodLow = .fromMem(mmu);
                const period_high: Channel3PeriodHigh = .fromMem(mmu);
                if(period_high.trigger) {
                    const period: u11 = period_low.period | @as(u11, period_high.period) << 8;
                    state.ch3_period_counter = ch3_t_cycles_per_period * (2047 - @as(u12, period));
                    state.ch3_wave_ram_idx = 1; // Note: First sample read must be at idx 1.
                    state.ch3_is_on = true;

                    var control: Control = .fromMem(mmu);
                    control.ch3_on = true;
                    control.toMem(mmu);
                }
                state.ch3_length_on = period_high.length_enable;
                if(state.ch3_is_on and state.ch3_length_on) {
                    state.length_values[2] = channel_length_table[2] - length.length_init;
                }

            },
            else => {},
        }
    }
}

// TODO: Remove dependency to the memory array.
pub fn cycle(state: *State, mmu: *MMU.State) ?def.Sample {
    state.freq_sweep_counter, var overflow = @subWithOverflow(state.freq_sweep_counter, 1);
    if(overflow == 1) {
        // TODO: Implement frequency sweep for ch1.
    }

    state.volume_sweep_counter, overflow = @subWithOverflow(state.volume_sweep_counter, 1);
    if(overflow == 1) {
        // TODO: Implement volume sweep for ch1, ch2, ch4.
    }

    // TODO: We are duplicating the mmu control with the chx_is_on values (another case for removing mmu!).
    var control: Control = .fromMem(mmu);
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
