const std = @import("std");

const APU = @import("apu.zig");
const BOOT = @import("boot.zig");
const CLI = @import("cli.zig");
const CPU = @import("cpu.zig");
const def = @import("defines.zig");
const DMA = @import("dma.zig");
const INPUT = @import("input.zig");
const mem_map = @import("mem_map.zig");
const MMU = @import("mmu.zig");
const PPU = @import("ppu.zig");
const Platform = @import("platform.zig");
const TIMER = @import("timer.zig");

const state = struct {
    var allocator: std.heap.GeneralPurposeAllocator(.{}) = undefined;
    var apu: APU.State = .{};
    var boot: BOOT.State = .{};
    var cli: CLI.State = .{};
    var cpu: CPU.State = .{};
    var dma: DMA.State = .{};
    var input: INPUT.State = .{};
    var mmu: MMU.State = .{};
    var platform: Platform.State = .{};
    var ppu: PPU.State = .{};
    var timer: TIMER.State = .{};
};

export fn init() void {
    state.allocator = std.heap.GeneralPurposeAllocator(.{}){};
    APU.init(&state.apu);
    BOOT.init(&state.boot);
    CLI.init(&state.cli, state.allocator.allocator());
    CPU.init(&state.cpu);
    DMA.init(&state.dma);
    INPUT.init(&state.input);
    MMU.init(&state.mmu);
    PPU.init(&state.ppu);
    Platform.init(&state.platform, imgui_cb);
    TIMER.init(&state.timer);

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
    INPUT.updateInputState(&state.input, &state.mmu, &state.platform.input_state);
    // Note: GB runs at 59.73Hz. This software runs at 60Hz.
    // TODO: It would be better to just let the system run to the end of the next vblank.
    const cycles_per_frame = 70224; 
    for(0..cycles_per_frame) |_| {
        // TODO: Maybe the CPU should return it's pins, so that it is very clear that we communicate between cpu and other system. 
        // This would strengthen decoupling and other systems don't "need" to know the mmu for this then.
        CPU.cycle(&state.cpu, &state.mmu);
        BOOT.cycle(&state.boot, &state.mmu);
        DMA.cycle(&state.dma, &state.mmu);
        INPUT.cycle(&state.input, &state.mmu);
        TIMER.cycle(&state.timer, &state.mmu);
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
