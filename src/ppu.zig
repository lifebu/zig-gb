const std = @import("std");
const build_options = @import("build_options");

const def = @import("defines.zig");
const PpuCycle = @import("ppu_cycle.zig");
const PpuVoid = @import("ppu_void.zig");

pub const Ppu = switch (build_options.ppu_plugin) {
    .runtime => union(enum) {
        const Self = @This();

        ppu_cycle: PpuCycle,
        ppu_void: PpuVoid,

        pub const empty: Self = .{ .ppu_void = .{} };

        pub fn init(self: *Self, plugin: def.PpuPlugin) void {
            self.* = switch(plugin) {
                .void => .{ .ppu_void = .{} },
                .cycle => .{ .ppu_cycle = .{} },
            };
            switch(self.*) {
                .ppu_void => self.ppu_void.init(plugin),
                .ppu_cycle => self.ppu_cycle.init(plugin),
            }
        }
        pub fn cycle(self: *Self) struct{ bool, bool } {
            return switch(self.*) {
                .ppu_void => self.ppu_void.cycle(),
                .ppu_cycle => self.ppu_cycle.cycle(),
            };
        }
        pub fn request(self: *Self, req: *def.Request) void {
            switch(self.*) {
                .ppu_void => self.ppu_void.request(req),
                .ppu_cycle => self.ppu_cycle.request(req),
            }
        }
        pub fn getFrontBuffer(self: *Self) [def.overscan_resolution]u8 {
            return switch(self.*) {
                .ppu_void => self.ppu_void.getFrontBuffer(),
                .ppu_cycle => self.ppu_cycle.getFrontBuffer(),
            };
        }
    }, 
    .cycle => PpuCycle,
    .void => PpuVoid, 
};
