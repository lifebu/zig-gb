const std = @import("std");
const test_options = @import("test_options");
const category = test_options.test_category;

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
    try test_roms.runTestRomsTests(category);
}

// test "APU_Channel" {
//     if (category != .all and category != .apu) {
//         return error.SkipZigTest;
//     }
//     try apu_test.runApuChannelTests();
// }
//
// test "APU_Output" {
//     if (category != .all and category != .apu) {
//         return error.SkipZigTest;
//     }
//     const pre_calc: bool = false;
//     try apu_sampling_test.runApuOutputTests(pre_calc);
// }
//
// test "APU_Sampler" {
//     if (category != .all and category != .apu) {
//         return error.SkipZigTest;
//     }
//     try apu_sampling_test.runApuSamplingTests();
// }

test "Cart" {
    if (category != .all and category != .cart) {
        return error.SkipZigTest;
    }
    try cart_test.runCartTests();
}

test "CPU_Halt" {
    if (category != .all and category != .cpu) {
        return error.SkipZigTest;
    }
    try halt_test.runHaltTests();
}

test "CPU_InterruptTest" {
    if (category != .all and category != .cpu) {
        return error.SkipZigTest;
    }
    try interrupt_test.runInterruptTests();
}

// test "CPU_SingleStepTest" {
//     if (category != .all and category != .cpu) {
//         return error.SkipZigTest;
//     }
//     try singlestep_test.runSingleStepTests();
// }

test "MMIO_DividerTest" {
    if (category != .all and category != .mmio) {
        return error.SkipZigTest;
    }
    try mmio_test.runDividerTests();
}

test "MMIO_InputTest" {
    if (category != .all and category != .mmio) {
        return error.SkipZigTest;
    }
    try mmio_test.runInputTests();
}

test "MMIO_TimerTest" {
    if (category != .all and category != .mmio) {
        return error.SkipZigTest;
    }
    try mmio_test.runTimerTests();
}

test "Memory_DMA" {
    if (category != .all and category != .memory) {
        return error.SkipZigTest;
    }
    try memory_test.runDMATests();
}

test "Memory_Request" {
    if (category != .all and category != .memory) {
        return error.SkipZigTest;
    }
    try memory_test.runRequestTests();
}

// test "PPU_InterruptTest" {
//     if (category != .all and category != .ppu) {
//         return error.SkipZigTest;
//     }
//     try ppu_test.runInterruptTests();
// }
