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
        imgui_cb(dumpFile);
    }
}

fn imgui_cb(dump_path: []const u8) void {
    const file_type: MMU.FileType = MMU.getFileType(dump_path);
    MMU.loadDump(&state.mmu, dump_path, file_type);
    CPU.loadDump(&state.cpu, file_type);
}

export fn frame() void {
    // Note: GB runs at 59.73Hz. This software runs at 60Hz.
    // TODO: It would be better to just let the system run to the end of the next vblank.
    const cycles_per_frame = 70224; 
    for(0..cycles_per_frame) |_| {
        // TODO: Maybe the CPU should return it's pins, so that it is very clear that we communicate between cpu and other system. 
        // This would strengthen decoupling and other systems don't "need" to know the mmu for this then.
        CPU.cycle(&state.cpu, &state.mmu);
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
