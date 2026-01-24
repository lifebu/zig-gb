const std = @import("std");
const test_options = @import("test_options");
const filter = test_options.test_filter;

const apu_sampling_test = @import("tests/apu_sampling.test.zig");
const apu_test = @import("tests/apu.test.zig");
const cart_test = @import("tests/cart.test.zig");
const halt_test = @import("tests/halt.test.zig");
const interrupt_test = @import("tests/interrupt.test.zig");
const memory_test = @import("tests/memory.test.zig");
const mmio_test = @import("tests/mmio.test.zig");
const ppu_test = @import("tests/ppu.test.zig");
const singlestep_test = @import("tests/singlestep.test.zig");
const test_roms = @import("tests/test_roms.test.zig");


test "All_TestRomTest" {
    try test_roms.runTestRomsTests(filter);
}

// test "APU_Channel" {
//     if (filter != .all and filter != .apu) {
//         return error.SkipZigTest;
//     }
//     try apu_test.runApuChannelTests();
// }
//
// test "APU_Output" {
//     if (filter != .all and filter != .apu) {
//         return error.SkipZigTest;
//     }
//     const pre_calc: bool = false;
//     try apu_sampling_test.runApuOutputTest(pre_calc);
// }
//
// test "APU_Sampler" {
//     if (filter != .all and filter != .apu) {
//         return error.SkipZigTest;
//     }
//     try apu_sampling_test.runApuSamplingTests();
// }

test "Cart" {
    if (filter != .all and filter != .cart) {
        return error.SkipZigTest;
    }
    try cart_test.runCartTests();
}

test "CPU_Halt" {
    if (filter != .all and filter != .cpu) {
        return error.SkipZigTest;
    }
    try halt_test.runHaltTests();
}

test "CPU_InterruptTest" {
    if (filter != .all and filter != .cpu) {
        return error.SkipZigTest;
    }
    try interrupt_test.runInterruptTests();
}

// test "CPU_SingleStepTest" {
//     if (filter != .all and filter != .cpu) {
//         return error.SkipZigTest;
//     }
//     try singlestep_test.runSingleStepTests();
// }

test "MMIO_DividerTest" {
    if (filter != .all and filter != .mmio) {
        return error.SkipZigTest;
    }
    try mmio_test.runDividerTests();
}

test "MMIO_InputTest" {
    if (filter != .all and filter != .mmio) {
        return error.SkipZigTest;
    }
    try mmio_test.runInputTests();
}

test "MMIO_TimerTest" {
    if (filter != .all and filter != .mmio) {
        return error.SkipZigTest;
    }
    try mmio_test.runTimerTest();
}

test "Memory_DMA" {
    if (filter != .all and filter != .memory) {
        return error.SkipZigTest;
    }
    try memory_test.runDMATest();
}

test "Memory_Request" {
    if (filter != .all and filter != .memory) {
        return error.SkipZigTest;
    }
    try memory_test.runRequestTest();
}

// test "PPU_InterruptTest" {
//     if (filter != .all and filter != .ppu) {
//         return error.SkipZigTest;
//     }
//     try ppu_test.runInterruptTests();
// }
