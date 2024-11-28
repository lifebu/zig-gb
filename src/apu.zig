const std = @import("std");
const assert = std.debug.assert;

const Def = @import("def.zig");
const MemMap = @import("mem_map.zig");
const MMU = @import("mmu.zig");
const DoubleBuffer = @import("util/DoubleBuffer.zig");

const Self = @This();

const WAVE_DUTY_TABLE = [4][8]u1 {
    [_]u1{ 0, 0, 0, 0, 0, 0, 0, 1},
    [_]u1{ 0, 0, 0, 0, 0, 0, 1, 1},
    [_]u1{ 0, 0, 0, 0, 1, 1, 1, 1},
    [_]u1{ 1, 1, 1, 1, 1, 1, 0, 0},
};

const CYCLES_PER_SAMPLE: u10 = Def.SYSTEM_FREQ / Def.SAMPLE_RATE;

const AudioControl = packed struct(u8) {
    ch1_running: bool,
    ch2_running: bool,
    ch3_running: bool,
    ch4_running: bool,
    _: u3,
    audio_enabled: bool,
};

const MasterVolume = packed struct(u8) {
    right_volume: u3,
    vin_right: u1,
    left_volume: u3,
    vin_left: u1
};

const Ch1Sweep = packed struct(u8) {
    individual_step: u3,
    direction: u1,
    pace: u3,
    _: u1,
};

const Ch12Length = packed struct(u8) {
    initial_length: u6,
    wave_duty: u2,
};

const Ch12Volume = packed struct(u8) {
    sweep_pace: u3,
    env_dir: u1,
    initial_volume: u4
};

const Ch12PeriodHigh = packed struct(u8) {
    period_high: u3,
    _: u3,
    length_enable: u1,
    trigger: u1,
};

ch2_period_counter: u14 = 0,
ch2_wave_duty_pos: u3 = 0,
sample_counter: u10 = 0,

pub fn step(self: *Self, mmu: *MMU, buffer: *DoubleBuffer) void {
    self.stepCounters(mmu);
    self.stepSampleGeneration(mmu, buffer);
}

fn stepCounters(self: *Self, mmu: *MMU) void {
    const memory: *[]u8 = mmu.getRaw();
    // TODO: Can this be done without ptr?
    const audio_control: *align(1) AudioControl = @ptrCast(&memory.*[MemMap.LCD_CONTROL]);
    if(!audio_control.audio_enabled) {
        return;
    }

    // ch1
    // const ch1Sweep: *align(1) Ch1Sweep = @ptrCast(&memory.*[MemMap.CH1_SWEEP]);
    // const ch1Length: *align(1) Ch12Length = @ptrCast(&memory.*[MemMap.CH1_LENGTH]);
    // const ch1Volume: *align(1) Ch12Volume = @ptrCast(&memory.*[MemMap.CH1_VOLUME]);
    // const ch1PeriodLow: u8 = memory.*[MemMap.CH1_LOW_PERIOD];
    // const ch1PeriodHigh: *align(1) Ch12PeriodHigh = @ptrCast(&memory.*[MemMap.CH1_HIGH_PERIOD]);
    // const ch1Period: u11 = ch1PeriodLow + (@as(u11, ch1PeriodHigh.period_high) << 8);

    // ch2
    // const ch2Length: *align(1) Ch12Length = @ptrCast(&memory.*[MemMap.CH2_LENGTH]);
    // const ch2Volume: *align(1) Ch12Volume = @ptrCast(&memory.*[MemMap.CH2_VOLUME]);
    const ch2PeriodHigh: *align(1) Ch12PeriodHigh = @ptrCast(&memory.*[MemMap.CH2_HIGH_PERIOD]);
    if(self.ch2_period_counter == 0) {
        const ch2PeriodLow: u8 = memory.*[MemMap.CH2_LOW_PERIOD];
        const ch2Period: u11 = ch2PeriodLow + (@as(u11, ch2PeriodHigh.period_high) << 8);
        self.ch2_period_counter = (2048 - @as(u14, ch2Period)) * 4;
        self.ch2_wave_duty_pos +%= 1;
    }
    self.ch2_period_counter -= 1;

    // TODO: Pandocs has a different calculation for this, would like to use their version!
    // self.ch2_period_counter, const ch2_freq_overflow = @addWithOverflow(self.ch2_period_counter, 1);
    // if(ch2_freq_overflow == 1) {
    //     const ch2PeriodLow: u8 = memory.*[MemMap.CH2_LOW_PERIOD];
    //     const ch2Period: u11 = ch2PeriodLow + (@as(u11, ch2PeriodHigh.period_high) << 8);
    //     self.ch2_period_counter = ch2Period;
    //     self.ch2_wave_duty_pos +%= 1;
    // }
}

fn stepSampleGeneration(self: *Self, mmu: *MMU, buffer: *DoubleBuffer) void {
    const memory: *[]u8 = mmu.getRaw();
    // TODO: Can this be done without ptr?
    const audio_control: *align(1) AudioControl = @ptrCast(&memory.*[MemMap.LCD_CONTROL]);

    if(self.sample_counter == 0) {
        const cycles_per_sample_min = (Def.SYSTEM_FREQ / Def.SAMPLE_RATE);
        // switch to a slower rate if the buffer is getting full!
        self.sample_counter = if(buffer.isGettingFull())  cycles_per_sample_min + 1 else cycles_per_sample_min;

        var samples = [2]i16{0, 0};
        if(audio_control.audio_enabled) {
            const master_volume: *align(1) MasterVolume = @ptrCast(&memory.*[MemMap.MASTER_VOLUME]);
            const ch2Length: *align(1) Ch12Length = @ptrCast(&memory.*[MemMap.CH2_LENGTH]);

            // TODO: unsure what value ranges amplitudes should have?
            // TODO: Missing ch1, ch3 and ch4 amplitudes
            const ch2Amplitude: u1 = WAVE_DUTY_TABLE[ch2Length.wave_duty][self.ch2_wave_duty_pos];

            // TODO: use MemMap.SoundPanning to have each channel on left, right, both or neither side "Simple Mixing and Panning".
            const leftCh2Amplitude: u1 = ch2Amplitude;
            const leftAmplitude: u1 = leftCh2Amplitude;
            // TODO: Would be neat to create a slice directly from both samples instead of this indexing!
            samples[0] = (std.math.maxInt(i16) / 7) * @as(i16, master_volume.left_volume * leftAmplitude); 

            const rightCh2Amplitude: u1 = ch2Amplitude;
            const rightAmplitude: u1 = rightCh2Amplitude;
            samples[1] = (std.math.maxInt(i16) / 7) * @as(i16, master_volume.right_volume * rightAmplitude); 
        }

        buffer.write(&samples) catch {
            std.debug.print("write buffer is full, samples will be skipped!\n", .{});
        };
    }
    self.sample_counter -= 1;
}
