const std = @import("std");

const def = @import("defines.zig");

pub const State = struct {
    gb_sample_buffer: [def.num_gb_samples]f32 = [1]f32{ 0.0 } ** def.num_gb_samples,
};

pub fn init(_: *State) void {
}

pub fn cycle(_: *State, _: *def.MemoryRequest) void {
}
