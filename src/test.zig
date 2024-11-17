const std = @import("std");

const blargg = @import("test/blargg_parser.zig");
const cpu_test = @import("test/cpu_test.zig");
const ppu_test = @import("test/ppu_test.zig");
const mmio_test = @import("test/mmio_test.zig");

// TODO: How to setup tests correctly that you can run all the tests and specific tests easily?
test "CPU_SingleStepTest" {
    try cpu_test.runSingleStepTests();
}

test "PPU_StaticTest" {
    try ppu_test.runStaticTest();
}

test "MMIO_DividerTest" {
    try mmio_test.runDividerTest();
}

test "MMIO_TimerTest" {
    try mmio_test.runTimerTest();
}

test "MMIO_DMATest" {
    try mmio_test.runDMATest();
}
