// graphics
pub const RESOLUTION_WIDTH = 160;
pub const RESOLUTION_HEIGHT = 144;
pub const SCALING = 6;

pub const WINDOW_WIDTH = RESOLUTION_WIDTH * SCALING;
pub const WINDOW_HEIGHT = RESOLUTION_HEIGHT * SCALING;

pub const TILE_WIDTH = 8;
pub const RESOLUTION_TILE_WIDTH = RESOLUTION_WIDTH / TILE_WIDTH;

pub const BYTE_PER_LINE = 2;
pub const NUM_2BPP = RESOLUTION_TILE_WIDTH * BYTE_PER_LINE * RESOLUTION_HEIGHT;

// system
pub const SYSTEM_FREQ = 4 * 1_024 * 1_024;
pub const T_CYCLES_IN_60FPS = SYSTEM_FREQ / 60;

// audio
// TODO: When I try to push stereo to sokol, i get super loud garbage data out? 
pub const NUM_CHANNELS = 1; 
pub const SAMPLE_RATE = 48_000;
pub const T_CYCLES_PER_SAMPLE = (SYSTEM_FREQ / SAMPLE_RATE);
pub const NUM_GB_SAMPLES = (T_CYCLES_IN_60FPS / T_CYCLES_PER_SAMPLE) * NUM_CHANNELS;

// memory
pub const ADDR_SPACE = 0x1_0000;
