/// Ranges are: [LOW, HIGH) (high excluding!). 

// Memory
// TODO: Apparently switch cases are including the maximum value, what about for loops (exlcuding max) and slices (slices are excluding max)? 
// TODO: Check all uses of this and fix all instances (could explain some of the off-by-one errors).
pub const ROM_LOW: u16          = 0x0000;
pub const ROM_MIDDLE: u16       = 0x4000;
pub const ROM_HIGH: u16         = 0x8000;

pub const VRAM_LOW: u16         = 0x8000;
pub const VRAM_HIGH: u16        = 0xA000;

pub const CART_RAM_LOW: u16     = 0xA000;
pub const CART_RAM_HIGH: u16    = 0xC000;

pub const WRAM_LOW: u16         = 0xC000;
pub const WRAM_HIGH: u16        = 0xE000;

pub const ECHO_LOW: u16         = 0xE000;
pub const ECHO_HIGH: u16        = 0xFE00;

pub const OAM_LOW: u16          = 0xFE00;
pub const OAM_HIGH: u16         = 0xFEA0;

pub const UNUSED_LOW: u16       = 0xFEA0;
pub const UNUSED_HIGH: u16      = 0xFF00;

pub const HIGH_PAGE: u16        = 0xFF00;

pub const HRAM_LOW: u16         = 0xFF80;
pub const HRAM_HIGH: u16        = 0xFFFF;

pub const AUDIO_LOW: u16        = 0xFF10;
pub const AUDIO_HIGH: u16       = 0xFF40;

// IO
pub const JOYPAD: u16           = 0xFF00;
pub const SERIAL_DATA: u16      = 0xFF01;
pub const SERIAL_CONTROL: u16   = 0xFF02;
pub const DIVIDER: u16          = 0xFF04;
pub const TIMER: u16            = 0xFF05;
pub const TIMER_MOD: u16        = 0xFF06;
pub const TIMER_CONTROL: u16    = 0xFF07;
pub const INTERRUPT_FLAG: u16   = 0xFF0F;
pub const CH1_SWEEP: u16        = 0xFF10;
pub const CH1_LENGTH: u16       = 0xFF11;
pub const CH1_VOLUME: u16       = 0xFF12;
pub const CH1_LOW_PERIOD: u16   = 0xFF13;
pub const CH1_HIGH_PERIOD: u16  = 0xFF14;
pub const CH2_LENGTH: u16       = 0xFF16;
pub const CH2_VOLUME: u16       = 0xFF17;
pub const CH2_LOW_PERIOD: u16   = 0xFF18;
pub const CH2_HIGH_PERIOD: u16  = 0xFF19;
pub const CH3_DAC: u16          = 0xFF1A;
pub const CH3_LENGTH: u16       = 0xFF1B;
pub const CH3_VOLUME: u16       = 0xFF1C;
pub const CH3_LOW_PERIOD: u16   = 0xFF1D;
pub const CH3_HIGH_PERIOD: u16  = 0xFF1E;
pub const CH4_LENGTH: u16       = 0xFF20;
pub const CH4_VOLUME: u16       = 0xFF21;
pub const CH4_FREQ: u16         = 0xFF22;
pub const CH4_CONTROL: u16      = 0xFF23;
pub const MASTER_VOLUME: u16    = 0xFF24;
pub const SOUND_PANNING: u16    = 0xFF25;
pub const SOUND_CONTROL: u16    = 0xFF26;
pub const SOUND_WAVEFORM: u16   = 0xFF30;
pub const LCD_CONTROL: u16      = 0xFF40;
pub const LCD_STAT: u16         = 0xFF41;
pub const SCROLL_Y: u16         = 0xFF42;
pub const SCROLL_X: u16         = 0xFF43;
pub const LCD_Y: u16            = 0xFF44;
pub const LCD_Y_COMPARE: u16    = 0xFF45;
pub const DMA: u16              = 0xFF46;
pub const BG_PALETTE: u16       = 0xFF47;
pub const OBJ_PALETTE_0: u16    = 0xFF48;
pub const OBJ_PALETTE_1: u16    = 0xFF49;
pub const WINDOW_Y: u16         = 0xFF4A;
pub const WINDOW_X: u16         = 0xFF4B;
pub const INTERRUPT_ENABLE: u16 = 0xFFFF;

// Interrupts
pub const INTERRUPT_VBLANK: u8  = 0x01; 
pub const INTERRUPT_LCD: u8     = 0x02; 
pub const INTERRUPT_TIMER: u8   = 0x04; 
pub const INTERRUPT_SERIAL: u8  = 0x08; 
pub const INTERRUPT_JOYPAD: u8  = 0x10; 
