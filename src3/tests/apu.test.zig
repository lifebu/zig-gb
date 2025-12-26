const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const MMU = @import("../mmu.zig");
const def = @import("../defines.zig");
const APU = @import("../apu.zig");
const Platform = @import("../platform.zig");
const mem_map = @import("../mem_map.zig");

// TODO: Need to update vscode running tests to make this debugable.
const sokol = @import("sokol");


pub fn runApuSamplerTests() !void {
    // 1st: Test that the sample rate was hit.
    // 2nd: Test that the Master Volume for l/r is applied.
    // 3rd: Test that the Stereo vs mono samples can be generated.
    // 4th: Test that the panning works
    // 5th: Test conversion from [0, 15] to [-1, 1] range for the platform output.

    var mmu: MMU.State = .{}; 

    // Initialize with test memory.
    for(0x0300..0x039F, 1..) |addr, i| {
        mmu.memory[@intCast(addr)] = @truncate(i);
    }
    for(mem_map.oam_low..mem_map.oam_high + 1) |addr| {
        mmu.memory[@intCast(addr)] = 0;
    }

    try std.testing.expectEqual(true, true);
}




const Control = packed struct(u8) {
    ch1_on: bool, ch2_on: bool, ch3_on: bool, ch4_on: bool,
    _: u3, enable_apu: bool,
};
const Volume = packed struct(u8) {
    right_volume: u3, vin_right: bool,
    left_volume: u3,  vin_left: bool,
};
const Panning = packed struct(u8) {
    ch1_right: bool, ch2_right: bool, ch3_right: bool, ch4_right: bool,
    ch1_left: bool,  ch2_left: bool,  ch3_left: bool,  ch4_left: bool,
};

fn mixChannels(ch1: u5, ch2: u5, ch3: u5, ch4: u5, panning: Panning, volume: Volume) struct{ u4, u4 } {
    // TODO: Try to do the volume without float conversion.
    const ch1_left: u6 = ch1 * @intFromBool(panning.ch1_left);
    const ch2_left: u6 = ch2 * @intFromBool(panning.ch2_left);
    const ch3_left: u6 = ch3 * @intFromBool(panning.ch3_left);
    const ch4_left: u6 = ch4 * @intFromBool(panning.ch4_left);
    const mix_left: u6 = (ch1_left + ch2_left + ch3_left + ch4_left) / 4;
    const volume_left: f32 = @as(f32, @floatFromInt(volume.left_volume)) / 7.0;
    const mix_left_volume: f32 = @as(f32, @floatFromInt(mix_left)) * volume_left;
    const state_left: u4 = @intFromFloat(@trunc(mix_left_volume));

    const ch1_right: u6 = ch1 * @intFromBool(panning.ch1_right);
    const ch2_right: u6 = ch2 * @intFromBool(panning.ch2_right);
    const ch3_right: u6 = ch3 * @intFromBool(panning.ch3_right);
    const ch4_right: u6 = ch4 * @intFromBool(panning.ch4_right);
    const mix_right: u6 = (ch1_right + ch2_right + ch3_right + ch4_right) / 4;
    // TODO: This is wrong, a volume of 0 is very quiet, but not 0.
    const volume_right: f32 = @as(f32, @floatFromInt(volume.right_volume)) / 7.0;
    const mix_right_volume: f32 = @as(f32, @floatFromInt(mix_right)) * volume_right;
    const state_right: u4 = @intFromFloat(@trunc(mix_right_volume));

    return .{ state_left, state_right };
}
fn sampleState(state: u5, volume: f32) f32 {
    const state_flt: f32 = @floatFromInt(state);
    const normalized: f32 = state_flt / 16.0;
    const ranged: f32 = (normalized * 2.0) - 1.0;
    const result: f32 = ranged * volume;
    return result;
}


const use_flt: bool = true;
const platform_volume: f32 = 0.2;
// TODO: with stereo, the audio sounds half as fast?
const is_stereo: bool = false;
const sample_rate = 44_100;
const t_cycles_per_sample = def.system_freq / sample_rate;
export fn init() void {
    sokol.audio.setup(.{
        .logger = .{ .func = sokol.log.func },
        .num_channels = if(is_stereo) 2 else 1,
        .sample_rate = sample_rate,
    });
}

var samples_pushed: usize = 0;
var result_samples: std.ArrayList(f32) = .empty;
var audio_done: bool = false;
export fn frame() void {
    const samples_used = sokol.audio.push(&result_samples.items[samples_pushed], @intCast(result_samples.items.len));
    samples_pushed += @intCast(samples_used);
    if(samples_pushed >= result_samples.items.len) {
        audio_done = true;
        sokol.app.quit();
    }
}
pub export fn event(ev: ?*const sokol.app.Event) void {
    const e: *const sokol.app.Event = ev orelse &.{};
    switch(e.key_code) {
        .ESCAPE, .CAPS_LOCK => {
            sokol.app.quit();
        },
        else => {},
    }
}
export fn deinit() void {
    sokol.audio.shutdown();
    audio_done = true;
}

