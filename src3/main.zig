const std = @import("std");

const def = @import("defines.zig");
const CPU = @import("cpu.zig");
const CLI = @import("cli.zig");
const Platform = @import("platform.zig");
const APU = @import("apu.zig");
const MMU = @import("mmu.zig");
const mem_map = @import("mem_map.zig");
const PPU = @import("ppu.zig");

const state = struct {
    var allocator: std.heap.GeneralPurposeAllocator(.{}) = undefined;
    var cli: CLI.State = .{};
    var cpu: CPU.State = .{};
    var platform: Platform.State = .{};
    var apu: APU.State = .{};
    var mmu: MMU.State = .{};
    var ppu: PPU.State = .{};
};

export fn init() void {
    state.allocator = std.heap.GeneralPurposeAllocator(.{}){};
    CLI.init(&state.cli, state.allocator.allocator());
    Platform.init(&state.platform, imgui_cb);
    APU.init(&state.apu);
    CPU.init(&state.cpu);
    MMU.init(&state.mmu);
    PPU.init(&state.ppu);

    // TODO: Better way to do this? Not in main function!
    if(state.cli.dumpFile) |dumpFile| {
        MMU.loadDump(&state.mmu, dumpFile);
    }
}

fn imgui_cb(dump_path: []u8) void {
    MMU.loadDump(&state.mmu, dump_path);
}

export fn frame() void {
    // Note: GB runs at 59.73Hz. This software runs at 60Hz.
    // TODO: It would be better to just let the system run to the end of the next vblank.
    const cycles_per_frame = 70224; 
    for(0..cycles_per_frame) |_| {
        CPU.cycle(&state.cpu, &state.mmu.memory);
        MMU.cycle(&state.mmu);
        APU.cycle(&state.apu, state.mmu.memory);
        PPU.cycle(&state.ppu, &state.mmu.memory);
    }

    Platform.frame(&state.platform, state.ppu.colorIds, state.apu.gb_sample_buffer);
}

export fn deinit() void {
    CLI.deinit(&state.cli, state.allocator.allocator());
    Platform.deinit();
    _ = state.allocator.deinit();
}

pub fn main() void {
    Platform.run(init, frame, deinit, &state.platform);
}
