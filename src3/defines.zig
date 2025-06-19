// input
// TODO: Is this optimal? Can we make it easier to calculate the dpad and button bytes?
pub const InputState = packed struct {
    right_pressed: bool = false,
    left_pressed: bool = false,
    up_pressed: bool = false,
    down_pressed: bool = false,

    a_pressed: bool = false,
    b_pressed: bool = false,
    select_pressed: bool = false,
    start_pressed: bool = false,
};

// graphics
pub const resolution_width = 160;
pub const resolution_height = 144;
pub const scaling = 4;

pub const window_width = resolution_width * scaling;
pub const window_height = resolution_height * scaling;

pub const tile_width = 8;
pub const overscan_width = resolution_width + tile_width;
pub const overscan_resolution = overscan_width * resolution_height;

pub const color_depth = 4;
pub const byte_per_line = 2;

// system
pub const system_freq = 4 * 1_024 * 1_024;
pub const t_cycles_in_60fps = system_freq / 60;
pub const t_cycles_per_m_cycle = 4;

// audio
// TODO: When I try to push stereo to sokol, i get super loud garbage data out? 
pub const num_channels = 1; 
pub const sample_rate = 48_000;
pub const t_cycles_per_sample = (system_freq / sample_rate);
pub const num_gb_samples = (t_cycles_in_60fps / t_cycles_per_sample) * num_channels;

// memory
pub const addr_space = 0x1_0000;
