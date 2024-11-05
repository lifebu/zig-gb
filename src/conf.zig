
const std = @import("std");

const Self = @This();

gbFile: []const u8,
bgbMode: bool = false,
bgbProc: ?std.process.Child = null,

pub fn init(alloc: std.mem.Allocator) !Self {

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    _ = args.next(); // The file itself, we don't need that
    const file: ?[]const u8 = if(args.next()) |val| val else null;    
    if(file == null) {
        std.log.err("Required to pass a path to a gb file as first parameter.\n", .{});
        unreachable;
    }
    var self = Self{ .gbFile = file.? };

    self.bgbMode = if(args.next()) |val| std.mem.eql(u8, val, "bgbMode") else false;
    if(self.bgbMode) {
        try self.runBGB(alloc);
    }

    return self;
}

pub fn deinit(self: *Self) !void {
    if(self.bgbProc != null) {
        // TODO: Does not work bgb be evil.
        _ = try self.bgbProc.?.kill();
    }
}

fn runBGB(self: *Self, alloc: std.mem.Allocator) !void {
    const argv = [_][]const u8{ "bgb", self.gbFile }; 
    self.bgbProc = std.process.Child.init(&argv, alloc);
    try self.bgbProc.?.spawn();
    // Some delay so that we and bgb "sync up".
    std.time.sleep(500_000_000);
} 
