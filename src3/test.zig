const std = @import("std");

const cpu_test = @import("tests/cpu.test.zig");
const interrupt_test = @import("tests/interrupt.test.zig");

// TODO: How to setup tests correctly that you can run all the tests and specific tests easily?
// TODO: Move tests into it's own module so that we don't have it loitering in the src folder!
// TODO: Maybe split up the tests?
test "CPU_SingleStepTest" {
    try cpu_test.runSingleStepTests();
}

test "InterruptTest" {
    try interrupt_test.runInterruptTests();
}
