const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const MMU = @import("../mmu.zig");
const def = @import("../defines.zig");
const PPU = @import("../ppu.zig");
const mem_map = @import("../mem_map.zig");

pub fn runInterruptTests() !void {
    var ppu: PPU.State = .{};
    var mmu: MMU.State = .{}; 

    PPU.init(&ppu);

    // Interrupt request: STAT: LY = LYC.
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    mmu.memory[mem_map.lcd_stat] = 0b0100_0000; // Select LY = LYC.
    // ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    mmu.memory[mem_map.lcd_control] = 0b1000_0000;
    mmu.memory[mem_map.lcd_y] = 9;
    mmu.memory[mem_map.lcd_y_compare] = 10;
    PPU.cycle(&ppu, &mmu);
    std.testing.expectEqual(0b0000_0010, mmu.memory[mem_map.interrupt_flag]) catch |err| {
        std.debug.print("Failed: STAT for LY=LYC requests interrupt.\n", .{});
        return err;
    };

    // Interrupt request: STAT: Mode 0
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    mmu.memory[mem_map.lcd_stat] = 0b0000_1000; // Select Mode 0 (HBlank)
    // ppu.lyCounter = 0;
    // ppu.lastSTATLine = false;
    mmu.memory[mem_map.lcd_y] = 0;
    while(mmu.memory[mem_map.lcd_y] == 0) {
        PPU.cycle(&ppu, &mmu);
    }
    std.testing.expectEqual(0b0000_0010, mmu.memory[mem_map.interrupt_flag]) catch |err| {
        std.debug.print("Failed: STAT for Mode 0 (HBlank) requests interrupt.\n", .{});
        return err;
    };

    // Interrupt request: STAT: Mode 1
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    mmu.memory[mem_map.lcd_stat] = 0b0001_0000; // Select Mode 1 (VBlank)
    // ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    // ppu.lastSTATLine = false;
    mmu.memory[mem_map.lcd_y] = def.resolution_height - 1;
    PPU.cycle(&ppu, &mmu);
    // Will trigger VBlank and STAT interrupt!
    std.testing.expectEqual(0b0000_0011, mmu.memory[mem_map.interrupt_flag]) catch |err| {
        std.debug.print("Failed: STAT for Mode 1 (VBlank) requests interrupt.\n", .{});
        return err;
    };

    // Interrupt request: STAT: Mode 2
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    mmu.memory[mem_map.lcd_stat] = 0b0010_0000; // Select Mode 2 (OAMScan)
    // ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    // ppu.lastSTATLine = false;
    mmu.memory[mem_map.lcd_y] = 0;
    PPU.cycle(&ppu, &mmu);
    std.testing.expectEqual(0b0000_0010, mmu.memory[mem_map.interrupt_flag]) catch |err| {
        std.debug.print("Failed: STAT for Mode 2 (OAMScan) requests interrupt.\n", .{});
        return err;
    };

    // Interrupt request: STAT: STAT Blocking.
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    mmu.memory[mem_map.lcd_stat] = 0b0010_1000; // Select Mode 0 (HBlank) and Mode 2 (OAMScan)
    // ppu.lyCounter = 0;
    mmu.memory[mem_map.lcd_y] = 0;
    while(mmu.memory[mem_map.interrupt_flag] == 0) { // Go until we have an HBlank interrupt.
        PPU.cycle(&ppu, &mmu);
    }
    // We now got a HBlank stat interrupt, clear it and try to get an OAMScan Stat interrupt.
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    while(mmu.memory[mem_map.lcd_y] == 0) { // Go until we are on the second line
        PPU.cycle(&ppu, &mmu);
    }
    std.testing.expectEqual(0b0000_0000, mmu.memory[mem_map.interrupt_flag]) catch |err| {
        std.debug.print("Failed: STAT interrupts are blocked for consecutive STAT sources.\n", .{});
        return err;
    };

    // Interrupt request: VBlank: Reached VBlank
    mmu.memory[mem_map.interrupt_flag] = 0x00;
    mmu.memory[mem_map.lcd_stat] = 0b0000_0000; // Select no STAT interrupt
    // ppu.lyCounter = PPU.DOTS_PER_LINE - 1;
    mmu.memory[mem_map.lcd_y] = def.resolution_height - 1;
    PPU.cycle(&ppu, &mmu);
    std.testing.expectEqual(0b0000_0001, mmu.memory[mem_map.interrupt_flag]) catch |err| {
        std.debug.print("Failed: VBlank requests interrupt.\n", .{});
        return err;
    };
}