fn pushSamplesFlt(channels: [4]u5, panning: Panning, volume: Volume) struct{ f32, f32 } {
    var sample_flt: [4]f32 = undefined;
    for(&sample_flt, channels) |*flt, channel_val| {
        const channel_flt: f32 = @floatFromInt(channel_val);
        const normalized: f32 = channel_flt / 15.0;
        const result: f32 = normalized * 2.0 - 1.0;
        flt.* = result;
    }

    const ch1_right: f32 = if(panning.ch1_right) sample_flt[0] else 0.0;
    const ch2_right: f32 = if(panning.ch2_right) sample_flt[1] else 0.0;
    const ch3_right: f32 = if(panning.ch3_right) sample_flt[2] else 0.0;
    const ch4_right: f32 = if(panning.ch4_right) sample_flt[3] else 0.0;
    var right: f32 = ch1_right + ch2_right + ch3_right + ch4_right;
    const right_volume: f32 = (@as(f32, @floatFromInt(volume.right_volume)) + 1.0) / 8.0;
    right *= right_volume * platform_volume;
    right /= 4.0;

    const ch1_left: f32 = if(panning.ch1_left) sample_flt[0] else 0.0;
    const ch2_left: f32 = if(panning.ch2_left) sample_flt[1] else 0.0;
    const ch3_left: f32 = if(panning.ch3_left) sample_flt[2] else 0.0;
    const ch4_left: f32 = if(panning.ch4_left) sample_flt[3] else 0.0;
    var left: f32 = ch1_left + ch2_left + ch3_left + ch4_left;
    const left_volume: f32 = (@as(f32, @floatFromInt(volume.left_volume)) + 1.0) / 8.0;
    left *= left_volume * platform_volume;
    left /= 4.0;

    return .{ left, right };
}

pub fn runApuOutputTest() !void {
    const alloc = std.testing.allocator;

    const sample_file = "test_data/apu/aceman_apu_samples.txt";
    const sample_txt = try std.fs.cwd().readFileAlloc(alloc, sample_file, std.math.maxInt(u32));
    defer alloc.free(sample_txt);
    defer result_samples.deinit(alloc);

    var lineIt = std.mem.splitScalar(u8, sample_txt, '\n');
    _ = lineIt.next().?; // ignore first line which initializes the channels to 0.

    const volume: Volume = .{ 
        // TODO: Reducing volume does reduce it, but it also sounds like we are missing sound information?
        .left_volume = 7, .right_volume = 7, .vin_left = false, .vin_right = false 
    };
    const panning: Panning = .{
        .ch1_right = true, .ch2_right = true, .ch3_right = true, .ch4_right = true,
        .ch1_left = true,  .ch2_left = true,  .ch3_left = true,  .ch4_left = true,
    };

    var curr_cycles: u64 = 0;
    // TODO: Make my states u4 as they should be. For some reason, SameBoy uses 16 as an off value sometimes?
    var channels: [4]u5 = [_]u5{0} ** 4;
    var state_left: u5 = 0;
    var state_right: u5 = 0;
    while(lineIt.next()) |line| {
        if(line.len == 0) {
            continue;
        }
        var elemIt = std.mem.splitScalar(u8, line, ',');
        const cycles: u64 = try std.fmt.parseInt(u64, elemIt.next().?, 10);
        const channel_idx: u2 = try std.fmt.parseInt(u2, elemIt.next().?, 10);
        const value: u5 = try std.fmt.parseInt(u5, elemIt.next().?, 10);

        while(curr_cycles < cycles) : (curr_cycles += 1) {
            // TODO: t_cycles_per_sample does not cleanly divide into integer, so we are slightly of with our sample rate.
            if(curr_cycles % t_cycles_per_sample == 0) {
                // TODO: Flt version works, but not the u4 version, why?
                if(use_flt) {
                    const left_ref: f32, const right_ref: f32 = pushSamplesFlt(channels, panning, volume);
                    if(is_stereo) {
                        try result_samples.append(alloc, left_ref);
                        try result_samples.append(alloc, right_ref);
                    } else {
                        const mono_ref: f32 = (left_ref + right_ref) / 2.0;
                        try result_samples.append(alloc, mono_ref);
                    }
                } else {
                    if(is_stereo) {
                        var sample: f32 = sampleState(state_left, platform_volume);
                        try result_samples.append(alloc, sample);

                        sample = sampleState(state_right, platform_volume);
                        try result_samples.append(alloc, sample);
                    } else {
                        const mix_mono: u6 = @as(u6, state_left) + @as(u6, state_right) / 2;
                        const state_mono: u5 = @intCast(mix_mono);
                        const sample: f32 = sampleState(state_mono, platform_volume);
                        try result_samples.append(alloc, sample);
                    }
                }
            }
        }

        channels[channel_idx] = value;
        state_left, state_right = mixChannels(channels[0], channels[1], channels[2], channels[3], panning, volume);
    }

    sokol.app.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = deinit,
        .event_cb = event,
        .width = def.window_width,
        .height = def.window_height,
        .icon = .{ .sokol_default = true },
        .window_title = "Audio Test",
        .logger = .{ .func = sokol.log.func },
    });
    try std.testing.expectEqual(true, audio_done);
}
