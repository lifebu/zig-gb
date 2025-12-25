const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const MMU = @import("../mmu.zig");
const def = @import("../defines.zig");
const TIMER = @import("../timer.zig");
const mem_map = @import("../mem_map.zig");

pub fn runDividerTests() !void {
    var timer: TIMER.State = .{};
    var mmu: MMU.State = .{}; 

    var request_data: u8 = 255;
    var request: def.Bus = .{ .data = &request_data, .write = mem_map.divider };
    TIMER.request(&timer, &mmu, &request);
    TIMER.cycle(&timer, &mmu);
    std.testing.expectEqual(0, mmu.memory[mem_map.divider]) catch |err| {
        std.debug.print("Failed: Divider is reset by writing to DIV.\n", .{});
        return err;
    };

    var expected_div: u8 = 0;
    const div_freq = 256;
    for(0..300) |_| {
        for(0..div_freq) |_| {
            TIMER.cycle(&timer, &mmu);
        }
        expected_div +%= 1;
        std.testing.expectEqual(expected_div, mmu.memory[mem_map.divider]) catch |err| {
            std.debug.print("Failed: Divider is incremented every 256 cycles.\n", .{});
            return err;
        };
    }
}

pub fn runTimerTest() !void {
    var timer: TIMER.State = .{};
    var mmu: MMU.State = .{}; 

    mmu.memory[mem_map.timer_mod] = 0x05;

    const CycleTestCase = struct {
        cycles: u16,
        timer_control: u8,
    };
    const cycleCases = [_]CycleTestCase {
        .{ .cycles = 1024, .timer_control = 0b0000_0100 }, 
        .{ .cycles = 16,   .timer_control = 0b0000_0101 }, 
        .{ .cycles = 64,   .timer_control = 0b0000_0110 }, 
        .{ .cycles = 256,  .timer_control = 0b0000_0111 },
    };
    for(cycleCases, 0..) |cycleCase, i| {
        if(i == 0) { // Change value to attach debugger.
            var val: u32 = 0; val += 1;
        }

        timer.system_counter = 0;
        mmu.memory[mem_map.timer] = 0x00;
        mmu.memory[mem_map.timer_control] = cycleCase.timer_control;
        for(0..cycleCase.cycles) |_| {
            TIMER.cycle(&timer, &mmu);
        }
        std.testing.expectEqual(0x01, mmu.memory[mem_map.timer]) catch |err| {
            std.debug.print("Failed: Timer increments every {d} cycles.\n", .{ cycleCase.cycles });
            return err;
        };
    }

    // overflow
    timer.system_counter = 0;
    mmu.memory[mem_map.timer_mod] = 0x05;
    mmu.memory[mem_map.timer] = 0xFF;
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    for(0..256) |_| {
        TIMER.cycle(&timer, &mmu);
    }
    // TIMA value is applied 4 cycles later.
    std.testing.expectEqual(0x00, mmu.memory[mem_map.timer]) catch |err| {
        std.debug.print("Failed: Timer mod is not applied immediately.\n", .{});
        return err;
    };
    std.testing.expectEqual(false, mmu.memory[mem_map.interrupt_flag] & mem_map.interrupt_timer == mem_map.interrupt_timer) catch |err| {
        std.debug.print("Failed: Timer interrupt is not triggered immediately.\n", .{});
        return err;
    };
    for(0..4) |_| {
        TIMER.cycle(&timer, &mmu);
    }
    std.testing.expectEqual(0x05, mmu.memory[mem_map.timer]) catch |err| {
        std.debug.print("Failed: Timer mod is applied after 4 cycles.\n", .{});
        return err;
    };
    std.testing.expectEqual(true, mmu.memory[mem_map.interrupt_flag] & mem_map.interrupt_timer == mem_map.interrupt_timer) catch |err| {
        std.debug.print("Failed: Timer interrupt is applied after 4 cycles.\n", .{});
        return err;
    };

    // disable can increment timer.
    timer.system_counter = 0xFFFD;
    mmu.memory[mem_map.timer] = 0x05;
    TIMER.cycle(&timer, &mmu);
    // TODO: This should come from the cpu?
    mmu.memory[mem_map.timer_control] = 0b0000_0011;
    TIMER.cycle(&timer, &mmu);
    std.testing.expectEqual(0x06, mmu.memory[mem_map.timer]) catch |err| {
        std.debug.print("Failed: Disabling timer can increment it.\n", .{});
        return err;
    };

    // overflow: cpu writes abort timer_mod
    timer.system_counter = 0;
    mmu.memory[mem_map.timer_mod] = 0x05;
    mmu.memory[mem_map.timer] = 0xFF;
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    for(0..256) |_| {
        TIMER.cycle(&timer, &mmu);
    }
    // TODO: This should come from the cpu?
    mmu.memory[mem_map.timer] = 0x10;
    for(0..4) |_| {
        TIMER.cycle(&timer, &mmu);
    }
    std.testing.expectEqual(0x10, mmu.memory[mem_map.timer]) catch |err| {
        std.debug.print("Failed: Writing to timer aborts modulo.\n", .{});
        return err;
    };
    std.testing.expectEqual(false, mmu.memory[mem_map.interrupt_flag] & mem_map.interrupt_timer == mem_map.interrupt_timer) catch |err| {
        std.debug.print("Failed: Writing to timer aborts interrupt.\n", .{});
        return err;
    };

    // overflow: cpu write TIMA on 4th cycle => write is ignored
    timer.system_counter = 0;
    mmu.memory[mem_map.timer_mod] = 0x05;
    mmu.memory[mem_map.timer] = 0xFF;
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    for(0..(256 + 3)) |_| {
        TIMER.cycle(&timer, &mmu);
    }
    // TODO: This should come from the cpu?
    mmu.memory[mem_map.timer] = 0x33;
    TIMER.cycle(&timer, &mmu);
    std.testing.expectEqual(0x05, mmu.memory[mem_map.timer]) catch |err| {
        std.debug.print("Failed: Writing to tima on 4th cycle leads to the write being ignored.\n", .{});
        return err;
    };

    // overflow: cpu write TMA on 4th cycle => new TMA value is used.
    timer.system_counter = 0;
    mmu.memory[mem_map.timer_mod] = 0x05;
    mmu.memory[mem_map.timer] = 0xFF;
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    for(0..(256 + 3)) |_| {
        TIMER.cycle(&timer, &mmu);
    }
    // TODO: This should come from the cpu?
    mmu.memory[mem_map.timer_mod] = 0x22;
    TIMER.cycle(&timer, &mmu);
    std.testing.expectEqual(0x22, mmu.memory[mem_map.timer]) catch |err| {
        std.debug.print("Failed: Writing to timer mod on 4th cycle leads to the new value used for the modulo.\n", .{});
        return err;
    };
}
