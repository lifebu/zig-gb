const std = @import("std");

const apu_sampling_test = @import("tests/apu_sampling.test.zig");
const apu_test = @import("tests/apu.test.zig");
const cart_test = @import("tests/cart.test.zig");
const halt_test = @import("tests/halt.test.zig");
const interrupt_test = @import("tests/interrupt.test.zig");
const memory_test = @import("tests/memory.test.zig");
const mmio_test = @import("tests/mmio.test.zig");
const ppu_test = @import("tests/ppu.test.zig");
const singlestep_test = @import("tests/singlestep.test.zig");

// TODO: How to setup tests correctly that you can run all the tests and specific tests easily?
// TODO: Move tests into it's own module so that we don't have it loitering in the src folder!
// TODO: Maybe split up the tests?
test "APU_Channel" {
    try apu_test.runApuChannelTests();
}

test "APU_Output" {
    const pre_calc: bool = false;
    try apu_sampling_test.runApuOutputTest(pre_calc);
}

test "APU_Sampler" {
    try apu_sampling_test.runApuSamplingTests();
}

test "Cart" {
    try cart_test.runCartTests();
}

test "CPU_Halt" {
    try halt_test.runHaltTests();
}

test "CPU_InterruptTest" {
    try interrupt_test.runInterruptTests();
}

test "CPU_SingleStepTest" {
    try singlestep_test.runSingleStepTests();
}

test "DividerTest" {
    try mmio_test.runDividerTests();
}

test "DMA" {
    try memory_test.runDMATest();
}

test "InputTest" {
    try mmio_test.runInputTests();
}

test "PPU_InterruptTest" {
    try ppu_test.runInterruptTests();
}

test "TimerTest" {
    try mmio_test.runTimerTest();
}
