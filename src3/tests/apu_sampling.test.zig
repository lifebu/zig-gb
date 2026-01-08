const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const APU = @import("../apu.zig");
const Platform = @import("../platform.zig");
const mem_map = @import("../mem_map.zig");

const sokol = @import("sokol");

fn drawSample(apu: *APU.State, ch1: u4, ch2: u4, ch3: u4, ch4: u4) def.Sample {
    apu.channel_values[0] = ch1;
    apu.channel_values[1] = ch2;
    apu.channel_values[2] = ch3;
    apu.channel_values[3] = ch4;
    apu.sample_tick = 0;
    return APU.cycle(apu).?;
}

pub fn runApuSamplingTests() !void {
    // TODO: Can we detect when the audio device has starved at any moment?
    // TODO: Test that the sample rate was hit over a period of time?
    // TODO: Test that we never wasted any samples.
    // TODO: Test we handle less than 60fps correctly.
    var apu: APU.State = .{};
    APU.init(&apu);

    var sample: def.Sample = .{};
    apu.volume = .{
        .left_volume = 7, .right_volume = 7, .vin_left = false, .vin_right = false,
    };
    apu.panning = .{
        .ch1_right = true, .ch2_right = true, .ch3_right = true, .ch4_right = true,
        .ch1_left = true,  .ch2_left = true,  .ch3_left = true,  .ch4_left = true,
    };

    // correct sample range [-1, 1]
    sample = drawSample(&apu, 0, 0, 0, 0);
    std.testing.expectApproxEqAbs(-1.0, sample.left, std.math.floatEps(f32)) catch |err| {
        std.debug.print("Failed: Channels not in [-1, 1] range.\n", .{});
        return err;
    };
    sample = drawSample(&apu, 8, 7, 7, 8);
    std.testing.expectApproxEqAbs(0.0, sample.left, std.math.floatEps(f32)) catch |err| {
        std.debug.print("Failed: Channels not in [-1, 1] range.\n", .{});
        return err;
    };
    sample = drawSample(&apu, 15, 15, 15, 15);
    std.testing.expectApproxEqAbs(1.0, sample.left, std.math.floatEps(f32)) catch |err| {
        std.debug.print("Failed: Channels not in [-1, 1] range.\n", .{});
        return err;
    };

    // master volume is applied
    for(0..std.math.maxInt(u3)) |input| {
        const input_flt: f32 = @floatFromInt(input);
        const expected: f32 = (input_flt + 1.0) / 8.0;
        apu.volume = .{
            .left_volume = @intCast(input), .right_volume = 7, .vin_left = false, .vin_right = false 
        };
        sample = drawSample(&apu, 15, 15, 15, 15);
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
    apu.volume = .{
        .left_volume = 7, .right_volume = 7, .vin_left = false, .vin_right = false,
    };
    for(0..apu.channel_values.len) |channel_idx| {
        apu.channel_values = @splat(0);
        apu.channel_values[channel_idx] = 15;

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
            apu.panning.ch1_left = test_case.left;
            apu.panning.ch2_left = test_case.left;
            apu.panning.ch3_left = test_case.left;
            apu.panning.ch4_left = test_case.left;
            apu.panning.ch1_right = test_case.right;
            apu.panning.ch2_right = test_case.right;
            apu.panning.ch3_right = test_case.right;
            apu.panning.ch4_right = test_case.right;

            apu.sample_tick = 0;
            sample = APU.cycle(&apu).?;

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

const Inputs = struct {
    cycles: u64, channel_idx: u2, value: u4,
};
const State = struct {
    use_precalc: bool,

    // precalc
    result_samples: std.ArrayList(f32) = .empty,
    samples_pushed: usize = 0,
    audio_done: bool = false,

    // sync
    curr_cycles: u64 = 0,
    curr_input_idx: usize = 0,
    input_states: std.ArrayList(Inputs) = .empty,
    apu: *APU.State,
    platform: *Platform.State,
};
export fn init_test(state_opaque: ?*anyopaque) void {
    const state: *State = @alignCast(@ptrCast(state_opaque.?));
    sokol.audio.setup(.{
        .logger = .{ .func = sokol.log.func },
        .num_channels = def.samples_per_frame,
        .sample_rate = def.sample_rate,
    });
    APU.init(state.apu);
}
export fn event_test(ev: ?*const sokol.app.Event) void {
    const e: *const sokol.app.Event = ev orelse &.{};
    switch(e.key_code) {
        .ESCAPE, .CAPS_LOCK => { sokol.app.quit(); },
        else => {},
    }
}
export fn deinit_test(state_opaque: ?*anyopaque) void {
    const state: *State = @alignCast(@ptrCast(state_opaque.?));

    sokol.audio.shutdown();
    state.audio_done = true;
}

export fn frame_test(state_opaque: ?*anyopaque) void {
    const state: *State = @alignCast(@ptrCast(state_opaque.?));
    if(state.use_precalc) {
        const frames_used: i32 = sokol.audio.push(&state.result_samples.items[state.samples_pushed], @intCast(state.result_samples.items.len));
        state.samples_pushed += @as(usize, @intCast(frames_used)) * def.samples_per_frame;
        if(state.samples_pushed >= state.result_samples.items.len) {
            state.audio_done = true;
            sokol.app.quit();
        }
    } else {
        const cycles_per_frame = 70224; 
        for(0..cycles_per_frame) |_| {
            const sample: ?def.Sample = APU.cycle(state.apu);
            if(sample) |value| {
                Platform.pushSample(state.platform, value);
            }

            state.curr_cycles += 1;
            const curr_input: Inputs = state.input_states.items[state.curr_input_idx];
            if(state.curr_cycles >= curr_input.cycles) {
                state.apu.channel_values[curr_input.channel_idx] = curr_input.value;
                state.curr_input_idx += 1;
                if(state.curr_input_idx >= state.input_states.items.len) {
                    state.audio_done = true;
                    sokol.app.quit();
                }
            }
        }
    }
}

pub fn runApuOutputTest(use_precalc: bool) !void {
    var apu: APU.State = .{};
    var platform: Platform.State = .{};
    APU.init(&apu);

    const alloc = std.testing.allocator;

    var state: State = .{ .use_precalc = use_precalc, .apu = &apu, .platform = &platform };
    defer state.result_samples.deinit(alloc);
    defer state.input_states.deinit(alloc);

    const sample_file = "test_data/apu/aceman_apu_samples.txt";
    const sample_txt = try std.fs.cwd().readFileAlloc(alloc, sample_file, std.math.maxInt(u32));
    defer alloc.free(sample_txt);

    var lineIt = std.mem.splitScalar(u8, sample_txt, '\n');
    _ = lineIt.next().?; // ignore first line which initializes the channels to 0.

    apu.volume = .{
        .left_volume = 7, .right_volume = 7, .vin_left = false, .vin_right = false,
    };
    apu.panning = .{
        .ch1_right = true, .ch2_right = true, .ch3_right = true, .ch4_right = true,
        .ch1_left = true,  .ch2_left = true,  .ch3_left = true,  .ch4_left = true,
    };

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

        if(use_precalc) {
            while(curr_cycles < cycles) : (curr_cycles += 1) {
                const sample: ?def.Sample = APU.cycle(&apu);
                if(sample) |sample_val| {
                    const sample_left: f32 = sample_val.left * def.default_platform_volume;
                    const sample_right: f32 = sample_val.right * def.default_platform_volume;
                    if(def.is_stereo) {
                        try state.result_samples.append(alloc, sample_left);
                        try state.result_samples.append(alloc, sample_right);
                    } else {
                        const mono: f32 = (sample_left + sample_right) / 2.0;
                        try state.result_samples.append(alloc, mono);
                    }
                }
            }
            apu.channel_values[channel_idx] = value;
        } else {
            try state.input_states.append(alloc, .{ .cycles = cycles, .channel_idx = channel_idx, .value = value });
        }
    }

    sokol.app.run(.{
        .init_userdata_cb = init_test,
        .frame_userdata_cb = frame_test,
        .cleanup_userdata_cb = deinit_test,
        .event_cb = event_test,
        .user_data = &state,
        .width = def.window_width,
        .height = def.window_height,
        .icon = .{ .sokol_default = true },
        .window_title = "Audio Test",
        .logger = .{ .func = sokol.log.func },
    });
    try std.testing.expectEqual(true, state.audio_done);
}
