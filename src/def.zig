const std = @import("std");

pub const SYSTEM_FREQ: u32 = 4 * 1_024 * 1_024;
pub const CYCLES_PER_MS: f32 = @as(f32, @floatFromInt(SYSTEM_FREQ)) / 1_000.0;

pub const RESOLUTION_WIDTH = 160;
pub const RESOLUTION_HEIGHT = 144;
pub const CLEAR_PIXELS_EACH_FRAME = false;

pub const NUM_SAMPLES = 1024;
pub const NUM_CHANNELS = 2; //Stereo
pub const SAMPLE_RATE = 48_000;

pub const Color = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 0xFF,
};

pub const InputState = packed struct {
    isRightPressed: bool = false,
    isLeftPressed: bool = false,
    isUpPressed: bool = false,
    isDownPressed: bool = false,

    isAPressed: bool = false,
    isBPressed: bool = false,
    isSelectPressed: bool = false,
    isStartPressed: bool = false,
};
