const std = @import("std");

const apu_test = @import("tests/apu.test.zig");
const dma_test = @import("tests/dma.test.zig");
const halt_test = @import("tests/halt.test.zig");
const interrupt_test = @import("tests/interrupt.test.zig");
const input_test = @import("tests/input.test.zig");
const ppu_test = @import("tests/ppu.test.zig");
const singlestep_test = @import("tests/singlestep.test.zig");
const timer_test = @import("tests/timer.test.zig");

// TODO: How to setup tests correctly that you can run all the tests and specific tests easily?
// TODO: Move tests into it's own module so that we don't have it loitering in the src folder!
// TODO: Maybe split up the tests?
test "APU_Output" {
    try apu_test.runApuOutputTest();
}

test "APU_Sampler" {
    try apu_test.runApuSamplingTests();
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
    try timer_test.runDividerTests();
}

test "DMA" {
    try dma_test.runDMATest();
}

test "InputTest" {
    try input_test.runInputTests();
}

test "PPU_InterruptTest" {
    try ppu_test.runInterruptTests();
}

test "TimerTest" {
    try timer_test.runTimerTest();
}
