const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const MMIO = @import("../mmio.zig");
const mem_map = @import("../mem_map.zig");

pub fn runInputTests() !void {
    var mmio: MMIO = .{};

    const TestCase = struct {
        name: []const u8,
        write: u8,
        expected: u8,
        input: def.InputState,
    };
    const testCases = [_]TestCase {
        TestCase {
            .name = "Nothing selected but have pressed button/dpad",
            .write = 0b1111_1111,
            .expected = 0b1111_1111,
            .input = def.InputState {
                .down_pressed = true, .up_pressed = false, .left_pressed = true, .right_pressed = false,
                .start_pressed = false, .select_pressed = true, .b_pressed = false, .a_pressed = true,
            },
        },
        TestCase {
            .name = "Select dpad and nothing pressed",
            .write = 0b1110_1111,
            .expected = 0b1110_1111,
            .input = def.InputState {
                .down_pressed = false, .up_pressed = false, .left_pressed = false, .right_pressed = false,
                .start_pressed = false, .select_pressed = false, .b_pressed = false, .a_pressed = false,
            },
        },
        TestCase {
            .name = "Select dpad and down pressed.",
            .write = 0b1110_1111,
            .expected = 0b1110_0111,
            .input = def.InputState {
                .down_pressed = true, .up_pressed = false, .left_pressed = false, .right_pressed = false,
                .start_pressed = false, .select_pressed = false, .b_pressed = false, .a_pressed = false,
            },
        },
        TestCase {
            .name = "Select dpad and up pressed.",
            .write = 0b1110_1111,
            .expected = 0b1110_1011,
            .input = def.InputState {
                .down_pressed = false, .up_pressed = true, .left_pressed = false, .right_pressed = false,
                .start_pressed = false, .select_pressed = false, .b_pressed = false, .a_pressed = false,
            },
        },
        TestCase {
            .name = "Select dpad and left pressed.",
            .write = 0b1110_1111,
            .expected = 0b1110_1101,
            .input = def.InputState {
                .down_pressed = false, .up_pressed = false, .left_pressed = true, .right_pressed = false,
                .start_pressed = false, .select_pressed = false, .b_pressed = false, .a_pressed = false,
            },
        },
        TestCase {
            .name = "Select dpad and right pressed.",
            .write = 0b1110_1111,
            .expected = 0b1110_1110,
            .input = def.InputState {
                .down_pressed = false, .up_pressed = false, .left_pressed = false, .right_pressed = true,
                .start_pressed = false, .select_pressed = false, .b_pressed = false, .a_pressed = false,
            },
        },
        TestCase {
            .name = "Select dpad and left,right,up,down pressed (impossible inputs).",
            .write = 0b1110_1111,
            .expected = 0b1110_1111,
            .input = def.InputState {
                .down_pressed = true, .up_pressed = true, .left_pressed = true, .right_pressed = true,
                .start_pressed = false, .select_pressed = false, .b_pressed = false, .a_pressed = false,
            },
        },
        TestCase {
            .name = "Select button and nothing pressed",
            .write = 0b1101_1111,
            .expected = 0b1101_1111,
            .input = def.InputState {
                .down_pressed = false, .up_pressed = false, .left_pressed = false, .right_pressed = false,
                .start_pressed = false, .select_pressed = false, .b_pressed = false, .a_pressed = false,
            },
        },
        TestCase {
            .name = "Select button and start pressed.",
            .write = 0b1101_1111,
            .expected = 0b1101_0111,
            .input = def.InputState {
                .down_pressed = false, .up_pressed = false, .left_pressed = false, .right_pressed = false,
                .start_pressed = true, .select_pressed = false, .b_pressed = false, .a_pressed = false,
            },
        },
        TestCase {
            .name = "Select button and select pressed.",
            .write = 0b1101_1111,
            .expected = 0b1101_1011,
            .input = def.InputState {
                .down_pressed = false, .up_pressed = false, .left_pressed = false, .right_pressed = false,
                .start_pressed = false, .select_pressed = true, .b_pressed = false, .a_pressed = false,
            },
        },
        TestCase {
            .name = "Select button and b pressed.",
            .write = 0b1101_1111,
            .expected = 0b1101_1101,
            .input = def.InputState {
                .down_pressed = false, .up_pressed = false, .left_pressed = false, .right_pressed = false,
                .start_pressed = false, .select_pressed = false, .b_pressed = true, .a_pressed = false,
            },
        },
        TestCase {
            .name = "Select button and a pressed.",
            .write = 0b1101_1111,
            .expected = 0b1101_1110,
            .input = def.InputState {
                .down_pressed = false, .up_pressed = false, .left_pressed = false, .right_pressed = false,
                .start_pressed = false, .select_pressed = false, .b_pressed = false, .a_pressed = true,
            },
        },
        TestCase {
            .name = "Select buttons and dpad and some inputs pressed. Expecting output and of dpad and buttons.",
            .write = 0b1100_1111,
            .expected = 0b1100_0001,
            .input = def.InputState {
                .down_pressed = true, .up_pressed = false, .left_pressed = true, .right_pressed = false,
                .start_pressed = true, .select_pressed = true, .b_pressed = false, .a_pressed = false,
            },
        },
    };

    for(testCases, 0..) |testCase, i| {
        if(i == 0) { // Change value to attach debugger.
            var val: u32 = 0; val += 1;
        }
        var request: def.Request = .{ .address = mem_map.joypad, .value = .{ .write = testCase.write } };
        _ = mmio.updateInputState(&testCase.input);
        mmio.request(&request);
        std.testing.expectEqual(testCase.expected, mmio.joypad) catch |err| {
            std.debug.print("Failed {d}: {s}\n", .{ i, testCase.name });
            return err;
        };
    }

    // Lower nibble is read-only to cpu.
    mmio.joypad = 0b1111_1111;
    var request: def.Request = .{ .address = mem_map.joypad, .value = .{ .write = 0b1111_0000 } };
    mmio.request(&request);
    std.testing.expectEqual(0b1111_1111, mmio.joypad) catch |err| {
        std.debug.print("Failed {d}: {s}\n", .{ testCases.len, "Lower nibble is ready-only to cpu" });
        return err;
    };

    // Interrupt
    var irq_joypad: bool = false;
    irq_joypad = mmio.updateInputState(&def.InputState{
        .down_pressed = false, .up_pressed = false, .left_pressed = false, .right_pressed = false,
        .start_pressed = false, .select_pressed = false, .b_pressed = false, .a_pressed = false,
    });
    std.testing.expectEqual(false, irq_joypad) catch |err| {
        std.debug.print("Failed: Joypad interrupt is triggered correctly.\n", .{});
        return err;
    };
    irq_joypad = mmio.updateInputState(&def.InputState{
        .down_pressed = true, .up_pressed = true, .left_pressed = true, .right_pressed = true,
        .start_pressed = true, .select_pressed = true, .b_pressed = true, .a_pressed = true,
    });
    std.testing.expectEqual(true, irq_joypad) catch |err| {
        std.debug.print("Failed: Joypad interrupt is triggered correctly.\n", .{});
        return err;
    };
}

