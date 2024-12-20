const std = @import("std");

const APU = @import("apu.zig");
const CART = @import("cart.zig");
const CONF = @import("conf.zig");
const CPU = @import("cpu.zig");
const Def = @import("def.zig");
const MMIO = @import("mmio.zig");
const MMU = @import("mmu.zig");
const MemMap = @import("mem_map.zig");
const PPU = @import("ppu.zig");
const PlatformSFML = @import("platform_sfml.zig");

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = allocator.allocator();
    defer _ = allocator.deinit();

    var conf = try CONF.init(alloc);
    defer conf.deinit() catch unreachable;

    var platform = try PlatformSFML.init(alloc, &conf);
    defer platform.deinit();

    var apu = APU{};

    var cpu = try CPU.init();
    defer cpu.deinit();

    var mmio = MMIO{};

    var mmu = try MMU.init(alloc);
    defer mmu.deinit();

    var cart = try CART.init(alloc, &mmu, conf.gbFile);
    defer cart.deinit();

    var ppu = PPU{};

    while(try platform.update()) {
        mmio.updateInputState(&mmu, platform.getInputState());

        var cyclesPerFrame: u32 = @intFromFloat(platform.targetDeltaMS * Def.CYCLES_PER_MS); 
        // TODO: Dynamic cycles per frame do not work. The window wants to show ~60FPS but the gameboy has ~59.7FPS. This discrepency lead to uggly lines crossing the screen.
        cyclesPerFrame = 70224;

        var cycles: u32 = 0;
        while(cycles < cyclesPerFrame) : (cycles += cpu.cycles_ahead) {
            try cpu.step(&mmu); 

            apu.onWrite(&mmu);
            cart.onWrite(&mmu);
            mmio.onWrite(&mmu);
            ppu.onWrite(&mmu);

            for(cpu.cycles_ahead) |_| {
                mmio.updateTimers(&mmu);
                mmio.updateDMA(&mmu);
                ppu.step(&mmu, platform.getRawPixels());
                apu.step(&mmu, platform.getSamples());
            }
        }

        try platform.render();
    }
}

