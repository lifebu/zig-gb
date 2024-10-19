const std = @import("std");

const blargg = @import("test/blargg_parser.zig");
const cpu_test = @import("test/cpu_test.zig");

test "SingleStepTest" {
    try cpu_test.runSingleStepTests();
}

