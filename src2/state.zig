const std = @import("std");
const sf = struct {
    usingnamespace @import("sfml");
};

// #platform
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

// #cpu
const FlagRegister = packed union {
    F: u8,
    Flags: packed struct {
        _: u4 = 0,
        // TODO: consider to use u1 instead of bool so I have less conversions!
        carry: bool = false,
        halfBCD: bool = false,
        nBCD: bool = false,
        zero: bool = false,
    },
};

const Registers = packed union {
    r16: packed struct {
        AF: u16 = 0,
        BC: u16 = 0,
        DE: u16 = 0,
        HL: u16 = 0,
    },
    // gb and x86 are little-endian
    r8: packed struct {
        F: FlagRegister = . { .F = 0 },
        A: u8 = 0,
        C: u8 = 0,
        B: u8 = 0,
        E: u8 = 0,
        D: u8 = 0,
        L: u8 = 0,
        H: u8 = 0,
    },
};


pub const State = struct {
    // #sys
    alloc: std.mem.Allocator,

    // #platform-conf
    gbFile: []const u8,
    bgbMode: bool = false,
    bgbProc: ?std.process.Child = null,

    // #platform-rendering
    cpuTexture: sf.graphics.Texture = undefined,
    currInputState: InputState = .{},
    gpuSprite: sf.graphics.Sprite = undefined,
    gpuTexture: sf.graphics.Texture = undefined,
    pixels: []sf.graphics.Color = undefined,
    window: sf.graphics.RenderWindow = undefined,
    windowFocused: bool = true,

    // #platform-timing
    clock: sf.system.Clock = undefined,
    deltaMS: f32 = 0,
    targetDeltaMS: f32 = 0,
    fps: f32 = 0,

    // #platform-audio
    audio_mutex: std.Thread.Mutex = std.Thread.Mutex{},
    audio_read_buffer: []i16 = undefined,
    audio_write_buffer: []i16 = undefined,
    audio_write_index: usize = 0,
    audio_test_time: f32 = 0,
    soundStream: *sf.c.sfSoundStream = undefined,

    // #apu
    /// index into the current wave duty pattern in the wave duty table.
    ch1_duty_idx: u3 = 0,
    /// counter that increments the duty index
    ch1_step_counter: u11 = 0,
    /// index into the current wave duty pattern in the wave duty table.
    ch2_duty_idx: u3 = 0,
    /// counter that increments the duty index
    ch2_step_counter: u11 = 0,
    /// length timer that shuts of channel 2 after some time.
    ch2_length_timer: u9 = 0,
    /// old value of the div register. Used to determine falling edges for the frame sequencer.
    old_div: u8 = 0,
    /// current index of the sequencer.
    sequencer_counter: u3 = 0,
    /// counter that is always updated. When this reaches 0, the apu generates a new sample.
    sample_counter: u10 = 0,

    // #cpu
    registers: Registers = .{ .r16 = .{} },
    // Program counter
    pc: u16 = 0,
    // Stack pointer
    sp: u16 = 0,
    // How many cycles the cpu is now ahead of the rest of the system.
    cycles_ahead: u8 = 0,
    ime: bool = false,
    // The effect of EI is delayed by one instruction.
    ime_requested: bool = false,
    isStopped: bool = false,
    isHalted: bool = false,

    // #mmio
    // Used to trigger interrupts from high->low transitions.
    dpadState: u4 = 0xF,
    buttonState: u4 = 0xF,

    // last bit we tested for timer (used to detect falling edge).
    timerLastBit: bool = false,
    // TODO: Maybe rename to "systemCounter"? 
    // TODO: Default value is default value after dmg, for other boot roms I need other values.
    dividerCounter: u16 = 0xAB00,

    dmaIsRunning: bool = false,
    dmaStartAddr: u16 = 0x0000,
    dmaCurrentOffset: u16 = 0,
    dmaCounter: u3 = 0,
};
