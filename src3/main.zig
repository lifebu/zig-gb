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
    CART.init(&state.cart, state.allocator.allocator());
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
    CART.loadDump(&state.cart, dump_path, file_type, &state.mmu);
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
        
        BOOT.request(&state.boot, &request);
        CART.request(&state.cart, &state.mmu, &request);
        DMA.request(&state.dma, &state.mmu, &request);
        INPUT.request(&state.input, &request);
        TIMER.request(&state.timer, &request);
        PPU.request(&state.ppu, &request);
        APU.request(&state.apu, &state.mmu, &request);
        CPU.request(&state.cpu, &request);
        MMU.request(&state.mmu, &request);
        RAM.request(&state.ram, &request);

        BOOT.cycle(&state.boot);
        CART.cycle(&state.cart);
        DMA.cycle(&state.dma, &state.mmu);
        INPUT.cycle(&state.input);
        const irq_timer = TIMER.cycle(&state.timer);
        const irq_vblank, const irq_stat = PPU.cycle(&state.ppu, &state.mmu);
        MMU.cycle(&state.mmu);
        RAM.cycle(&state.ram);
        const sample: ?def.Sample = APU.cycle(&state.apu, &state.mmu);
        if(sample) |value| {
            Platform.pushSample(&state.platform, value);
        }

        const irq_serial: bool = false;
        CPU.pushInterrupts(&state.cpu, irq_vblank, irq_stat, irq_timer, irq_serial, irq_joypad);
        irq_joypad = false; // TODO: Not the nicest, okay for now.
    }

    Platform.frame(&state.platform, state.ppu.colorIds);
}

export fn deinit() void {
    CPU.deinit(&state.cpu, state.allocator.allocator());
    CART.deinit(&state.cart);
    CLI.deinit(&state.cli, state.allocator.allocator());
    Platform.deinit();
    _ = state.allocator.deinit();
}

pub fn main() void {
    Platform.run(init, frame, deinit, &state.platform);
}
