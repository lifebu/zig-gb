const std = @import("std");

const sf = struct {
    usingnamespace @import("sfml");
    usingnamespace sf.graphics;
};

pub const PPU = struct {
    const Self = @This();

    const RESOLUTION_WIDTH = 160;
    const RESOLUTION_HEIGHT = 144;

    const HARDWARE_COLORS = [4]sf.Color{ 
        sf.Color.fromRGB(224, 248, 208),    // white
        sf.Color.fromRGB(136, 192, 112),    // lgrey
        sf.Color.fromRGB(52, 104, 86),      // dgray
        sf.Color.fromRGB(8, 24, 32)         // black
    };
    
    const TILE_SIZE_X = 8;
    const TILE_SIZE_Y = 8;
    const TILE_SIZE_BYTE = 16;
    const TILE_LINE_SIZE_BYTE = 2;

    const TILE_MAP_SIZE_X = 32;
    const TILE_MAP_SIZE_Y = 32;

    const TILE_MAP_BASE_ADDRESS = 0x9800;
    const TILE_BASE_ADDRESS = 0x8000;
    const TILE_MAP_COLOR_OFFSET = 0xFF47;

    const LY_ADDRESS = 0xFF44;

    pub fn updatePixels(_: *Self, memory: *[]u8, pixels: *[]sf.Color) !void {
        const palletteByte: u8 = memory.*[TILE_MAP_COLOR_OFFSET];
        //https://gbdev.io/pandocs/Palettes.html
        const colorID3: u8 = (palletteByte & (3 << 6)) >> 6;
        const colorID2: u8 = (palletteByte & (3 << 4)) >> 4;
        const colorID1: u8 = (palletteByte & (3 << 2)) >> 2;
        const colorID0: u8 = (palletteByte & (3 << 0)) >> 0;

        const colorPalette = [4]sf.Color{ 
            HARDWARE_COLORS[colorID0], HARDWARE_COLORS[colorID1], HARDWARE_COLORS[colorID2], HARDWARE_COLORS[colorID3]
        };

        var y: u16 = 0;
        while (y < RESOLUTION_HEIGHT) : (y += 1) {
            var x: u16 = 0;
            while (x < RESOLUTION_WIDTH) : (x += 1) {
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
                pixels.*[x + (y * RESOLUTION_WIDTH)] = colorPalette[colorID];
            }
        }

        memory.*[LY_ADDRESS] = 144;
    }
};
