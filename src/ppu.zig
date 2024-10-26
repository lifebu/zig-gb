const std = @import("std");

const Def = @import("def.zig");
const MemMap = @import("mem_map.zig");
const MMU = @import("mmu.zig");

const Self = @This();

const HARDWARE_COLORS = [4]Def.Color{ 
    Def.Color{ .r = 244, .g = 248, .b = 208 },  // white
    Def.Color{ .r = 136, .g = 192, .b = 112},   // lgrey
    Def.Color{ .r = 52,  .g = 104, .b = 86},    // dgray
    Def.Color{ .r = 8,   .g = 24,  .b = 32}     // black
};

const TILE_SIZE_X = 8;
const TILE_SIZE_Y = 8;
const TILE_SIZE_BYTE = 16;
const TILE_LINE_SIZE_BYTE = 2;

const TILE_MAP_SIZE_X = 32;
const TILE_MAP_SIZE_Y = 32;

const TILE_MAP_BASE_ADDRESS = 0x9800;
const TILE_BASE_ADDRESS = 0x8000;

lyCounter: u16 = 0,
const LCD_Y_FREQ: u16 = 456;

pub fn updateState(self: *Self, mmu: *MMU) void {
    // TODO: This is just some fake timing.
    self.lyCounter += 1;
    if(self.lyCounter >= LCD_Y_FREQ) {
        var lcdY: u8 = mmu.read8(MemMap.LCD_Y);
        lcdY += 1;
        if(lcdY == 154) {
            var a: u32 = 10;
            a += 1;
        } 
        lcdY %= 154;
        mmu.write8(MemMap.LCD_Y, lcdY);
        self.lyCounter = 0;
    }
}

pub fn updatePixels(_: *Self, mmu: *MMU, pixels: *[]Def.Color) !void {
    const memory: *[]u8 = mmu.getRaw();

    const palletteByte: u8 = memory.*[MemMap.BG_PALETTE];
    //https://gbdev.io/pandocs/Palettes.html
    const colorID3: u8 = (palletteByte & (3 << 6)) >> 6;
    const colorID2: u8 = (palletteByte & (3 << 4)) >> 4;
    const colorID1: u8 = (palletteByte & (3 << 2)) >> 2;
    const colorID0: u8 = (palletteByte & (3 << 0)) >> 0;

    const colorPalette = [4]Def.Color{ 
        HARDWARE_COLORS[colorID0], HARDWARE_COLORS[colorID1], HARDWARE_COLORS[colorID2], HARDWARE_COLORS[colorID3]
    };

    var y: u16 = 0;
    while (y < Def.RESOLUTION_HEIGHT) : (y += 1) {
        var x: u16 = 0;
        while (x < Def.RESOLUTION_WIDTH) : (x += 1) {
            const tileMapIndexX: u16 = (x / TILE_SIZE_X) % TILE_MAP_SIZE_X;
            const tileMapIndexY: u16 = (y / TILE_SIZE_Y) % TILE_MAP_SIZE_Y;
            const tileMapAddress: u16 = TILE_MAP_BASE_ADDRESS + tileMapIndexX + (tileMapIndexY * TILE_MAP_SIZE_Y);
            const tileAddressOffset: u16 align(1) = memory.*[tileMapAddress];

            const tileAddress: u16 = TILE_BASE_ADDRESS + (tileAddressOffset * TILE_SIZE_BYTE);
            const tilePixelX: u16 = x % TILE_SIZE_X;
            const tilePixelY: u16 = y % TILE_SIZE_Y;

            const tileRowBaseAddress: u16 = tileAddress + (tilePixelY * TILE_LINE_SIZE_BYTE);
            const firstRowByte: u8 = memory.*[tileRowBaseAddress];
            const secondRowByte: u8 = memory.*[tileRowBaseAddress + 1];

            const bitOffset: u3 = @intCast(TILE_SIZE_X - tilePixelX - 1);

            const one: u8 = 1;
            const mask: u8 = one << bitOffset;

            const firstBit: u8 = (firstRowByte & mask) >> bitOffset;
            const secondBit: u8 = (secondRowByte & mask) >> bitOffset;
            const colorID: u8 = firstBit + (secondBit << 1); // LSB first
            pixels.*[x + (y * Def.RESOLUTION_WIDTH)] = colorPalette[colorID];
        }
    }
}
