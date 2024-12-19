const std = @import("std");
const assert = std.debug.assert;

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
        dmgPalete: enum(u1) {
            OBP0,
            OBP1,
        },
        xFlip: u1,
        yFlip: u1,
        priority: u1,
    },
};

pub const LCDC = packed struct {
    bg_window_enable: bool = false,
    obj_enable: bool = false,
    obj_size: enum(u1) {
        SINGLE_HEIGHT,
        DOUBLE_HEIGHT,
    } = .SINGLE_HEIGHT,
    bg_map_area: enum(u1) {
        FIRST_MAP,
        SECOND_MAP,
    } = .FIRST_MAP,
    bg_window_tile_data: enum(u1) {
        SECOND_TILE_DATA,
        FIRST_TILE_DATA,
    } = .SECOND_TILE_DATA,
    window_enable: bool = false,
    window_map_area: enum(u1) {
        FIRST_MAP,
        SECOND_MAP,
    } = .FIRST_MAP,
    lcd_enable: bool = false,
};

pub const LCDStat = packed struct {
    ppu_mode: enum(u2) {
        H_BLANK,
        V_BLANK,
        OAM_SCAN,
        DRAW,
    },
    ly_is_lyc: bool = false,
    mode_0_select: bool = false,
    mode_1_select: bool = false,
    mode_2_select: bool = false,
    lyc_select: bool = false,
    _: u1 = 0,

    // TODO: Not sure If I want those functions? they don't save a lot of code, but make the intention clearer?
    pub fn toByte(self: LCDStat) u8 {
        return @bitCast(self);
    }

    pub fn fromByte(val: u8) LCDStat {
        return @bitCast(val);
    }
};

linePixelWait: u8 = 0, // Wait 12 cycles before starting to draw.
currPixelX: u8 = 0,
objectsInCurrLine: u4 = 0,
lyCounter: u16 = 0,
/// Last state of the STAT line. Used to simulate STAT Blocking.
lastSTATLine: bool = false,
pub const DOTS_PER_LINE: u16 = 456;

pub fn step(self: *Self, mmu: *MMU, pixels: *[]Def.Color) void {
    const lcdc: LCDC = @bitCast(mmu.read8_sys(MemMap.LCD_CONTROL));
    if(!lcdc.lcd_enable) {
        return;
    }

    self.updateState(mmu);

    const lcd_stat: LCDStat = @bitCast(mmu.read8_sys(MemMap.LCD_STAT));
    switch (lcd_stat.ppu_mode) {
        .OAM_SCAN => {},
        .DRAW => {
            if(self.linePixelWait < 12) {
                self.linePixelWait += 1;
                return;
            }

            assert(self.currPixelX <= 160);
            const lcdY: u8 = mmu.read8_sys(MemMap.LCD_Y);
            self.drawPixel(mmu, self.currPixelX, lcdY, pixels);
            self.currPixelX += 1;
        },
        .H_BLANK => {},
        .V_BLANK => {},
    }
}

fn updateState(self: *Self, mmu: *MMU) void {
    var lcd_stat: LCDStat = @bitCast(mmu.read8_sys(MemMap.LCD_STAT));
    var lcdY: u8 = mmu.read8_sys(MemMap.LCD_Y);

    // Line counting
    self.lyCounter += 1;
    if(self.lyCounter >= DOTS_PER_LINE) {
        self.lyCounter = 0;

        lcdY += 1;
        lcdY %= 154;
        mmu.write8_sys(MemMap.LCD_Y, lcdY);

        if(lcdY == 144) {
            mmu.setFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_VBLANK);
        } 

        const lyCompare = mmu.read8_sys(MemMap.LCD_Y_COMPARE);
        lcd_stat.ly_is_lyc = lyCompare == lcdY;
    }

    var STATLine: bool = lcd_stat.lyc_select and lcd_stat.ly_is_lyc;

    // Mode setting
    const oldMode = lcd_stat.ppu_mode;
    if(lcdY > 143) {
        lcd_stat.ppu_mode = .V_BLANK;
        STATLine = STATLine or lcd_stat.mode_1_select;
    } else if (self.lyCounter <= 80) {
        lcd_stat.ppu_mode = .OAM_SCAN;
        STATLine = STATLine or lcd_stat.mode_2_select;
    } else if (self.lyCounter > 80 and self.lyCounter <= 252) {
        lcd_stat.ppu_mode = .DRAW;
    } else if (self.lyCounter > 252) {
        lcd_stat.ppu_mode = .H_BLANK;
        STATLine = STATLine or lcd_stat.mode_0_select;
        if(oldMode != lcd_stat.ppu_mode) {
            self.objectsInCurrLine = 0;
            self.currPixelX = 0;
            self.linePixelWait = 0;
        }
    }

    // TODO: If you disable the ppu, the permissions must be lifted!
    switch(lcd_stat.ppu_mode) {
        .OAM_SCAN => {
            mmu.setPermission(.OAM);
        },
        .DRAW => {
            mmu.setPermission(.VRAM);
        },
        .H_BLANK => {
            mmu.clearPermission(.OAM);
            mmu.clearPermission(.VRAM);
        },
        .V_BLANK => {
        },
    }

    mmu.write8_sys(MemMap.LCD_STAT, @bitCast(lcd_stat));
    
    if(STATLine and !self.lastSTATLine) {
        mmu.setFlag(MemMap.INTERRUPT_FLAG, MemMap.INTERRUPT_LCD);
    }
    self.lastSTATLine = STATLine;
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

