pub const HIGH_PAGE: u16        = 0xFF00;

// IO
pub const JOYPAD: u16           = 0xFF00;
pub const SERIAL_DATA: u16      = 0xFF01;
pub const SERIAL_CONTROL: u16   = 0xFF02;
pub const DIVIDER: u16          = 0xFF04;
pub const TIMER: u16            = 0xFF05;
pub const TIMER_MOD: u16        = 0xFF06;
pub const TIMER_CONTROL: u16    = 0xFF07;
pub const INTERRUPT_FLAG: u16   = 0xFF0F;
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
