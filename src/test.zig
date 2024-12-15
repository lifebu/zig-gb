const std = @import("std");

const blargg = @import("test/blargg_parser.zig");
const cpu_test = @import("test/cpu_test.zig");
const ppu_test = @import("test/ppu_test.zig");
const mmio_test = @import("test/mmio_test.zig");
const mmu_test = @import("test/mmu_test.zig");
const interrupt_test = @import("test/interrupt_test.zig");

// TODO: How to setup tests correctly that you can run all the tests and specific tests easily?
// TODO: Maybe split up the tests?
test "CPU_SingleStepTest" {
    try cpu_test.runSingleStepTests();
}

test "CPU_HaltTest" {
    try cpu_test.runHaltTests();
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

test "MMIO_JoypadTest" {
    try mmio_test.runJoypadTests();
}

test "InterruptTest" {
    try interrupt_test.runInterruptTests();
}

test "MMU_WriteMemoryTest" {
    try mmu_test.runWriteMemoryTests();
}

test "MMU_WriteIOTest" {
    try mmu_test.runWriteIOTests();
}

test "MMU_ReadMemoryTest" {
    try mmu_test.runReadMemoryTests();
}
