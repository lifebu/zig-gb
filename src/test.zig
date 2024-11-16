const std = @import("std");

const blargg = @import("test/blargg_parser.zig");
const cpu_test = @import("test/cpu_test.zig");
const ppu_test = @import("test/ppu_test.zig");

test "CPU_SingleStepTest" {
    try cpu_test.runSingleStepTests();
}

test "PPU_StaticTest" {
    try ppu_test.runStaticTest();
}
