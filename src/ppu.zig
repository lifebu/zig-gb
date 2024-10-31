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

const OBJ_SIZE_BYTE = 4;
const OBJ_PER_LINE = 10;
const OAM_SIZE = 40;

const FIRST_TILE_MAP_ADDRESS = 0x9800;
const SECOND_TILE_MAP_ADDRESS = 0x9C00;

const FIRST_TILE_ADDRESS = 0x8000;
const SECOND_TILE_ADDRESS = 0x8800;

const OAM_BASE_ADDRESS = 0xFE00;

const Object = packed struct {
    yPosition: u8,
    xPosition: u8,
    tileIndex: u8,
    flags: packed struct {
        cgbPalette: u3,
        bank: u1,
        dmgPalete: u1, // 0 = OBP0, 1 = OBP1
        xFlip: u1,
        yFlip: u1,
        priority: u1,
    },
};

const LCDC = packed struct {
    bg_window_enable: bool,
    obj_enable: bool,
    obj_size: enum(u1) {
        SINGLE_HEIGHT,
        DOUBLE_HEIGHT,
    },
    bg_map_area: enum(u1) {
        FIRST_MAP,
        SECOND_MAP,
    },
    bg_window_tile_data: enum(u1) {
        SECOND_TILE_DATA,
        FIRST_TILE_DATA,
    },
    window_enable: bool,
    window_map_area: enum(u1) {
        FIRST_MAP,
        SECOND_MAP,
    },
    lcd_enable: bool,
};

const LCDStat = packed struct {
    ppu_mode: enum(u2) {
        H_BLANK,
        V_BLANK,
        OAM_SCAN,
        DRAW,
    },
    ly_is_lyc: bool,
    mode_0_select: bool,
    mode_1_select: bool,
    mode_2_select: bool,
    lyc_select: bool,
    _: u1,
};

lyCounter: u16 = 0,
const LCD_Y_FREQ: u16 = 456;

// TODO: This is just some fake timing.
pub fn updateState(self: *Self, mmu: *MMU) void {
    const memory: *[]u8 = mmu.getRaw();
    const lcd_stat: *align(1) LCDStat = @ptrCast(&memory.*[MemMap.LCD_STAT]);
    var lcdY: u8 = mmu.read8(MemMap.LCD_Y);

    var hasStatInterrupt: bool = false;

    // Line counting
    self.lyCounter += 1;
    if(self.lyCounter >= LCD_Y_FREQ) {
        self.lyCounter = 0;

        lcdY += 1;
        lcdY %= 154;
        mmu.write8(MemMap.LCD_Y, lcdY);

        if(lcdY == 144) {
            mmu.setFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_VBLANK);
        } 

        const lyCompare = mmu.read8(MemMap.LCD_Y_COMPARE);
        lcd_stat.ly_is_lyc = lyCompare == lcdY;
        if(lcd_stat.lyc_select and lcd_stat.ly_is_lyc) {
            hasStatInterrupt = true;
        }
    }

    // Mode setting
    const oldMode = lcd_stat.ppu_mode;
    if(lcdY > 143) {
        lcd_stat.ppu_mode = .V_BLANK;
        if(lcd_stat.mode_1_select and oldMode != lcd_stat.ppu_mode) {
            hasStatInterrupt = true;
        }
    } else if (self.lyCounter <= 80) {
        lcd_stat.ppu_mode = .OAM_SCAN;
        if(lcd_stat.mode_2_select and oldMode != lcd_stat.ppu_mode) {
            hasStatInterrupt = true;
        }
    } else if (self.lyCounter > 80 and self.lyCounter <= 252) {
        lcd_stat.ppu_mode = .DRAW;
    } else if (self.lyCounter > 252) {
        lcd_stat.ppu_mode = .H_BLANK;
        if(lcd_stat.mode_0_select and oldMode != lcd_stat.ppu_mode) {
            hasStatInterrupt = true;
        }
    }
    
    if(hasStatInterrupt) {
        mmu.setFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_LCD);
    }
}

