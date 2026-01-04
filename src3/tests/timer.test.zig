const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const TIMER = @import("../timer.zig");
const mem_map = @import("../mem_map.zig");

pub fn runDividerTests() !void {
    var timer: TIMER.State = .{};
    var irq_timer: bool = false;

    var request: def.Request = .{ .address = mem_map.divider, .value = .{ .write = 255 } };
    TIMER.request(&timer, &request);
    _ = TIMER.cycle(&timer);
    std.testing.expectEqual(0, timer.divider) catch |err| {
        std.debug.print("Failed: Divider is reset by writing to DIV.\n", .{});
        return err;
    };

    var expected_div: u8 = 0;
    const div_freq = 256;
    for(0..300) |_| {
        for(0..div_freq) |_| {
            irq_timer = TIMER.cycle(&timer);
        }
        expected_div +%= 1;
        std.testing.expectEqual(expected_div, timer.divider) catch |err| {
            std.debug.print("Failed: Divider is incremented every 256 cycles.\n", .{});
            return err;
        };
    }
}

pub fn runTimerTest() !void {
    var timer: TIMER.State = .{};
    var irq_timer: bool = false;

    const CycleTestCase = struct {
        cycles: u16,
        timer_control: TIMER.TimerControl,
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

        timer = .{};
        timer.timer_control = @bitCast(cycleCase.timer_control);
        for(0..cycleCase.cycles) |_| {
            irq_timer = TIMER.cycle(&timer);
        }
        std.testing.expectEqual(0x01, timer.timer) catch |err| {
            std.debug.print("Failed: Timer increments every {d} cycles.\n", .{ cycleCase.cycles });
            return err;
        };
    }

    // overflow
    timer = .{};
    timer.timer = 0xFF;
    timer.timer_mod = 0x05;
    timer.timer_control = .{ .enable = true, .clock = 3 };
    for(0..256) |_| {
        irq_timer = TIMER.cycle(&timer);
    }
    // TIMA value is applied 4 cycles later.
    std.testing.expectEqual(0x00, timer.timer) catch |err| {
        std.debug.print("Failed: Timer mod is not applied immediately.\n", .{});
        return err;
    };
    std.testing.expectEqual(false, irq_timer) catch |err| {
        std.debug.print("Failed: Timer interrupt is not triggered immediately.\n", .{});
        return err;
    };
    for(0..4) |_| {
        irq_timer = TIMER.cycle(&timer);
    }
    std.testing.expectEqual(0x05, timer.timer) catch |err| {
        std.debug.print("Failed: Timer mod is applied after 4 cycles.\n", .{});
        return err;
    };
    std.testing.expectEqual(true, irq_timer) catch |err| {
        std.debug.print("Failed: Timer interrupt is applied after 4 cycles.\n", .{});
        return err;
    };

    // disable can increment timer.
    timer = .{};
    timer.timer = 0x05;
    timer.system_counter = 0xFFFD;
    timer.timer_control = .{ .enable = true, .clock = 3 };
    irq_timer = TIMER.cycle(&timer);
    timer.timer_control = .{ .enable = false, .clock = 3 };
    irq_timer = TIMER.cycle(&timer);
    std.testing.expectEqual(0x06, timer.timer) catch |err| {
        std.debug.print("Failed: Disabling timer can increment it.\n", .{});
        return err;
    };

    // overflow: cpu writes abort timer_mod
    timer = .{};
    timer.timer = 0xFF;
    timer.timer_mod = 0x05;
    timer.timer_control = .{ .enable = true, .clock = 3 };
    for(0..256) |_| {
        irq_timer = TIMER.cycle(&timer);
    }
    var request: def.Request = .{ .address = mem_map.timer, .value = .{ .write = 0x10 } };
    TIMER.request(&timer, &request);
    for(0..4) |_| {
        irq_timer = TIMER.cycle(&timer);
    }
    std.testing.expectEqual(0x10, timer.timer) catch |err| {
        std.debug.print("Failed: Writing to timer aborts modulo.\n", .{});
        return err;
    };
    std.testing.expectEqual(false, irq_timer) catch |err| {
        std.debug.print("Failed: Writing to timer aborts interrupt.\n", .{});
        return err;
    };

    // overflow: cpu write TIMA on 4th cycle => write is ignored
    timer = .{};
    timer.timer = 0xFF;
    timer.timer_mod = 0x05;
    timer.timer_control = .{ .enable = true, .clock = 3 };
    for(0..(256 + 3)) |_| {
        irq_timer = TIMER.cycle(&timer);
    }
    request = .{ .address = mem_map.timer, .value = .{ .write = 0x33 } };
    TIMER.request(&timer, &request);
    irq_timer = TIMER.cycle(&timer);
    std.testing.expectEqual(0x05, timer.timer) catch |err| {
        std.debug.print("Failed: Writing to tima on 4th cycle leads to the write being ignored.\n", .{});
        return err;
    };

    // overflow: cpu write TMA on 4th cycle => new TMA value is used.
    timer = .{};
    timer.timer = 0xFF;
    timer.timer_mod = 0x05;
    timer.timer_control = .{ .enable = true, .clock = 3 };
    for(0..(256 + 3)) |_| {
        irq_timer = TIMER.cycle(&timer);
    }
    request = .{ .address = mem_map.timer_mod, .value = .{ .write = 0x22 } };
    TIMER.request(&timer, &request);
    irq_timer = TIMER.cycle(&timer);
    std.testing.expectEqual(0x22, timer.timer) catch |err| {
        std.debug.print("Failed: Writing to timer mod on 4th cycle leads to the new value used for the modulo.\n", .{});
        return err;
    };
}
