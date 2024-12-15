const std = @import("std");

const APU = @import("../apu.zig");
const Def = @import("../def.zig");
const MMIO = @import("../mmio.zig");
const MMU = @import("../mmu.zig");
const MemMap = @import("../mem_map.zig");
const PPU = @import("../ppu.zig");

pub fn runWriteMemoryTests() !void {
    const alloc = std.testing.allocator;

    var apu = APU{};
    var mmio = MMIO{};
    var mmu = try MMU.init(alloc, &apu, &mmio, null);
    defer mmu.deinit();

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

    // Echo-RAM: Write: E000-FDFF <==> C000-DDFF
    for(0..(MemMap.ECHO_HIGH - MemMap.ECHO_LOW)) |i| {
        const iCast: u16 = @intCast(i);
        mmu.write8_sys(MemMap.WRAM_LOW + iCast, 0x00);
        mmu.write8_usr(MemMap.ECHO_LOW + iCast, 0xFF);
        std.testing.expectEqual(0xFF, mmu.read8_sys(MemMap.WRAM_LOW + iCast)) catch |err| {
            std.debug.print("Failed: Echo-RAM writes to Work-RAM: {d}\n", .{i});
            return err;
        };
    }

    // PPU: Write VRAM during Mode 3 (DRAW):
    var lcd_stat = PPU.LCDStat{ .ppu_mode = .DRAW };
    mmu.write8_sys(MemMap.LCD_STAT, @bitCast(lcd_stat));
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
    lcd_stat = PPU.LCDStat{ .ppu_mode = .OAM_SCAN };
    mmu.write8_sys(MemMap.LCD_STAT, @bitCast(lcd_stat));
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
    lcd_stat = PPU.LCDStat{ .ppu_mode = .DRAW };
    mmu.write8_sys(MemMap.LCD_STAT, @bitCast(lcd_stat));
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

    // TODO: Missing Tests:
    // Cannot access CGB palettes during PPU Mode 3 (DRAW).
}

pub fn runReadMemoryTests() !void {
    const alloc = std.testing.allocator;

    var apu = APU{};
    var mmio = MMIO{};
    var mmu = try MMU.init(alloc, &apu, &mmio, null);
    defer mmu.deinit();

    // Echo-RAM: Read: E000-FDFF <==> C000-DDFF
    for(0..(MemMap.ECHO_HIGH - MemMap.ECHO_LOW)) |i| {
        const iCast: u16 = @intCast(i);
        mmu.write8_sys(MemMap.WRAM_LOW + iCast, 0xFF);
        mmu.write8_sys(MemMap.ECHO_LOW + iCast, 0x00);
        std.testing.expectEqual(0xFF, mmu.read8_usr(MemMap.ECHO_LOW + iCast)) catch |err| {
            std.debug.print("Failed: Echo-RAM reads from Work-RAM: {d}\n", .{i});
            return err;
        };
    }

    // PPU: Read VRAM during Mode 3 (DRAW):
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
        std.testing.expectEqual(0x00, mmu.read8_usr(addr)) catch |err| {
            std.debug.print("Failed: UNUSED Region sould return 0x00: {d}\n", .{i});
            return err;
        };
    }

    // TODO: Missing Tests:
    // Unused (FEA0-FEFF)
        // 0xFF when OAM is blocked.
}

// TODO: Should this be part of the tests of the subsystem?
pub fn runWriteIOTests() !void {
    const alloc = std.testing.allocator;

    var apu = APU{};
    var mmio = MMIO{};
    var mmu = try MMU.init(alloc, &apu, &mmio, null);
    defer mmu.deinit();

    mmu.write8_sys(MemMap.LCD_Y, 0x00);
    mmu.write8_usr(MemMap.LCD_Y, 0xFF);
    std.testing.expectEqual(0x00, mmu.read8_usr(MemMap.LCD_Y)) catch |err| {
        std.debug.print("Failed: LCD_Y is not writeable\n", .{});
        return err;
    };

    mmu.write8_sys(MemMap.LCD_STAT, 0x00);
    mmu.write8_usr(MemMap.LCD_STAT, 0xFF);
    std.testing.expectEqual(0xFF - 0b111, mmu.read8_usr(MemMap.LCD_STAT)) catch |err| {
        std.debug.print("Failed: Low 3 bits of LCD_STAT are read-only\n", .{});
        return err;
    };
}
