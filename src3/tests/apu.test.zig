const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const APU = @import("../apu.zig");
const mem_map = @import("../mem_map.zig");

fn initWaveTable(apu: *APU, pattern: [32]u4) void {
    for(&apu.ch3_wave_table, 0..) |*wave, idx| {
        const first_idx: usize = idx * 2;
        const low_nibble: u8 = pattern[first_idx + 1];
        const high_nibble: u8 = @as(u8, (pattern[first_idx])) << 4;
        wave.* = low_nibble | high_nibble;
    }
}

fn cpuWrite(apu: *APU, address: u16, value: u8) void {
    var request: def.Request = .{ .address = address, .value = .{ .write = value } };
    apu.request(&request);
}

pub fn runApuChannelTests() !void {
    var apu: APU  = .{};

    // CH3: Channel status bit is updated.
    apu.init();
    cpuWrite(&apu, mem_map.ch3_high_period, @bitCast(APU.Channel3PeriodHigh{
        .period = 0, .length_on = false, .trigger = true,
    }));
    std.testing.expectEqual(true, apu.control.ch3_on) catch |err| {
        std.debug.print("Failed: Ch3 status bit must be updated when we trigger channel 3.\n", .{});
        return err;
    };

    var wave_pattern: [32]u4 = undefined;
    for(&wave_pattern, 0..) |*pattern, idx| {
        pattern.* = @intCast(idx % 16);
    }
    initWaveTable(&apu, wave_pattern);

    // CH3: Wave Table is read left-to-right at correct frequency, dac and volume shift is supported.
    // TODO: Test that you can turn of a ch3 by turning it's dac of by setting it to false after starting ch3.
    const TestCase = struct {
        volume: u2 = 0b01,
        period: u11 = 2000,
        dac: bool = true,
    };
    const test_cases: [10]TestCase = .{
        .{ .volume = 0b00 }, .{ .volume = 0b01 }, .{ .volume = 0b10 }, .{ .volume = 0b11 },
        .{ .dac = false },
        .{ .period = 0 }, .{ .period = 511 }, .{ .period = 1023 }, .{ .period = 1535 }, 
        // TODO: period values above 2047 - 16 give wrong results, why?
        .{ .period = 2047 - 16 },
    };
    for(test_cases) |test_case| {
        apu.init();
        cpuWrite(&apu, mem_map.sound_control, @bitCast(APU.Control{
            .enable_apu = true, .ch1_on = false, .ch2_on = false, .ch3_on = false, .ch4_on = false,
        }));
        cpuWrite(&apu, mem_map.ch3_dac, @bitCast(APU.Channel3Dac{
            .dac_on = test_case.dac,
        }));
        cpuWrite(&apu, mem_map.ch3_length, @bitCast(APU.Channel3Length{
            .initial = 0,
        }));
        cpuWrite(&apu, mem_map.ch3_volume, @bitCast(APU.Channel3Volume{
            .shift = test_case.volume,
        }));
        cpuWrite(&apu, mem_map.ch3_low_period, @bitCast(APU.Channel3PeriodLow{
            .period = @truncate(test_case.period),
        }));
        cpuWrite(&apu, mem_map.ch3_high_period, @bitCast(APU.Channel3PeriodHigh{
            .period = @truncate(test_case.period >> 8), .length_on = false, .trigger = true,
        }));

        var pattern_idx: u5 = 1; 
        for(0..32) |sample_idx| {
            const cycles_per_value: u13 = APU.ch3_t_cycles_per_period * (2048 - @as(u13, test_case.period));
            for(0..cycles_per_value) |_| {
                _ = apu.cycle();
            }

            var expected = wave_pattern[pattern_idx];
            expected = if(test_case.dac) expected else APU.ch3_dac_off_value;
            expected = if(test_case.volume == 0b00) 0 else expected >> (test_case.volume - 1);
            std.testing.expectEqual(expected, apu.channel_values[2]) catch |err| {
                std.debug.print("Failed: Ch3: dac: {}, period: {}, vol: {}: sample {} does not match the wave table entry {}.\n", .{ test_case.dac, test_case.period, test_case.volume, sample_idx + 1, pattern_idx });
                return err;
            };
            pattern_idx +%= 1;
        }
    }
}
