const std = @import("std");

const Def = @import("../def.zig");
const MMIO = @import("../mmio.zig");
const MMU = @import("../mmu.zig");
const MemMap = @import("../mem_map.zig");
const PPU = @import("../ppu.zig");

pub fn runWriteMemoryTests() !void {
    const alloc = std.testing.allocator;

    var mmu = try MMU.init(alloc);
    defer mmu.deinit();
    var mmio = MMIO{};
    var ppu = PPU{};
    var pixels = try alloc.alloc(Def.Color, Def.RESOLUTION_WIDTH * Def.RESOLUTION_HEIGHT);
    defer alloc.free(pixels);

    const lcd_contr = PPU.LCDC{ .lcd_enable = true };
    mmu.write8_sys(MemMap.LCD_CONTROL, @bitCast(lcd_contr));
    mmu.write8_sys(MemMap.LCD_Y, 9);

    // TODO: maybe combine those tests into an array of configs?
    // ROM: Cannot write.
    for(0..MemMap.ROM_HIGH) |i| {
        const iCast: u16 = @intCast(i);
        mmu.write8_sys(MemMap.ROM_LOW + iCast, 0x00);
        mmu.write8_usr(MemMap.ROM_LOW + iCast, 0xFF);
        std.testing.expectEqual(0x00, mmu.read8_sys(MemMap.ROM_LOW + iCast)) catch |err| {
            std.debug.print("Failed: ROM is writable: {d}\n", .{i});
            return err;
        };
    }

    // PPU: Write VRAM during Mode 3 (DRAW):
    ppu.lyCounter = 81;
    ppu.step(&mmu, &pixels);
    for(MemMap.VRAM_LOW..MemMap.VRAM_HIGH) |i| {
        const addr: u16 = @intCast(i);
        mmu.write8_sys(addr, 0x00);
        mmu.write8_usr(addr, 0xFF);
        std.testing.expectEqual(0x00, mmu.read8_sys(addr)) catch |err| {
            std.debug.print("Failed: PPU: Write VRAM during Mode 3 is forbidden, Address: {d}\n", .{i});
            return err;
        };
    }

    // PPU: Write OAM during Mode 2 (OAM_SCAN):
    ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    ppu.step(&mmu, &pixels);
    for(MemMap.OAM_LOW..MemMap.OAM_HIGH) |i| {
        const addr: u16 = @intCast(i);
        mmu.write8_sys(addr, 0x00);
        mmu.write8_usr(addr, 0xFF);
        std.testing.expectEqual(0x00, mmu.read8_sys(addr)) catch |err| {
            std.debug.print("Failed: PPU: Write OAM during Mode 2 is forbidden, Address: {d}\n", .{i});
            return err;
        };
    }

    // PPU: Write OAM during Mode 3 (DRAW):
    ppu.lyCounter = 81;
    ppu.step(&mmu, &pixels);
    for(MemMap.OAM_LOW..MemMap.OAM_HIGH) |i| {
        const addr: u16 = @intCast(i);
        mmu.write8_sys(addr, 0x00);
        mmu.write8_usr(addr, 0xFF);
        std.testing.expectEqual(0x00, mmu.read8_sys(addr)) catch |err| {
            std.debug.print("Failed: PPU: Write OAM during Mode 3 is forbidden, Address: {d}\n", .{i});
            return err;
        };
    }

    // UNUSED: Cannot write.
    for(MemMap.UNUSED_LOW..MemMap.UNUSED_HIGH) |i| {
        const addr: u16 = @intCast(i);
        mmu.write8_sys(addr, 0x00);
        mmu.write8_usr(addr, 0xFF);
        std.testing.expectEqual(0x00, mmu.read8_sys(addr)) catch |err| {
            std.debug.print("Failed: UNUSED Region is writable: {d}\n", .{i});
            return err;
        };
    }

    // OAM DMA Transfer: Can only write HRAM.
    mmu.write8_usr(MemMap.DMA, 0x03);
    mmio.onWrite(&mmu);
    for(0..MemMap.HRAM_LOW) |i| {
        const addr: u16 = @intCast(i);
        mmu.write8_sys(addr, 0x00);
        mmu.write8_usr(addr, 0xFF);
        std.testing.expectEqual(0x00, mmu.read8_sys(addr)) catch |err| {
            std.debug.print("Failed: During OAM DMA only HRAM is writeable. Writeable address: {d}\n", .{i});
            return err;
        };
    }
    for(MemMap.HRAM_HIGH..MemMap.INTERRUPT_ENABLE) |i| {
        const addr: u16 = @intCast(i);
        mmu.write8_sys(addr, 0x00);
        mmu.write8_usr(addr, 0xFF);
        std.testing.expectEqual(0x00, mmu.read8_sys(addr)) catch |err| {
            std.debug.print("Failed: During OAM DMA only HRAM is writeable. Writeable address: {d}\n", .{i});
            return err;
        };
    }

    // TODO: Missing Tests:
    // ECHO-RAM: Read: E000-FDFF <==> C000-DDFF
        // Forbidden to be used by Nintendo. 
    // Cannot access CGB palettes during PPU Mode 3 (DRAW).
    // CGB: WRAM and Cart ar on seperate memory busses => depending on start address of dma, writes might be allowed.
}