fn getPalette(paletteByte: u8) [4]Def.Color {
    //https://gbdev.io/pandocs/Palettes.html
    const ColorID3: u8 = (paletteByte & (3 << 6)) >> 6;
    const ColorID2: u8 = (paletteByte & (3 << 4)) >> 4;
    const ColorID1: u8 = (paletteByte & (3 << 2)) >> 2;
    const ColorID0: u8 = (paletteByte & (3 << 0)) >> 0;

    return [4]Def.Color{ 
        HARDWARE_COLORS[ColorID0], HARDWARE_COLORS[ColorID1], HARDWARE_COLORS[ColorID2], HARDWARE_COLORS[ColorID3]
    };
}

pub fn updatePixels(_: *Self, mmu: *MMU, pixels: *[]Def.Color) !void {
    const memory: *[]u8 = mmu.getRaw();
    const lcdc: *align(1) LCDC = @ptrCast(&memory.*[MemMap.LCD_CONTROL]);
    if(!lcdc.lcd_enable) {
        return;
    }

    const bgMapBaseAddress: u16 = if(lcdc.bg_map_area == .FIRST_MAP) FIRST_TILE_MAP_ADDRESS else SECOND_TILE_MAP_ADDRESS;
    const windowMapBaseAddress: u16 = if(lcdc.window_map_area == .FIRST_MAP) FIRST_TILE_MAP_ADDRESS else SECOND_TILE_MAP_ADDRESS;
    const bgWindowTileBaseAddress: u16 = if(lcdc.bg_window_tile_data == .SECOND_TILE_DATA) SECOND_TILE_ADDRESS else FIRST_TILE_ADDRESS;
    const objTileBaseAddress: u16 = FIRST_TILE_ADDRESS; 

    const bgPalette = getPalette(memory.*[MemMap.BG_PALETTE]);
    const objPalette0 = getPalette(memory.*[MemMap.OBJ_PALETTE_0]);
    const objPalette1 = getPalette(memory.*[MemMap.OBJ_PALETTE_1]);

    // background
    const bgScrollX: u8 = memory.*[MemMap.SCROLL_X];
    const bgScrollY: u8 = memory.*[MemMap.SCROLL_Y];
    var bgY: u16 = 0;
    while (bgY < Def.RESOLUTION_HEIGHT) : (bgY += 1) {
        var bgX: u16 = 0;
        while (bgX < Def.RESOLUTION_WIDTH) : (bgX += 1) {
            const tileMapX: u16 = (bgX + bgScrollX); 
            const tileMapY: u16 = (bgY + bgScrollY);

            const tileMapIndexX: u16 = (tileMapX / TILE_SIZE_X) % TILE_MAP_SIZE_X;
            const tileMapIndexY: u16 = (tileMapY / TILE_SIZE_Y) % TILE_MAP_SIZE_Y;
            const tileMapAddress: u16 = bgMapBaseAddress + tileMapIndexX + (tileMapIndexY * TILE_MAP_SIZE_Y);
            const tileAddressOffset: u16 align(1) = memory.*[tileMapAddress];

            const tileAddress: u16 = bgWindowTileBaseAddress + (tileAddressOffset * TILE_SIZE_BYTE);
            const tilePixelX: u16 = tileMapX % TILE_SIZE_X;
            const tilePixelY: u16 = tileMapY % TILE_SIZE_Y;

            const tileRowBaseAddress: u16 = tileAddress + (tilePixelY * TILE_LINE_SIZE_BYTE);
            const firstRowByte: u8 = memory.*[tileRowBaseAddress];
            const secondRowByte: u8 = memory.*[tileRowBaseAddress + 1];

            const bitOffset: u3 = @intCast(TILE_SIZE_X - tilePixelX - 1);

            const one: u8 = 1;
            const mask: u8 = one << bitOffset;

            const firstBit: u8 = (firstRowByte & mask) >> bitOffset;
            const secondBit: u8 = (secondRowByte & mask) >> bitOffset;
            const colorID: u8 = firstBit + (secondBit << 1); // LSB first
            pixels.*[bgX + (bgY * Def.RESOLUTION_WIDTH)] = bgPalette[colorID];
        }
    }

    // objects
    if(!lcdc.obj_enable) {
        return;
    }

    var obj_index: u16 = 0;
    while(obj_index < OAM_SIZE) : (obj_index += 1) {
        const objectAddress: u16 = OAM_BASE_ADDRESS + (obj_index * OBJ_SIZE_BYTE);
        const obj: *align(1) Object = @ptrCast(&memory.*[objectAddress]);

        var tileY: u16 = 0;
        while (tileY < TILE_SIZE_Y) : (tileY += 1) {
            const objY: u16 = obj.yPosition + tileY; 
            if (objY < 16 or objY > 160) {
                continue; // line not visible
            }

            var tileX: u16 = 0;
            while (tileX < TILE_SIZE_X) : (tileX += 1) {
                const objX: u16 = obj.xPosition + tileX; 
                if(objX < 8 or objX > 168) {
                    continue; // xPos not visible.
                }

                const tileAddress: u16 = objTileBaseAddress + (@as(u16, obj.tileIndex) * TILE_SIZE_BYTE);
                const tilePixelX: u16 = tileX % TILE_SIZE_X;
                const tilePixelY: u16 = tileY % TILE_SIZE_Y;

                const tileRowBaseAddress: u16 = tileAddress + (tilePixelY * TILE_LINE_SIZE_BYTE);
                const firstRowByte: u8 = memory.*[tileRowBaseAddress];
                const secondRowByte: u8 = memory.*[tileRowBaseAddress + 1];

                const bitOffset: u3 = @intCast(TILE_SIZE_X - tilePixelX - 1);

                const one: u8 = 1;
                const mask: u8 = one << bitOffset;

                const firstBit: u8 = (firstRowByte & mask) >> bitOffset;
                const secondBit: u8 = (secondRowByte & mask) >> bitOffset;
                const colorID: u8 = firstBit + (secondBit << 1); // LSB first
                if(colorID == 0) {
                    continue; // transparent
                }

                const screenX: u16 = if(obj.flags.xFlip == 1) (obj.xPosition - 8) + (TILE_SIZE_X - tileX) else objX - 8;
                const screenY: u16 = if(obj.flags.yFlip == 1) (obj.yPosition - 16) + (TILE_SIZE_Y - tileY) else objY - 16;

                const color: Def.Color = if(obj.flags.dmgPalete == 0) objPalette0[colorID] else objPalette1[colorID];
                pixels.*[screenX + (screenY * Def.RESOLUTION_WIDTH)] = color;
            }
        }       
    }

    if(!lcdc.window_enable) {
        return;
    }

    // window
    const winPosX: u16 = memory.*[MemMap.WINDOW_X];
    const winPosY: u16 = memory.*[MemMap.WINDOW_Y];
    var winY: u16 = 0;
    while (winY < Def.RESOLUTION_HEIGHT) : (winY += 1) {
        var winX: u16 = 0;
        while (winX < Def.RESOLUTION_WIDTH) : (winX += 1) {
            const tileMapIndexX: u16 = (winX / TILE_SIZE_X) % TILE_MAP_SIZE_X;
            const tileMapIndexY: u16 = (winY / TILE_SIZE_Y) % TILE_MAP_SIZE_Y;
            const tileMapAddress: u16 = windowMapBaseAddress + tileMapIndexX + (tileMapIndexY * TILE_MAP_SIZE_Y);
            const tileAddressOffset: u16 align(1) = memory.*[tileMapAddress];

            const tileAddress: u16 = bgWindowTileBaseAddress + (tileAddressOffset * TILE_SIZE_BYTE);
            const tilePixelX: u16 = winX % TILE_SIZE_X;
            const tilePixelY: u16 = winY % TILE_SIZE_Y;

            const tileRowBaseAddress: u16 = tileAddress + (tilePixelY * TILE_LINE_SIZE_BYTE);
            const firstRowByte: u8 = memory.*[tileRowBaseAddress];
            const secondRowByte: u8 = memory.*[tileRowBaseAddress + 1];

            const bitOffset: u3 = @intCast(TILE_SIZE_X - tilePixelX - 1);

            const one: u8 = 1;
            const mask: u8 = one << bitOffset;

            const firstBit: u8 = (firstRowByte & mask) >> bitOffset;
            const secondBit: u8 = (secondRowByte & mask) >> bitOffset;
            const colorID: u8 = firstBit + (secondBit << 1); // LSB first

            const screenX: u16 = winX + 7 - winPosX;
            const screenY: u16 = winY + winPosY;
            if(screenX < 0 or screenX > Def.RESOLUTION_WIDTH or screenY < 0 or screenY > Def.RESOLUTION_HEIGHT) {
                continue; // outside of screen!
            }

            pixels.*[screenX + (screenY * Def.RESOLUTION_WIDTH)] = bgPalette[colorID];
        }
    }
}
