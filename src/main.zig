const std = @import("std");

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

    var platform = try PlatformSFML.init(alloc);
    defer platform.deinit();

    var cpu = try CPU.init();
    defer cpu.deinit();

    var mmio = MMIO{};

    var mmu = try MMU.init(alloc, &mmio, "playground/tetris.gb");
    defer mmu.deinit();

    var ppu = PPU{};

    while(platform.update()) {
        var cycles: u32 = 0;
        while(cycles < Def.CYCLES_PER_FRAME) {
            try cpu.step(&mmu); 
            cycles += cpu.cycles_ahead;

            for(cpu.cycles_ahead) |_| {
                mmio.updateTimers(&mmu);
                mmio.updateDMA(&mmu);
                ppu.updateState(&mmu);
            }
            mmio.updateJoypad(&mmu, platform.getInputState());
        }

        try ppu.updatePixels(&mmu, platform.getRawPixels());
        try platform.render();
    }
}

