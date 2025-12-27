const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const MMU = @import("../mmu.zig");
const def = @import("../defines.zig");
const APU = @import("../apu.zig");
const Platform = @import("../platform.zig");
const mem_map = @import("../mem_map.zig");

const sokol = @import("sokol");

// TODO: Implement channels:
// 3: Period, Volume shift, Length, Wave-Table
// 2: Period, Volume envelope, Length, Duty-Table
// 3: Period, Volume envelope, Length, Sweep, Duty-Table 
// 4: Period, Volume envelope, Length, LFSR 

// APU structure:
// - apu.cycle() returns an optional sample (sampler part of apu). try push sample to platform.
// - emulator has no sound buffer. sokol.audio already has a buffer.

fn drawSample(apu: *APU.State, mmu: *MMU.State, ch1: u4, ch2: u4, ch3: u4, ch4: u4) def.Sample {
    apu.channels[0] = ch1;
    apu.channels[1] = ch2;
    apu.channels[2] = ch3;
    apu.channels[3] = ch4;
    apu.sample_counter = 0;
    return APU.cycle(apu, mmu).?;
}

pub fn runApuSamplingTests() !void {
    // TODO: Can we detect when the audio device has starved at any moment?
    // TODO: Test that the sample rate was hit over a period of time?

    var apu: APU.State = .{};
    var mmu: MMU.State = .{}; 
    APU.init(&apu);

    var sample: def.Sample = .{};
    mmu.memory[mem_map.master_volume] = @bitCast(APU.Volume {
        .left_volume = 7, .right_volume = 7, .vin_left = false, .vin_right = false,
    });
    mmu.memory[mem_map.sound_panning] = @bitCast(APU.Panning {
        .ch1_right = true, .ch2_right = true, .ch3_right = true, .ch4_right = true,
        .ch1_left = true,  .ch2_left = true,  .ch3_left = true,  .ch4_left = true,
    });

    // correct sample range [-1, 1]
    sample = drawSample(&apu, &mmu, 0, 0, 0, 0);
    std.testing.expectApproxEqAbs(-1.0, sample.left, std.math.floatEps(f32)) catch |err| {
        std.debug.print("Failed: Channels not in [-1, 1] range.\n", .{});
        return err;
    };
    sample = drawSample(&apu, &mmu, 8, 7, 7, 8);
    std.testing.expectApproxEqAbs(0.0, sample.left, std.math.floatEps(f32)) catch |err| {
        std.debug.print("Failed: Channels not in [-1, 1] range.\n", .{});
        return err;
    };
    sample = drawSample(&apu, &mmu, 15, 15, 15, 15);
    std.testing.expectApproxEqAbs(1.0, sample.left, std.math.floatEps(f32)) catch |err| {
        std.debug.print("Failed: Channels not in [-1, 1] range.\n", .{});
        return err;
    };

    // master volume is applied
    for(0..std.math.maxInt(u3)) |input| {
        const input_flt: f32 = @floatFromInt(input);
        const expected: f32 = (input_flt + 1.0) / 8.0;
        mmu.memory[mem_map.master_volume] = @bitCast(APU.Volume {
            .left_volume = @intCast(input), .right_volume = 7, .vin_left = false, .vin_right = false 
        });
        sample = drawSample(&apu, &mmu, 15, 15, 15, 15);
        std.testing.expectApproxEqAbs(expected, sample.left, std.math.floatEps(f32)) catch |err| {
            std.debug.print("Failed: Master volume not correctly applied.\n", .{});
            return err;
        };
        std.testing.expectApproxEqAbs(1.0, sample.right, std.math.floatEps(f32)) catch |err| {
            std.debug.print("Failed: Master volume not correctly applied.\n", .{});
            return err;
        };
    }

    // panning is correctly applied (stereo).    
    mmu.memory[mem_map.master_volume] = @bitCast(APU.Volume {
        .left_volume = 7, .right_volume = 7, .vin_left = false, .vin_right = false,
    });
    for(0..apu.channels.len) |channel_idx| {
        apu.channels = [_]u4{ 0 } ** apu.channels.len;
        apu.channels[channel_idx] = 15;

        const lower_nibble_on: u8 = @as(u8, 1) << @intCast(channel_idx);
        const higher_nibble_on: u8 = lower_nibble_on << 4;

        const PanningCase = struct {
            left: bool, right: bool
        };
        const test_cases = [4]PanningCase{
            .{ .left = false, .right = false },
            .{ .left = false, .right = true },
            .{ .left = true, .right = false },
            .{ .left = true, .right = true },
        };
        for (test_cases) |test_case| {
            const lower_nibble: u8 = if(test_case.right) lower_nibble_on else 0;
            const high_nibble: u8 = if(test_case.left) higher_nibble_on else 0;
            mmu.memory[mem_map.sound_panning] = lower_nibble | high_nibble;

            apu.sample_counter = 0;
            sample = APU.cycle(&apu, &mmu).?;

            const expected_left: f32 = if(test_case.left) 0.25 else 0.0;
            std.testing.expectApproxEqAbs(expected_left, sample.left, std.math.floatEps(f32)) catch |err| {
                std.debug.print("Failed: Panning (L:{}, R:{}): Left sample must be {}.\n", .{ test_case.left, test_case.right, expected_left });
                return err;
            };

            const expected_right: f32 = if(test_case.right) 0.25 else 0.0;
            std.testing.expectApproxEqAbs(expected_right, sample.right, std.math.floatEps(f32)) catch |err| {
                std.debug.print("Failed: Panning (L:{}, R:{}): Right sample must be {}.\n", .{ test_case.left, test_case.right, expected_right });
                return err;
            };

        } 
    }
}

