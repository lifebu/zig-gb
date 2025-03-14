const std = @import("std");

const def = @import("defines.zig");
const CLI = @import("cli.zig");
const Platform = @import("platform.zig");
const APU = @import("apu.zig");
const MMU = @import("mmu.zig");
const mem_map = @import("mem_map.zig");
const PPU = @import("ppu.zig");

const state = struct {
    var allocator: std.heap.GeneralPurposeAllocator(.{}) = undefined;
    var cli: CLI.State = .{};
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
    // Note: GB actually runs at 59.73Hz
    const cycles_in_60fps = def.system_freq / 60; 
    for(0..cycles_in_60fps) |_| {
        MMU.cycle(&state.mmu);
        APU.cycle(&state.apu, state.mmu.memory);
        PPU.cycle(&state.ppu, &state.mmu.memory);
    }
    // TODO: Window x scrolling is broken, can test it with this code:
    // state.mmu.memory[mem_map.window_x] = (state.mmu.memory[mem_map.window_x] + 1) % 167;
    // TODO: Window y scrolling is broken, can test it with this code:
    // state.mmu.memory[mem_map.window_y] = (state.mmu.memory[mem_map.window_y] + 1) % 144;
    // TODO: Background x scrolling is broken, can test it with this code:
    // state.mmu.memory[mem_map.scroll_x] = (state.mmu.memory[mem_map.scroll_x] + 1) % 255;
    // TODO: Background y scrolling is broken, can test it with this code:
    // state.mmu.memory[mem_map.scroll_y] = (state.mmu.memory[mem_map.scroll_y] + 1) % 255;

    Platform.frame(&state.platform, state.ppu.color2bpp, state.apu.gb_sample_buffer);
    // TODO: The ppu currently mixes pixels which will lead to previous frames changing the current frame.
    // This leads to smearing. As a workaround, clear the color buffer each frame!
    state.ppu.color2bpp = [_]u8{ 0 } ** def.num_2bpp;
}

export fn deinit() void {
    CLI.deinit(&state.cli, state.allocator.allocator());
    Platform.deinit();
    _ = state.allocator.deinit();
}

pub fn main() void {
    Platform.run(init, frame, deinit, &state.platform);
}
