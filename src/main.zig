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

    var cpu = try CPU.init(alloc, "test_data/blargg_roms/cpu_instrs/individual/06-ld r,r.gb");
    defer cpu.deinit();

    var mmu = try MMU.init(alloc, "test_data/blargg_roms/cpu_instrs/individual/06-ld r,r.gb");
    defer mmu.deinit();

    var ppu = PPU{};
    var mmio = MMIO{};

    while(platform.update()) {
        try ppu.updatePixels(&mmu, platform.getRawPixels());
        try cpu.frame(&mmu);


        const rawMemory: *[]u8 = mmu.getRaw();
        // TODO: This does not work because we need to update those once per cycle. but the cpu only works on frames. 
        // And the cpu.cycle cannot be used as it is incremented by more then once per cpu tick.
        mmio.updateJoypad(&rawMemory.*[MemMap.JOYPAD], platform.getInputState());
        // TODO: Maybe pass them as a packed struct?
        mmio.updateTimers(&rawMemory.*[MemMap.DIVIDER], &rawMemory.*[MemMap.TIMER], rawMemory.*[MemMap.TIMER_MOD], rawMemory.*[MemMap.TIMER_CONTROL]);
        
        try platform.render();
    }
}

