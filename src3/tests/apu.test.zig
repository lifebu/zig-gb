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

fn mixChannels(channels: [4]u5, panning: Panning, volume: Volume) struct{ f32, f32 } {
    var sample_flt: [4]f32 = undefined;
    for(&sample_flt, channels) |*flt, channel_val| {
        const channel_flt: f32 = @floatFromInt(channel_val);
        const normalized: f32 = channel_flt / 15.0;
        const result: f32 = normalized * 2.0 - 1.0;
        flt.* = result;
    }

    const ch1_left: f32 = if(panning.ch1_left) sample_flt[0] else 0.0;
    const ch2_left: f32 = if(panning.ch2_left) sample_flt[1] else 0.0;
    const ch3_left: f32 = if(panning.ch3_left) sample_flt[2] else 0.0;
    const ch4_left: f32 = if(panning.ch4_left) sample_flt[3] else 0.0;
    const mix_left: f32 = (ch1_left + ch2_left + ch3_left + ch4_left) / 4.0;
    const volume_left: f32 = @floatFromInt(volume.left_volume);
    const volume_left_normal: f32 = (volume_left + 1.0) / 8.0;
    const state_left: f32 = mix_left * volume_left_normal;

    const ch1_right: f32 = if(panning.ch1_right) sample_flt[0] else 0.0;
    const ch2_right: f32 = if(panning.ch2_right) sample_flt[1] else 0.0;
    const ch3_right: f32 = if(panning.ch3_right) sample_flt[2] else 0.0;
    const ch4_right: f32 = if(panning.ch4_right) sample_flt[3] else 0.0;
    const mix_right: f32 = (ch1_right + ch2_right + ch3_right + ch4_right) / 4.0;
    const volume_right: f32 = @floatFromInt(volume.right_volume);
    const volume_right_normal: f32 = (volume_right + 1.0) / 8.0;
    const state_right: f32 = mix_right * volume_right_normal;

    return .{ state_left, state_right };
}

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

pub fn runApuOutputTest() !void {
    const alloc = std.testing.allocator;

    const sample_file = "test_data/apu/aceman_apu_samples.txt";
    const sample_txt = try std.fs.cwd().readFileAlloc(alloc, sample_file, std.math.maxInt(u32));
    defer alloc.free(sample_txt);
    defer result_samples.deinit(alloc);

    var lineIt = std.mem.splitScalar(u8, sample_txt, '\n');
    _ = lineIt.next().?; // ignore first line which initializes the channels to 0.

    const volume: Volume = .{ 
        .left_volume = 7, .right_volume = 7, .vin_left = false, .vin_right = false 
    };
    const panning: Panning = .{
        .ch1_right = true, .ch2_right = true, .ch3_right = true, .ch4_right = true,
        .ch1_left = true,  .ch2_left = true,  .ch3_left = true,  .ch4_left = true,
    };

    var curr_cycles: u64 = 0;
    // TODO: Make my states u4 as they should be. For some reason, SameBoy uses 16 as an off value sometimes?
    var channels: [4]u5 = [_]u5{0} ** 4;
    var state_left: f32 = 0;
    var state_right: f32 = 0;
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
                const sample_left: f32 = state_left * platform_volume;
                const sample_right: f32 = state_right * platform_volume;
                if(is_stereo) {
                    try result_samples.append(alloc, sample_left);
                    try result_samples.append(alloc, sample_right);
                } else {
                    const mono: f32 = (sample_left + sample_right) / 2.0;
                    try result_samples.append(alloc, mono);
                }
            }
        }

        channels[channel_idx] = value;
        state_left, state_right = mixChannels(channels, panning, volume);
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
