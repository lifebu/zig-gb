const std = @import("std");

const APU = @import("apu.zig");
const BUS = @import("bus.zig");
const BOOT = @import("boot.zig");
const CART = @import("cart.zig");
const CLI = @import("cli.zig");
const CPU = @import("cpu.zig");
const def = @import("defines.zig");
const DMA = @import("dma.zig");
const INPUT = @import("input.zig");
const mem_map = @import("mem_map.zig");
const MMU = @import("mmu.zig");
const PPU = @import("ppu.zig");
const RAM = @import("ram.zig");
const Platform = @import("platform.zig");
const TIMER = @import("timer.zig");

const state = struct {
    var allocator: std.heap.GeneralPurposeAllocator(.{}) = undefined;
    var apu: APU.State = .{};
    var bus: BUS.State = .{};
    var boot: BOOT.State = .{};
    var cart: CART.State = .{};
    var cli: CLI.State = .{};
    var cpu: CPU.State = .{};
    var dma: DMA.State = .{};
    var input: INPUT.State = .{};
    var mmu: MMU.State = .{};
    var platform: Platform.State = .{};
    var ppu: PPU.State = .{};
    var ram: RAM.State = .{};
    var timer: TIMER.State = .{};
};

export fn init() void {
    state.allocator = std.heap.GeneralPurposeAllocator(.{}){};
    APU.init(&state.apu);
    BUS.init(&state.bus);
    BOOT.init(&state.boot);
    CART.init(&state.cart, state.allocator.allocator());
    CLI.init(&state.cli, state.allocator.allocator());
    CPU.init(&state.cpu);
    DMA.init(&state.dma);
    INPUT.init(&state.input);
    MMU.init(&state.mmu);
    PPU.init(&state.ppu);
    Platform.init(&state.platform, imgui_cb);
    RAM.init(&state.ram);
    TIMER.init(&state.timer);

    // TODO: Better way to do this? Not in main function!
    if(state.cli.dumpFile) |dumpFile| {
        imgui_cb(dumpFile);
    }
}

fn imgui_cb(dump_path: []const u8) void {
    const file_type: def.FileType = MMU.getFileType(dump_path);
    MMU.loadDump(&state.mmu, dump_path, file_type);
    CPU.loadDump(&state.cpu, file_type);
    CART.loadDump(&state.cart, dump_path, file_type, &state.mmu);
}

export fn frame() void {
    INPUT.updateInputState(&state.input, &state.mmu, &state.platform.input_state);
    // Note: GB runs at 59.73Hz. This software runs at 60Hz.
    // TODO: It would be better to just let the system run to the end of the next vblank. How to do that when the PPU is disabled?
    const cycles_per_frame = 70224; 
    for(0..cycles_per_frame) |_| {
        // TODO: Consider creating a list of active systems that are ticked every cycle by calling their memory and cycle functions.
        // Deactivating a system means moving it to the inactive set.
        var request: def.MemoryRequest = CPU.cycle(&state.cpu, &state.mmu);
        BOOT.memory(&state.boot, &request);
        BUS.request(&state.bus);
        CART.memory(&state.cart, &state.mmu, &request);
        DMA.memory(&state.dma, &state.mmu, &request);
        INPUT.memory(&state.input, &request);
        TIMER.memory(&state.timer, &state.mmu, &request);
        PPU.memory(&state.ppu, &request);
        APU.memory(&state.apu, &request);
        MMU.memory(&state.mmu, &request);
        RAM.request(&state.ram, &state.bus);

        BOOT.cycle(&state.boot);
        BUS.cycle(&state.bus);
        CART.cycle(&state.cart);
        DMA.cycle(&state.dma, &state.mmu);
        INPUT.cycle(&state.input);
        TIMER.cycle(&state.timer, &state.mmu);
        PPU.cycle(&state.ppu, &state.mmu);
        APU.cycle(&state.apu);
        MMU.cycle(&state.mmu);
        RAM.cycle(&state.ram);
    }

    Platform.frame(&state.platform, state.ppu.colorIds, state.apu.gb_sample_buffer);
}

export fn deinit() void {
    CART.deinit(&state.cart);
    CLI.deinit(&state.cli, state.allocator.allocator());
    Platform.deinit();
    _ = state.allocator.deinit();
}

pub fn main() void {
    Platform.run(init, frame, deinit, &state.platform);
}