export fn init() void {
    sokol.audio.setup(.{
        .logger = .{ .func = sokol.log.func },
        .num_channels = def.samples_per_frame,
        .sample_rate = def.sample_rate,
    });
}
var samples_pushed: usize = 0;
var result_samples: std.ArrayList(f32) = .empty;
var audio_done: bool = false;
export fn frame() void {
    // TODO: use sokol.audio.expect() instead? How would this work on the real APU?
    const frames_used = sokol.audio.push(&result_samples.items[samples_pushed], @intCast(result_samples.items.len));
    samples_pushed += @as(usize, @intCast(frames_used)) * def.samples_per_frame;
    if(samples_pushed >= result_samples.items.len) {
        audio_done = true;
        sokol.app.quit();
    }
}
pub export fn event(ev: ?*const sokol.app.Event) void {
    const e: *const sokol.app.Event = ev orelse &.{};
    switch(e.key_code) {
        .ESCAPE, .CAPS_LOCK => { sokol.app.quit(); },
        else => {},
    }
}
export fn deinit() void {
    sokol.audio.shutdown();
    audio_done = true;
}

pub fn runApuOutputTest() !void {
    var apu: APU.State = .{};
    var mmu: MMU.State = .{}; 
    APU.init(&apu);

    const alloc = std.testing.allocator;
    const sample_file = "test_data/apu/aceman_apu_samples.txt";
    const sample_txt = try std.fs.cwd().readFileAlloc(alloc, sample_file, std.math.maxInt(u32));
    defer alloc.free(sample_txt);
    defer result_samples.deinit(alloc);

    var lineIt = std.mem.splitScalar(u8, sample_txt, '\n');
    _ = lineIt.next().?; // ignore first line which initializes the channels to 0.
    
    mmu.memory[mem_map.master_volume] = @bitCast(APU.Volume {
        .left_volume = 7, .right_volume = 7, .vin_left = false, .vin_right = false,
    });
    mmu.memory[mem_map.sound_panning] = @bitCast(APU.Panning {
        .ch1_right = true, .ch2_right = true, .ch3_right = true, .ch4_right = true,
        .ch1_left = true,  .ch2_left = true,  .ch3_left = true,  .ch4_left = true,
    });

    var curr_cycles: u64 = 0;
    while(lineIt.next()) |line| {
        if(line.len == 0) {
            continue;
        }
        var elemIt = std.mem.splitScalar(u8, line, ',');
        const cycles: u64 = try std.fmt.parseInt(u64, elemIt.next().?, 10);
        const channel_idx: u2 = try std.fmt.parseInt(u2, elemIt.next().?, 10);
        // Note: Sameboy uses [0, 16] ranges (sometimes), but all channels has [0, 15].
        const value_raw: u5 = try std.fmt.parseInt(u5, elemIt.next().?, 10);
        const value: u4 = if(value_raw > 15) 15 else @intCast(value_raw);

        while(curr_cycles < cycles) : (curr_cycles += 1) {
            const sample: ?def.Sample = APU.cycle(&apu, &mmu);
            if(sample) |sample_val| {
                const platform_volume: f32 = 0.15;
                const sample_left: f32 = sample_val.left * platform_volume;
                const sample_right: f32 = sample_val.right * platform_volume;
                if(def.is_stereo) {
                    try result_samples.append(alloc, sample_left);
                    try result_samples.append(alloc, sample_right);
                } else {
                    const mono: f32 = (sample_left + sample_right) / 2.0;
                    try result_samples.append(alloc, mono);
                }
            }
        }

        apu.channels[channel_idx] = value;
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
