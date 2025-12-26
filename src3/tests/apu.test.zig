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


const num_channels = 1; // 1 = Mono, 2 = Stereo.
const sample_rate = 48_000;
const t_cycles_per_sample = def.system_freq / sample_rate;
export fn init() void {
    sokol.audio.setup(.{
        .logger = .{ .func = sokol.log.func },
        .num_channels = num_channels,
        .sample_rate = sample_rate,
    });
}

var samples_pushed: usize = 0;
var result_samples: std.ArrayList(f32) = .empty;
var used_all_samples: bool = false;
export fn frame() void {
    if(samples_pushed > result_samples.items.len) {
        used_all_samples = true;
        sokol.app.quit();
        return;
    }

    const samples_used = sokol.audio.push(&result_samples.items[samples_pushed], @intCast(result_samples.items.len));
    samples_pushed += @intCast(samples_used);
}
export fn deinit() void {
    sokol.audio.shutdown();
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

    var curr_cycles: u64 = 0;
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
            if(curr_cycles % t_cycles_per_sample == 0) {
                const average: u6 = (@as(u6, samples[0]) + @as(u6, samples[1]) + @as(u6, samples[2]) + @as(u6, samples[3])) / 4;
                const average_sample: u4 = @intCast(average);
                const normalized: f32 = @as(f32, @floatFromInt(average_sample)) / 16.0;
                const ranged: f32 = (normalized * 2.0) - 1.0;
                const volumed: f32 = ranged * 0.1;
                try result_samples.append(alloc, volumed);
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
    try std.testing.expectEqual(true, used_all_samples);
}
