const std = @import("std");

const singlestep_test = @import("tests/singlestep.test.zig");
const halt_test = @import("tests/halt.test.zig");
const interrupt_test = @import("tests/interrupt.test.zig");

// TODO: How to setup tests correctly that you can run all the tests and specific tests easily?
// TODO: Move tests into it's own module so that we don't have it loitering in the src folder!
// TODO: Maybe split up the tests?
test "CPU_SingleStepTest" {
    try singlestep_test.runSingleStepTests();
}

test "CPU_Halt" {
    try halt_test.runHaltTests();
}

test "CPU_InterruptTest" {
    try interrupt_test.runInterruptTests();
}