pub fn runReadMemoryTests() !void {
    const alloc = std.testing.allocator;

    var mmu = try MMU.init(alloc);
    defer mmu.deinit();
    var mmio = MMIO{};
    var ppu = PPU{};
    var pixels = try alloc.alloc(Def.Color, Def.RESOLUTION_WIDTH * Def.RESOLUTION_HEIGHT);
    defer alloc.free(pixels);

    const lcd_contr = PPU.LCDC{ .lcd_enable = true };
    mmu.write8_sys(MemMap.LCD_CONTROL, @bitCast(lcd_contr));
    mmu.write8_sys(MemMap.LCD_Y, 9);

    // PPU: Read VRAM during Mode 3 (DRAW):
    ppu.lyCounter = 81;
    ppu.step(&mmu, &pixels);
    var lcd_stat = PPU.LCDStat{ .ppu_mode = .DRAW };
    mmu.write8_sys(MemMap.LCD_STAT, @bitCast(lcd_stat));
    for(MemMap.VRAM_LOW..MemMap.VRAM_HIGH) |i| {
        const addr: u16 = @intCast(i);
        mmu.write8_sys(addr, 0x00);
        std.testing.expectEqual(0xFF, mmu.read8_usr(addr)) catch |err| {
            std.debug.print("Failed: PPU: Read VRAM during Mode 3 should return 0xFF, Address: {d}\n", .{i});
            return err;
        };
    }

    // PPU: Read OAM during Mode 2 (OAM_SCAN):
    ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    ppu.step(&mmu, &pixels);
    lcd_stat = PPU.LCDStat{ .ppu_mode = .OAM_SCAN };
    mmu.write8_sys(MemMap.LCD_STAT, @bitCast(lcd_stat));
    for(MemMap.OAM_LOW..MemMap.OAM_HIGH) |i| {
        const addr: u16 = @intCast(i);
        mmu.write8_sys(addr, 0x00);
        std.testing.expectEqual(0xFF, mmu.read8_usr(addr)) catch |err| {
            std.debug.print("Failed: PPU: Read OAM during Mode 2 should return 0xFF, Address: {d}\n", .{i});
            return err;
        };
    }

    // PPU: Read OAM during Mode 3 (DRAW):
    ppu.lyCounter = 81;
    ppu.step(&mmu, &pixels);
    lcd_stat = PPU.LCDStat{ .ppu_mode = .DRAW };
    mmu.write8_sys(MemMap.LCD_STAT, @bitCast(lcd_stat));
    for(MemMap.OAM_LOW..MemMap.OAM_HIGH) |i| {
        const addr: u16 = @intCast(i);
        mmu.write8_sys(addr, 0x00);
        std.testing.expectEqual(0xFF, mmu.read8_usr(addr)) catch |err| {
            std.debug.print("Failed: PPU: Read OAM during Mode 3 should return 0xFF, Address: {d}\n", .{i});
            return err;
        };
    }

    // UNUSED: Cannot read.
    for(MemMap.UNUSED_LOW..MemMap.UNUSED_HIGH) |i| {
        const addr: u16 = @intCast(i);
        mmu.write8_sys(addr, 0xFF);
        std.testing.expectEqual(0xFF, mmu.read8_usr(addr)) catch |err| {
            std.debug.print("Failed: UNUSED Region sould return 0xFF: {d}\n", .{i});
            return err;
        };
    }

    // OAM DMA Transfer: Can only read HRAM.
    mmu.write8_usr(MemMap.DMA, 0x03);
    mmio.onWrite(&mmu);
    for(0..MemMap.HRAM_LOW) |i| {
        const addr: u16 = @intCast(i);
        mmu.write8_sys(addr, 0x01);
        std.testing.expectEqual(0xFF, mmu.read8_usr(addr)) catch |err| {
            std.debug.print("Failed: During OAM DMA only HRAM is readable. Readable address: {d}\n", .{i});
            return err;
        };
    }
    for(MemMap.HRAM_HIGH..MemMap.INTERRUPT_ENABLE) |i| {
        const addr: u16 = @intCast(i);
        mmu.write8_sys(addr, 0x01);
        std.testing.expectEqual(0xFF, mmu.read8_usr(addr)) catch |err| {
            std.debug.print("Failed: During OAM DMA only HRAM is readable. Writeable address: {d}\n", .{i});
            return err;
        };
    }

    // TODO: Missing Tests:
    // ECHO-RAM: Read: E000-FDFF <==> C000-DDFF
        // Forbidden to be used by Nintendo. 
    // Unused (FEA0-FEFF)
        // 0xFF when OAM is blocked.
    // CGB: WRAM and Cart ar on seperate memory busses => depending on start address of dma, reads might be allowed.
}

// TODO: Should this be part of the tests of the subsystem?
pub fn runWriteIOTests() !void {
    const alloc = std.testing.allocator;

    var mmu = try MMU.init(alloc);
    defer mmu.deinit();
    var ppu = PPU{};

    mmu.write8_sys(MemMap.LCD_Y, 0x00);
    mmu.write8_usr(MemMap.LCD_Y, 0xFF);
    std.testing.expectEqual(0x00, mmu.read8_usr(MemMap.LCD_Y)) catch |err| {
        std.debug.print("Failed: LCD_Y is not writeable\n", .{});
        return err;
    };

    mmu.write8_sys(MemMap.LCD_STAT, 0x00);
    mmu.write8_usr(MemMap.LCD_STAT, 0xFF);
    ppu.onWrite(&mmu);
    std.testing.expectEqual(0xFF - 0b111, mmu.read8_usr(MemMap.LCD_STAT)) catch |err| {
        std.debug.print("Failed: Low 3 bits of LCD_STAT are read-only\n", .{});
        return err;
    };
}
