const std = @import("std");

const APU = @import("../apu.zig");
const Def = @import("../def.zig");
const MMIO = @import("../mmio.zig");
const MMU = @import("../mmu.zig");
const MemMap = @import("../mem_map.zig");

pub fn runWriteTests() !void {
    const alloc = std.testing.allocator;

    var apu = APU{};
    var mmio = MMIO{};
    var mmu = try MMU.init(alloc, &apu, &mmio, null);
    defer mmu.deinit();

    // TODO: Missing Tests:
    // ROM: Cannot write
    // Echo-RAM: E000-FDFF <=> C000-DDFF
    // PPU-Mode: (writes are ignored, reads return garbage 0xFF).
        // Accessible
        // Mode 2 (OAM Scan): VRAM, CGB palettes 
        // Mode 3 (Draw): None
        // Mode 0 (HBlank): VRAM, OAM, CGB palettes 
        // Mode 1 (VBlank): VRAM, OAM, CGB palettes 
    // Unused (FEA0-FEFF)
        // Cannot write.
    // Hardware Registers:
        // FF44: LY
        // FF41: STAT (LYC==LY and PPUMode are readOnly) 
}

pub fn runReadTests() !void {
    const alloc = std.testing.allocator;

    var apu = APU{};
    var mmio = MMIO{};
    var mmu = try MMU.init(alloc, &apu, &mmio, null);
    defer mmu.deinit();

    // TODO: Missing Tests:
    // Echo-RAM: E000-FDFF <=> C000-DDFF
    // PPU-Mode: (writes are ignored, reads return garbage 0xFF).
        // Accessible
        // Mode 2 (OAM Scan): VRAM, CGB palettes 
        // Mode 3 (Draw): None
        // Mode 0 (HBlank): VRAM, OAM, CGB palettes 
        // Mode 1 (VBlank): VRAM, OAM, CGB palettes 
    // Unused (FEA0-FEFF)
        // 0xFF when OAM is blocked.
        // 0x00 Otherwise.
}
