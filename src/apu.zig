const std = @import("std");
const build_options = @import("build_options");

const def = @import("defines.zig");
const ApuCycle = @import("apu_cycle.zig");
const ApuVoid = @import("apu_void.zig");

pub const Apu = switch (build_options.ppu_plugin) {
    .runtime => union(enum) {
        const Self = @This();

        apu_cycle: ApuCycle,
        apu_void: ApuVoid,

        pub const empty: Self = .{ .apu_void = .{} };

        pub fn init(self: *Self, plugin: def.ApuPlugin) void {
            self.* = switch(plugin) {
                .void => .{ .apu_void = .{} },
                .cycle => .{ .apu_cycle = .{} },
            };
            switch(self.*) {
                .apu_void => self.apu_void.init(plugin),
                .apu_cycle => self.apu_cycle.init(plugin),
            }
        }
        pub fn cycle(self: *Self) void {
            switch(self.*) {
                .apu_void => self.apu_void.cycle(),
                .apu_cycle => self.apu_cycle.cycle(),
            }
        }
        pub fn request(self: *Self, req: *def.Request) void {
            switch(self.*) {
                .apu_void => self.apu_void.request(req),
                .apu_cycle => self.apu_cycle.request(req),
            }
        }
        pub fn getSamples(self: *Self) *def.SampleFifo {
            return switch(self.*) {
                .apu_void => self.apu_void.getSamples(),
                .apu_cycle => self.apu_cycle.getSamples(),
            };
        }
    }, 
    .cycle => ApuCycle,
    .void => ApuVoid, 
};
