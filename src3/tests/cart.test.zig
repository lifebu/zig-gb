
const std = @import("std");

const Cart = @import("../cart.zig");
const def = @import("../defines.zig");
const mem_map = @import("../mem_map.zig");

pub fn runCartTests() !void {
    // TODO: Missing Tests:
    // Header: Detect MBC Type (None, 1, 3, 5) and Features (ROMSize, RAMSize, RTC, Rumble).
    // No MBC: 32kByte ROM <= 8kByte RAM.

    // MBC1: Alternative Wiring: 
        // if ROM >= 512KByte. 
        // Not supported!
    // MBC1M: Not Supported!

    // Memory:
    // ROM Bank 0: 0x000-0x3FFF: First 16kByte of ROM (Bank 0). (R)
        // MBC1: Alternative Wiring: Allows to access $20/$40/$60.
    // ROM Bank n: 0x4000-0x7FFF: Acess ROM 01-7F (00->01 Translation). (R)
        // MBC5: No 00-01 Translation. Can map Bank 0 to here.
    // RAM Bank n: 0xA000-0xBFFF: (R/W)
        // RAM not enabled: Returns open-bus (0xFF), Writes ignored. 
        // MBC3: RTC Register can also be mapped here. (R/W)

    // Registers:
    // RAMEnable Register: 0x0000-0x1FFF: (W)
        // Enable: Write 0xA to low nibble
        // Disable: Write anything else.
    // Low ROM-Bank Number: 0x2000-0x3FFF: First nth bit of ROM Bank. (W)
        // MBC1: 5-bit Register, MBC3: 7-bit Register, MBC5: 8-Bit Register
        // Mask to Register-size => 00->01 Translation => Mask to actual ROM-Size => Select Bank.
        // MBC5: No 00->01 Translation, Memory Range: 0x2000-0x2FFF
    // High Rom-Bank Number: 0x3000-0x3FFF (W)
        // MBC5 only, only lsb is used. 
    // RAM-Bank Number: 0x4000-0x5FFF: Select RAM Bank n. (W)
        // MBC1, 3: 2-bit, MBC5: 4-bit
        // MBC1: Alternative Wiring: Use these 2 bits For ROM Bank as well. 
        // MBC3: Values between 0x08-0x0C selects RTC Register. 
        // Mask to Register-size => Mask to actual RAM-Size => Select Bank. 
        // 8kByte RAM (no Banking): Looks at 0-bits => Value always 0 => Selects Bank 0. 
    // Special: 0x6000-0x7FFF: Special Register: (W)
        // MBC1: Bank Mode
            // Bank Mode: 0 (default): ROM Bank 0 and RAM Bank is locked to the their Bank 0.
            // Bank Mode 1: ROM Bank 0 and RAM Bank are controlled using 2-Bit Ram Bank Register. 
            // If ROM <= 512kByte and RAM <= 8KByte => Unused. 
            // ROM: Only relevant for alternative wiring. 
            // RAM: Only relevant without alternative wiring and more than 8kByte RAM.
        // MBC3: Latch Clock Data.
            // Write 00 then 01 => current time is latched to RTC Registers (all!).
            // Does not update until latched again.
            // Clock runs parallel in the background, this gives a snapshot. 
}
