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

    var mmu = try MMU.init(alloc, "test_data/blargg_roms/cpu_instrs/individual/06-ld r,r.gb");
    defer mmu.deinit();

    var ppu = PPU{};
    var mmio = MMIO{};

    while(platform.update()) {
        var cycles: u32 = 0;
        while(cycles < Def.CYCLES_PER_FRAME) {
            try cpu.step(&mmu); 
            cycles += cpu.cycles_ahead;

            for(cpu.cycles_ahead) |_| {
                mmio.updateTimers(&mmu);
            }
            mmio.updateJoypad(&mmu, platform.getInputState());
        }

        try ppu.updatePixels(&mmu, platform.getRawPixels());
        try platform.render();
    }
}

