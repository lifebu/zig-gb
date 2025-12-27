const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");
// TODO: Try to get rid of mmu dependency. It is currently required to read out IE and IF.
const MMU = @import("mmu.zig");

const apu_channels = 4;

const Control = packed struct(u8) {
    ch1_on: bool, ch2_on: bool, ch3_on: bool, ch4_on: bool,
    _: u3, enable_apu: bool,

    // TODO: When we remove the mmu like this all subsystems control their own registers and react to read/write request on the bus.
    // Then we don't need "fromMem()" and "toMem()".
    pub fn fromMem(mmu: *MMU.State) Control {
        return @bitCast(mmu.memory[mem_map.sound_control]);
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

pub const State = struct {
    // TODO: Remove this: no buffering on gb side.
    gb_sample_buffer: [def.num_gb_samples]f32 = [1]f32{ 0.0 } ** def.num_gb_samples,

    channels: [apu_channels]u4 = [_]u4{0} ** apu_channels,
    sample_counter: u16 = 0, 
};

pub fn init(state: *State) void {
    state.sample_counter = def.t_cycles_per_sample;
}

pub fn request(_: *State, _: *def.Bus) void {

}

// TODO: Remove dependency to the memory array.
pub fn cycle(state: *State, mmu: *MMU.State) ?def.Sample {
    state.sample_counter, const overflow = @subWithOverflow(state.sample_counter, 1);
    if(overflow == 1) {
        state.sample_counter = def.t_cycles_per_sample;
        const panning = Panning.fromMem(mmu);
        const volume = Volume.fromMem(mmu);
        return mixChannels(state.channels, panning, volume);
    }

    return null;
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
