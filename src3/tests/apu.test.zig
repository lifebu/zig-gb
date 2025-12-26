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
    _ = volume; // TODO: Volume is in [0, 7] but sampels are in [0, 15]

    const ch1_left: u6 = ch1 * @intFromBool(panning.ch1_left);
    const ch2_left: u6 = ch2 * @intFromBool(panning.ch2_left);
    const ch3_left: u6 = ch3 * @intFromBool(panning.ch3_left);
    const ch4_left: u6 = ch4 * @intFromBool(panning.ch4_left);
    const mix_left: u6 = (ch1_left + ch2_left + ch3_left + ch4_left) / 4;
    const sample_left: u4 = @intCast(mix_left);

    const ch1_right: u6 = ch1 * @intFromBool(panning.ch1_right);
    const ch2_right: u6 = ch2 * @intFromBool(panning.ch2_right);
    const ch3_right: u6 = ch3 * @intFromBool(panning.ch3_right);
    const ch4_right: u6 = ch4 * @intFromBool(panning.ch4_right);
    const mix_right: u6 = (ch1_right + ch2_right + ch3_right + ch4_right) / 4;
    const sample_right: u4 = @intCast(mix_right);

    return .{ sample_left, sample_right };
}
fn sampleToPlatform(sample: u5, volume: f32) f32 {
    const normalized: f32 = @as(f32, @floatFromInt(sample)) / 16.0;
    const ranged: f32 = (normalized * 2.0) - 1.0;
    const result: f32 = ranged * volume;
    return result;
}

const platform_volume: f32 = 0.1;
const is_stereo: bool = false;
const sample_rate = 48_000;
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
    if(samples_pushed > result_samples.items.len) {
        audio_done = true;
        sokol.app.quit();
        return;
    }

    const samples_used = sokol.audio.push(&result_samples.items[samples_pushed], @intCast(result_samples.items.len));
    samples_pushed += @intCast(samples_used);
}
export fn deinit() void {
    sokol.audio.shutdown();
    audio_done = true;
}
fn imgui_cb(_: []const u8) void {}

pub fn runApuOutputTest() !void {
    const alloc = std.testing.allocator;

    const sample_file = "test_data/apu/aceman_apu_samples.txt";
    const sample_txt = try std.fs.cwd().readFileAlloc(alloc, sample_file, std.math.maxInt(u32));
    defer alloc.free(sample_txt);
    defer result_samples.deinit(alloc);

    var lineIt = std.mem.splitScalar(u8, sample_txt, '\n');
    _ = lineIt.next().?; // ignore first line which initializes the channels to 0.

    const volume: Volume = .{ 
        .left_volume = 0, .right_volume = 0, .vin_left = false, .vin_right = false 
    };
    const panning: Panning = .{
        .ch1_right = true, .ch2_right = true, .ch3_right = true, .ch4_right = true,
        .ch1_left = true,  .ch2_left = true,  .ch3_left = true,  .ch4_left = true,
    };

    var curr_cycles: u64 = 0;
    // TODO: Make my samples u4 as they should be. For some reason, SameBoy uses 16 as an off value sometimes?
    var samples: [4]u5 = [_]u5{0} ** 4;
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
                const sample_left: u4, const sample_right = mixChannels(samples[0], samples[1], samples[2], samples[3], panning, volume);
                if(is_stereo) {
                    // TODO: with stereo, the audio sounds half as fast?
                    var sample_platform: f32 = sampleToPlatform(sample_left, platform_volume);
                    try result_samples.append(alloc, sample_platform);

                    sample_platform = sampleToPlatform(sample_right, platform_volume);
                    try result_samples.append(alloc, sample_platform);
                } else {
                    const mix_mono: u6 = @as(u6, sample_left) + @as(u6, sample_right) / 2;
                    const sample_mono: u5 = @intCast(mix_mono);
                    const sample_platform: f32 = sampleToPlatform(sample_mono, platform_volume);
                    try result_samples.append(alloc, sample_platform);
                }
            }
        }

        samples[channel_idx] = value;
    }

    sokol.app.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = deinit,
        .width = def.window_width,
        .height = def.window_height,
        .icon = .{ .sokol_default = true },
        .window_title = "Audio Test",
        .logger = .{ .func = sokol.log.func },
    });
    try std.testing.expectEqual(true, audio_done);
}
