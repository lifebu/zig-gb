const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const MMU = @import("../mmu.zig");
const def = @import("../defines.zig");
const INPUT = @import("../input.zig");
const mem_map = @import("../mem_map.zig");

pub fn runInputTests() !void {
    var input: INPUT.State = .{};
    var mmu: MMU.State = .{}; 

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
        var request_data: u8 = testCase.write;
        mmu.request.write = mem_map.joypad;
        mmu.request.data = &request_data;
        INPUT.updateInputState(&input, &mmu, &testCase.input);
        INPUT.cycle(&input, &mmu);
        std.testing.expectEqual(testCase.expected, mmu.memory[mem_map.joypad]) catch |err| {
            std.debug.print("Failed {d}: {s}\n", .{ i, testCase.name });
            return err;
        };
    }

    // Lower nibble is read-only to cpu.
    mmu.memory[mem_map.joypad] = 0b1111_1111;
    var request_data: u8 = 0b1111_0000;
    mmu.request.write = mem_map.joypad;
    mmu.request.data = &request_data;
    INPUT.cycle(&input, &mmu);
    std.testing.expectEqual(0b1111_1111, mmu.memory[mem_map.joypad]) catch |err| {
        std.debug.print("Failed {d}: {s}\n", .{ testCases.len, "Lower nibble is ready-only to cpu" });
        return err;
    };

    // Interrupt
    mmu.memory[mem_map.interrupt_flag] = 0b0000_0000;
    mmu.memory[mem_map.joypad] = 0b1111_1111;
    INPUT.cycle(&input, &mmu);
    mmu.memory[mem_map.joypad] = 0b0000_0000;
    INPUT.cycle(&input, &mmu);
    std.testing.expectEqual(false, mmu.memory[mem_map.interrupt_flag] & mem_map.interrupt_joypad == mem_map.interrupt_joypad) catch |err| {
        std.debug.print("Failed: Joypad interrupt is not triggered.\n", .{});
        return err;
    };
}
