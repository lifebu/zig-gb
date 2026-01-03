const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const MMU = @import("../mmu.zig");
const def = @import("../defines.zig");
const PPU = @import("../ppu.zig");
const mem_map = @import("../mem_map.zig");

pub fn runInterruptTests() !void {
    // TODO: just let the ppu run for a frame + buffer and check the order of interrupts we get.
    var ppu: PPU.State = .{};
    var mmu: MMU.State = .{}; 
    PPU.init(&ppu);

    var irq_vblank: bool = false;
    var irq_stat: bool = false;

    // Interrupt request: STAT: LY = LYC.
    ppu.lcd_stat = .{ .ly_is_lyc = true };
    // ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    ppu.lcd_control = .{ .lcd_enable = true };
    ppu.lcd_y = 9;
    ppu.lcd_y_compare = 10;
    irq_vblank, irq_stat = PPU.cycle(&ppu, &mmu);
    std.testing.expectEqual(true, irq_stat) catch |err| {
        std.debug.print("Failed: STAT for LY=LYC requests interrupt.\n", .{});
        return err;
    };

    // Interrupt request: STAT: Mode 0
    ppu.lcd_stat = .{ .mode_0_select = true }; // HBlank
    // ppu.lyCounter = 0;
    // ppu.lastSTATLine = false;
    ppu.lcd_y = 0;
    while(ppu.lcd_y == 0) {
        irq_vblank, irq_stat = PPU.cycle(&ppu, &mmu);
    }
    std.testing.expectEqual(true, irq_stat) catch |err| {
        std.debug.print("Failed: STAT for Mode 0 (HBlank) requests interrupt.\n", .{});
        return err;
    };

    // Interrupt request: STAT: Mode 1
    ppu.lcd_stat = .{ .mode_1_select = true }; // VBlank
    // ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    // ppu.lastSTATLine = false;
    ppu.lcd_y = def.resolution_height - 1;
    irq_vblank, irq_stat = PPU.cycle(&ppu, &mmu);
    // Will trigger VBlank and STAT interrupt!
    std.testing.expectEqual(true, irq_stat) catch |err| {
        std.debug.print("Failed: STAT for Mode 1 (VBlank) requests interrupt.\n", .{});
        return err;
    };
    std.testing.expectEqual(true, irq_vblank) catch |err| {
        std.debug.print("Failed: STAT for Mode 1 (VBlank) requests interrupt.\n", .{});
        return err;
    };

    // Interrupt request: STAT: Mode 2
    ppu.lcd_stat = .{ .mode_2_select = true }; // OAMScan
    // ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    // ppu.lastSTATLine = false;
    ppu.lcd_y = 0;
    irq_vblank, irq_stat = PPU.cycle(&ppu, &mmu);
    std.testing.expectEqual(true, irq_stat) catch |err| {
        std.debug.print("Failed: STAT for Mode 2 (OAMScan) requests interrupt.\n", .{});
        return err;
    };

    // Interrupt request: STAT: STAT Blocking.
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    ppu.lcd_stat = .{ .mode_0_select = true, .mode_2_select = true }; // HBlank, OAMScan
    // ppu.lyCounter = 0;
    ppu.lcd_y = 0;
    while(mmu.memory[mem_map.interrupt_flag] == 0) { // Go until we have an HBlank interrupt.
        irq_vblank, irq_stat = PPU.cycle(&ppu, &mmu);
    }
    // We now got a HBlank stat interrupt, clear it and try to get an OAMScan Stat interrupt.
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    while(ppu.lcd_y == 0) { // Go until we are on the second line
        irq_vblank, irq_stat = PPU.cycle(&ppu, &mmu);
    }
    std.testing.expectEqual(0b0000_0000, mmu.memory[mem_map.interrupt_flag]) catch |err| {
        std.debug.print("Failed: STAT interrupts are blocked for consecutive STAT sources.\n", .{});
        return err;
    };

    // Interrupt request: VBlank: Reached VBlank
    ppu.lcd_stat = .{ }; // Select no STAT
    // ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    ppu.lcd_y = def.resolution_height - 1;
    irq_vblank, irq_stat = PPU.cycle(&ppu, &mmu);
    std.testing.expectEqual(true, irq_vblank) catch |err| {
        std.debug.print("Failed: VBlank requests interrupt.\n", .{});
        return err;
    };
}
