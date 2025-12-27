/// Ranges are: [LOW, HIGH) (high excluding!). 

// Memory
pub const rom_low: u16          = 0x0000;
pub const rom_middle: u16       = 0x4000;
pub const rom_high: u16         = 0x8000;
pub const rom_header: u16       = 0x0100;

pub const vram_low: u16         = 0x8000;
pub const vram_high: u16        = 0xA000;

pub const cart_ram_low: u16     = 0xA000;
pub const cart_ram_high: u16    = 0xC000;

pub const wram_low: u16         = 0xC000;
pub const wram_high: u16        = 0xE000;

pub const echo_low: u16         = 0xE000;
pub const echo_high: u16        = 0xFE00;

pub const oam_low: u16          = 0xFE00;
pub const oam_high: u16         = 0xFEA0;

pub const unused_low: u16       = 0xFEA0;
pub const unused_high: u16      = 0xFF00;

pub const high_page: u16        = 0xFF00;

pub const hram_low: u16         = 0xFF80;
pub const hram_high: u16        = 0xFFFF;

pub const audio_low: u16        = 0xFF10;
pub const audio_high: u16       = 0xFF40;

// IO
pub const joypad: u16           = 0xFF00;
pub const serial_data: u16      = 0xFF01;
pub const serial_control: u16   = 0xFF02;
pub const divider: u16          = 0xFF04;
pub const timer: u16            = 0xFF05;
pub const timer_mod: u16        = 0xFF06;
pub const timer_control: u16    = 0xFF07;
pub const interrupt_flag: u16   = 0xFF0F;

pub const ch1_low: u16          = 0xFF10;
pub const ch1_sweep: u16        = 0xFF10;
pub const ch1_length: u16       = 0xFF11;
pub const ch1_volume: u16       = 0xFF12;
pub const ch1_low_period: u16   = 0xFF13;
pub const ch1_high_period: u16  = 0xFF14;
pub const ch1_high: u16         = 0xFF14;

pub const ch2_low: u16          = 0xFF16;
pub const ch2_length: u16       = 0xFF16;
pub const ch2_volume: u16       = 0xFF17;
pub const ch2_low_period: u16   = 0xFF18;
pub const ch2_high_period: u16  = 0xFF19;
pub const ch2_high: u16         = 0xFF19;

pub const ch3_low: u16          = 0xFF1A;
pub const ch3_dac: u16          = 0xFF1A;
pub const ch3_length: u16       = 0xFF1B;
pub const ch3_volume: u16       = 0xFF1C;
pub const ch3_low_period: u16   = 0xFF1D;
pub const ch3_high_period: u16  = 0xFF1E;
pub const ch3_high: u16         = 0xFF1E;

pub const ch4_low: u16          = 0xFF20;
pub const ch4_length: u16       = 0xFF20;
pub const ch4_volume: u16       = 0xFF21;
pub const ch4_freq: u16         = 0xFF22;
pub const ch4_control: u16      = 0xFF23;
pub const ch4_high: u16         = 0xFF23;

pub const master_volume: u16    = 0xFF24;
pub const sound_panning: u16    = 0xFF25;
pub const sound_control: u16    = 0xFF26;
pub const sound_waveform: u16   = 0xFF30;

pub const lcd_control: u16      = 0xFF40;
pub const lcd_stat: u16         = 0xFF41;
pub const scroll_y: u16         = 0xFF42;
pub const scroll_x: u16         = 0xFF43;
pub const lcd_y: u16            = 0xFF44;
pub const lcd_y_compare: u16    = 0xFF45;
pub const dma: u16              = 0xFF46;
pub const bg_palette: u16       = 0xFF47;
pub const obj_palettes_dmg: u16 = 0xFF48;
pub const obj_palette_0: u16    = 0xFF48;
pub const obj_palette_1: u16    = 0xFF49;
pub const boot_rom: u16         = 0xFF50;
pub const window_y: u16         = 0xFF4A;
pub const window_x: u16         = 0xFF4B;

pub const interrupt_enable: u16 = 0xFFFF;

// Interrupts
pub const interrupt_vblank: u8  = 0x01; 
pub const interrupt_lcd: u8     = 0x02; 
pub const interrupt_timer: u8   = 0x04; 
pub const interrupt_serial: u8  = 0x08; 
pub const interrupt_joypad: u8  = 0x10; 

// VRAM
pub const tile_map_9800 = 0x9800;
pub const tile_map_9C00 = 0x9C00;

pub const tile_8000 = 0x8000;
pub const tile_8800 = 0x8800;
