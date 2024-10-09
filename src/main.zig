const std = @import("std");
// TODO: This is strange!
const _cpu = @import("cpu.zig");

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = allocator.allocator();
    defer _ = allocator.deinit();

    var cpu = try _cpu.CPU.init(alloc);
    defer cpu.deinit();

    try cpu.frame();
}
