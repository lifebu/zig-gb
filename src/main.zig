const std = @import("std");
const cpu = @import("cpu.zig");

pub fn main() !void {
    try cpu.main();
}