pub fn runDividerTests() !void {
    var mmio: MMIO = .{};
    var irq_timer: bool = false;

    var request: def.Request = .{ .address = mem_map.divider, .value = .{ .write = 255 } };
    mmio.request(&request);
    _ = mmio.cycle();
    std.testing.expectEqual(0, mmio.divider) catch |err| {
        std.debug.print("Failed: Divider is reset by writing to DIV.\n", .{});
        return err;
    };

    var expected_div: u8 = 0;
    const div_freq = 256;
    for(0..300) |_| {
        for(0..div_freq) |_| {
            _, irq_timer = mmio.cycle();
        }
        expected_div +%= 1;
        std.testing.expectEqual(expected_div, mmio.divider) catch |err| {
            std.debug.print("Failed: Divider is incremented every 256 cycles.\n", .{});
            return err;
        };
    }
}

pub fn runTimerTest() !void {
    var mmio: MMIO = .{};
    var irq_timer: bool = false;

    const CycleTestCase = struct {
        cycles: u16,
        timer_control: MMIO.TimerControl,
    };
    const cycleCases = [_]CycleTestCase {
        .{ .cycles = 1024, .timer_control = .{ .enable = true, .clock = 0 } }, 
        .{ .cycles = 16,   .timer_control = .{ .enable = true, .clock = 1 } }, 
        .{ .cycles = 64,   .timer_control = .{ .enable = true, .clock = 2 } }, 
        .{ .cycles = 256,  .timer_control = .{ .enable = true, .clock = 3 } },
    };
    for(cycleCases, 0..) |cycleCase, i| {
        if(i == 0) { // Change value to attach debugger.
            var val: u32 = 0; val += 1;
        }

        mmio = .{};
        mmio.timer_control = @bitCast(cycleCase.timer_control);
        for(0..cycleCase.cycles) |_| {
            _, irq_timer = mmio.cycle();
        }
        std.testing.expectEqual(0x01, mmio.timer) catch |err| {
            std.debug.print("Failed: Timer increments every {d} cycles.\n", .{ cycleCase.cycles });
            return err;
        };
    }

    // overflow
    mmio = .{};
    mmio.timer = 0xFF;
    mmio.timer_mod = 0x05;
    mmio.timer_control = .{ .enable = true, .clock = 3 };
    for(0..256) |_| {
        _, irq_timer = mmio.cycle();
    }
    // TIMA value is applied 4 cycles later.
    std.testing.expectEqual(0x00, mmio.timer) catch |err| {
        std.debug.print("Failed: Timer mod is not applied immediately.\n", .{});
        return err;
    };
    std.testing.expectEqual(false, irq_timer) catch |err| {
        std.debug.print("Failed: Timer interrupt is not triggered immediately.\n", .{});
        return err;
    };
    for(0..4) |_| {
        _, irq_timer = mmio.cycle();
    }
    std.testing.expectEqual(0x05, mmio.timer) catch |err| {
        std.debug.print("Failed: Timer mod is applied after 4 cycles.\n", .{});
        return err;
    };
    std.testing.expectEqual(true, irq_timer) catch |err| {
        std.debug.print("Failed: Timer interrupt is applied after 4 cycles.\n", .{});
        return err;
    };

    // disable can increment timer.
    mmio = .{};
    mmio.timer = 0x05;
    mmio.system_counter = 0xFFFD;
    mmio.timer_control = .{ .enable = true, .clock = 3 };
    _, irq_timer = mmio.cycle();
    mmio.timer_control = .{ .enable = false, .clock = 3 };
    _, irq_timer = mmio.cycle();
    std.testing.expectEqual(0x06, mmio.timer) catch |err| {
        std.debug.print("Failed: Disabling timer can increment it.\n", .{});
        return err;
    };

    // overflow: cpu writes abort timer_mod
    mmio = .{};
    mmio.timer = 0xFF;
    mmio.timer_mod = 0x05;
    mmio.timer_control = .{ .enable = true, .clock = 3 };
    for(0..256) |_| {
        _, irq_timer = mmio.cycle();
    }
    var request: def.Request = .{ .address = mem_map.timer, .value = .{ .write = 0x10 } };
    mmio.request(&request);
    for(0..4) |_| {
        _, irq_timer = mmio.cycle();
    }
    std.testing.expectEqual(0x10, mmio.timer) catch |err| {
        std.debug.print("Failed: Writing to timer aborts modulo.\n", .{});
        return err;
    };
    std.testing.expectEqual(false, irq_timer) catch |err| {
        std.debug.print("Failed: Writing to timer aborts interrupt.\n", .{});
        return err;
    };

    // overflow: cpu write TIMA on 4th cycle => write is ignored
    mmio = .{};
    mmio.timer = 0xFF;
    mmio.timer_mod = 0x05;
    mmio.timer_control = .{ .enable = true, .clock = 3 };
    for(0..(256 + 3)) |_| {
        _, irq_timer = mmio.cycle();
    }
    request = .{ .address = mem_map.timer, .value = .{ .write = 0x33 } };
    mmio.request(&request);
    _, irq_timer = mmio.cycle();
    std.testing.expectEqual(0x05, mmio.timer) catch |err| {
        std.debug.print("Failed: Writing to tima on 4th cycle leads to the write being ignored.\n", .{});
        return err;
    };

    // overflow: cpu write TMA on 4th cycle => new TMA value is used.
    mmio = .{};
    mmio.timer = 0xFF;
    mmio.timer_mod = 0x05;
    mmio.timer_control = .{ .enable = true, .clock = 3 };
    for(0..(256 + 3)) |_| {
        _, irq_timer = mmio.cycle();
    }
    request = .{ .address = mem_map.timer_mod, .value = .{ .write = 0x22 } };
    mmio.request(&request);
    _, irq_timer = mmio.cycle();
    std.testing.expectEqual(0x22, mmio.timer) catch |err| {
        std.debug.print("Failed: Writing to timer mod on 4th cycle leads to the new value used for the modulo.\n", .{});
        return err;
    };
}