fn drawPixel(_: *Self, mmu: *MMU, pixelX: u8, pixelY: u8, pixels: *[]Def.Color) void {
    const lcdc: LCDC = @bitCast(mmu.read8_sys(MemMap.LCD_CONTROL));

    const bgMapBaseAddress: u16 = if(lcdc.bg_map_area == .FIRST_MAP) FIRST_TILE_MAP_ADDRESS else SECOND_TILE_MAP_ADDRESS;
    const windowMapBaseAddress: u16 = if(lcdc.window_map_area == .FIRST_MAP) FIRST_TILE_MAP_ADDRESS else SECOND_TILE_MAP_ADDRESS;
    const bgWindowTileBaseAddress: u16 = if(lcdc.bg_window_tile_data == .SECOND_TILE_DATA) SECOND_TILE_ADDRESS else FIRST_TILE_ADDRESS;
    const signedAdressing: bool = bgWindowTileBaseAddress == SECOND_TILE_ADDRESS;
    const objTileBaseAddress: u16 = FIRST_TILE_ADDRESS; 

    const bgPalette = getPalette(mmu.read8_sys(MemMap.BG_PALETTE));
    const objPalette0 = getPalette(mmu.read8_sys(MemMap.OBJ_PALETTE_0));
    const objPalette1 = getPalette(mmu.read8_sys(MemMap.OBJ_PALETTE_1));

    var pixelColorID: u8 = 0;

    // background
    if(lcdc.bg_window_enable) {
        const bgScrollX: u8 = mmu.read8_sys(MemMap.SCROLL_X);
        const bgScrollY: u8 = mmu.read8_sys(MemMap.SCROLL_Y);
        const tileMapX: u16 = (@as(u16, pixelX) + bgScrollX); 
        const tileMapY: u16 = (@as(u16, pixelY) + bgScrollY);

        const tileMapIndexX: u16 = (tileMapX / TILE_SIZE_X) % TILE_MAP_SIZE_X;
        const tileMapIndexY: u16 = (tileMapY / TILE_SIZE_Y) % TILE_MAP_SIZE_Y;
        const tileMapAddress: u16 = bgMapBaseAddress + tileMapIndexX + (tileMapIndexY * TILE_MAP_SIZE_Y);
        var tileAddressOffset: u16 = mmu.read8_sys(tileMapAddress);
        if(signedAdressing) {
            if(tileAddressOffset < 128) {
                tileAddressOffset += 128;
            } else {
                tileAddressOffset -= 128;
            }
        }

        const tileAddress: u16 = bgWindowTileBaseAddress + tileAddressOffset * TILE_SIZE_BYTE;
        const tilePixelX: u16 = tileMapX % TILE_SIZE_X;
        const tilePixelY: u16 = tileMapY % TILE_SIZE_Y;

        const tileRowBaseAddress: u16 = tileAddress + (tilePixelY * TILE_LINE_SIZE_BYTE);
        const firstRowByte: u8 = mmu.read8_sys(tileRowBaseAddress);
        const secondRowByte: u8 = mmu.read8_sys(tileRowBaseAddress + 1);

        const bitOffset: u3 = @intCast(TILE_SIZE_X - tilePixelX - 1);

        const one: u8 = 1;
        const mask: u8 = one << bitOffset;

        const firstBit: u8 = (firstRowByte & mask) >> bitOffset;
        const secondBit: u8 = (secondRowByte & mask) >> bitOffset;
        const colorID: u8 = firstBit + (secondBit << 1); // LSB first
        pixels.*[@as(u16, pixelX) + (@as(u16, pixelY) * Def.RESOLUTION_WIDTH)] = bgPalette[colorID];
        pixelColorID = colorID;
    }
    
    // window
    if(lcdc.window_enable and lcdc.bg_window_enable)
    {
        window: {
            const winPosX: u16 = mmu.read8_sys(MemMap.WINDOW_X);
            const winPosY: u16 = mmu.read8_sys(MemMap.WINDOW_Y);
            if(pixelX + winPosX < 7) {
                return; // outside of screen.
            }
            const screenX: u16 = pixelX + winPosX - 7;
            const screenY: u16 = pixelY + winPosY;
            if(screenX >= Def.RESOLUTION_WIDTH or screenY >= Def.RESOLUTION_HEIGHT) {
                break: window; // outside of screen.
            }

            const tileMapIndexX: u16 = (pixelX / TILE_SIZE_X);
            const tileMapIndexY: u16 = (pixelY / TILE_SIZE_Y);
            const tileMapAddress: u16 = windowMapBaseAddress + tileMapIndexX + (tileMapIndexY * TILE_MAP_SIZE_Y);
            var tileAddressOffset: u16 = mmu.read8_sys(tileMapAddress);
            if(signedAdressing) {
                if(tileAddressOffset < 128) {
                    tileAddressOffset += 128;
                } else {
                    tileAddressOffset -= 128;
                }
            }

            const tileAddress: u16 = bgWindowTileBaseAddress + tileAddressOffset * TILE_SIZE_BYTE;
            const tilePixelX: u16 = pixelX % TILE_SIZE_X;
            const tilePixelY: u16 = pixelY % TILE_SIZE_Y;

            const tileRowBaseAddress: u16 = tileAddress + (tilePixelY * TILE_LINE_SIZE_BYTE);
            const firstRowByte: u8 = mmu.read8_sys(tileRowBaseAddress);
            const secondRowByte: u8 = mmu.read8_sys(tileRowBaseAddress + 1);

            const bitOffset: u3 = @intCast(TILE_SIZE_X - tilePixelX - 1);

            const one: u8 = 1;
            const mask: u8 = one << bitOffset;

            const firstBit: u8 = (firstRowByte & mask) >> bitOffset;
            const secondBit: u8 = (secondRowByte & mask) >> bitOffset;
            const colorID: u8 = firstBit + (secondBit << 1); // LSB first
            pixels.*[screenX + (screenY * Def.RESOLUTION_WIDTH)] = bgPalette[colorID];
            pixelColorID = colorID;
        } 
    }

    // objects
    if(lcdc.obj_enable) {
        var obj_index: u16 = 0;
        while(obj_index < OAM_SIZE) : (obj_index += 1) {
            const objectAddress: u16 = OAM_BASE_ADDRESS + (obj_index * OBJ_SIZE_BYTE);
            const obj: *align(1) Object = @ptrCast(&mmu.memory[objectAddress]);
            const objHeight: u8 = if(lcdc.obj_size == .DOUBLE_HEIGHT) TILE_SIZE_Y * 2 else TILE_SIZE_Y;

            const objPixelX: i16 = @as(i16, pixelX) + 8 - @as(i16, obj.xPosition);
            const objPixelY: i16 = @as(i16, pixelY) + 16 - @as(i16, obj.yPosition);
            if(objPixelX < 0 or objPixelX >= TILE_SIZE_X or objPixelY < 0 or objPixelY >= objHeight) {
                continue; // pixel not inside of object
            }

            // In double height mode you are allowed to use either an even tileindex or the next tileindex and draw the same object.
            const objTileIndex = if(lcdc.obj_size == .DOUBLE_HEIGHT) obj.tileIndex - (obj.tileIndex % 2) else obj.tileIndex;
            const tileOffset: u2 = if(objPixelY >= TILE_SIZE_Y) 1 else 0;
            const tileAddress: u16 = objTileBaseAddress + (@as(u16, objTileIndex + tileOffset) * TILE_SIZE_BYTE);

            const tilePixelX: u8 = @as(u8, @intCast(if(obj.flags.xFlip == 1) TILE_SIZE_X - 1 - objPixelX else objPixelX)) % TILE_SIZE_X;
            const tilePixelY: u8 = @as(u8, @intCast(if(obj.flags.yFlip == 1) objHeight - 1 - objPixelY  else objPixelY)) % TILE_SIZE_Y;

            const tileRowBaseAddress: u16 = tileAddress + (tilePixelY * TILE_LINE_SIZE_BYTE);
            const firstRowByte: u8 = mmu.read8_sys(tileRowBaseAddress);
            const secondRowByte: u8 = mmu.read8_sys(tileRowBaseAddress + 1);

            const bitOffset: u3 = @intCast(TILE_SIZE_X - tilePixelX - 1);

            const one: u8 = 1;
            const mask: u8 = one << bitOffset;

            const firstBit: u8 = (firstRowByte & mask) >> bitOffset;
            const secondBit: u8 = (secondRowByte & mask) >> bitOffset;
            const colorID: u8 = firstBit + (secondBit << 1); // LSB first
            if(colorID == 0) {
                continue; // transparent
            }
            if(obj.flags.priority == 1 and pixelColorID != 0) {
                continue; // can only draw over color 0.
            }

            const color: Def.Color = if(obj.flags.dmgPalete == .OBP0) objPalette0[colorID] else objPalette1[colorID];
            pixels.*[@as(u16, pixelX) + (@as(u16, pixelY) * Def.RESOLUTION_WIDTH)] = color;
        }
    }
}


