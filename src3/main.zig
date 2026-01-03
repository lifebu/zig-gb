const std = @import("std");

const APU = @import("apu.zig");
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
    BOOT.init(&state.boot);
    CART.init(&state.cart);
    CLI.init(&state.cli, state.allocator.allocator());
    CPU.init(&state.cpu, state.allocator.allocator());
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
    CPU.loadDump(&state.cpu, file_type, state.allocator.allocator());
    CART.loadDump(&state.cart, dump_path, file_type, state.allocator.allocator());
}

export fn frame() void {
    var irq_joypad: bool = INPUT.updateInputState(&state.input, &state.platform.input_state);
    // Note: GB runs at 59.73Hz. This software runs at 60Hz.
    // TODO: It would be better to just let the system run to the end of the next vblank. How to do that when the PPU is disabled?
    const cycles_per_frame = 70224; 
    for(0..cycles_per_frame) |_| {
        // TODO: Consider creating a list of active systems that are ticked every cycle by calling their memory and cycle functions.
        // Deactivating a system means moving it to the inactive set.
        var request: def.Request = .{};
        CPU.cycle(&state.cpu, &request);
        CPU.request(&state.cpu, &request);
        DMA.cycle(&state.dma, &request);
        
        BOOT.request(&state.boot, &request);
        CART.request(&state.cart, &request);
        DMA.request(&state.dma, &request);
        INPUT.request(&state.input, &request);
        TIMER.request(&state.timer, &request);
        PPU.request(&state.ppu, &state.mmu, &request);
        APU.request(&state.apu, &request);
        RAM.request(&state.ram, &request);
        MMU.request(&state.mmu, &request);

        BOOT.cycle(&state.boot);
        CART.cycle(&state.cart);
        INPUT.cycle(&state.input);
        const irq_timer = TIMER.cycle(&state.timer);
        const irq_vblank, const irq_stat = PPU.cycle(&state.ppu, &state.mmu);
        MMU.cycle(&state.mmu);
        RAM.cycle(&state.ram);
        const sample: ?def.Sample = APU.cycle(&state.apu);
        if(sample) |value| {
            Platform.pushSample(&state.platform, value);
        }

        const irq_serial: bool = false;
        CPU.pushInterrupts(&state.cpu, irq_vblank, irq_stat, irq_timer, irq_serial, irq_joypad);
        irq_joypad = false; // TODO: Not the nicest, okay for now.
        // TODO: I should create an error message, if any request was never answered (i.e. game tried to access invalid memory).
    }

    Platform.frame(&state.platform, state.ppu.colorIds);
}

export fn deinit() void {
    CPU.deinit(&state.cpu, state.allocator.allocator());
    CART.deinit(&state.cart, state.allocator.allocator());
    CLI.deinit(&state.cli, state.allocator.allocator());
    Platform.deinit();
    _ = state.allocator.deinit();
}

pub fn main() void {
    Platform.run(init, frame, deinit, &state.platform);
}
