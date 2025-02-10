const std = @import("std");

const def = @import("defines.zig");
const Platform = @import("platform.zig");
const APU = @import("apu.zig");
const MMU = @import("mmu.zig");
const PPU = @import("ppu.zig");

const state = struct {
    var platform: Platform.State = .{};
    var apu: APU.State = .{};
    var mmu: MMU.State = .{};
    var ppu: PPU.State = .{};
};

export fn init() void {
    Platform.init(&state.platform);
    APU.init(&state.apu);
    MMU.init(&state.mmu);
    PPU.init(&state.ppu);
}

export fn frame() void {
    // Note: GB actually runs at 59.73Hz
    const cycles_in_60fps = def.system_freq / 60; 
    for(0..cycles_in_60fps) |_| {
        MMU.cycle(&state.mmu);
        APU.cycle(&state.apu, state.mmu.memory);
        PPU.cycle(&state.ppu, &state.mmu.memory);
    }

    Platform.frame(&state.platform, state.ppu.color2bpp, state.apu.gb_sample_buffer);
}

export fn deinit() void {
    Platform.deinit();
}

pub fn main() void {
    Platform.run(init, frame, deinit);
}
