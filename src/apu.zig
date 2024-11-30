const std = @import("std");
const assert = std.debug.assert;

const Def = @import("def.zig");
const MemMap = @import("mem_map.zig");
const MMU = @import("mmu.zig");
const DoubleBuffer = @import("util/DoubleBuffer.zig");

const Self = @This();

const WAVE_DUTY_TABLE = [4][8]u1 {
    [_]u1{ 1, 1, 1, 1, 1, 1, 1, 0 }, // 12.5%
    [_]u1{ 0, 1, 1, 1, 1, 1, 1, 0 }, // 25%
    [_]u1{ 0, 1, 1, 1, 1, 0, 0, 0 }, // 50%
    [_]u1{ 1, 0, 0, 0, 0, 0, 0, 1 }, // 75%
};

// TODO: Somehow I need a faster sample rate here?
const CYCLES_PER_SAMPLE: u10 = (Def.SYSTEM_FREQ / Def.SAMPLE_RATE) + 2;

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
    trigger: bool,
};

const Sequencer = struct {
    length_tick: bool,
    volume_tick: bool,
    sweep_tick: bool,
};

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

pub fn onAPUWrite(self: *Self, mmu: *MMU, addr: u16, val: u8) void {
    const memory: *[]u8 = mmu.getRaw();
    var curr_audio_ctrl: AudioControl = @bitCast(memory.*[MemMap.SOUND_CONTROL]);

    switch(addr) {
        MemMap.SOUND_CONTROL => {
            var audio_ctrl: AudioControl = @bitCast(val);
            if(audio_ctrl.audio_enabled) {
                // TODO: Clears wave channel buffer.

                // channel running indicator bits are read only.
                audio_ctrl.ch1_running = curr_audio_ctrl.ch1_running;
                audio_ctrl.ch2_running = curr_audio_ctrl.ch2_running;
                audio_ctrl.ch3_running = curr_audio_ctrl.ch3_running;
                audio_ctrl.ch4_running = curr_audio_ctrl.ch4_running;
            } else {
                // TODO: Turning APU off makes all registers except SOUND_CONTROL read-only.
                // Disable all channels and reset them.
                audio_ctrl.ch1_running = false;
                self.ch1_duty_idx = 0;
                self.ch1_step_counter = 0;

                audio_ctrl.ch2_running = false;
                self.ch2_duty_idx = 0;
                self.ch2_step_counter = 0;

                audio_ctrl.ch3_running = false;
                audio_ctrl.ch4_running = false;

                self.sequencer_counter = 0;

                // Reset all audio registers.
                for(MemMap.AUDIO_LOW..MemMap.AUDIO_HIGH) |i| {
                    memory.*[i] = 0;
                }
                // TODO: Inconsistent naming.
                memory.*[MemMap.SOUND_CONTROL] = @bitCast(audio_ctrl);
            }
        },
        // TODO: Audio is on ice for now, because in ducktales the actual CH2_LOW_PERIOD, which the game should set to a value is never touched.
        MemMap.CH2_LOW_PERIOD => {
            var a: u32 = 0;
            a += 1;
            memory.*[addr] = val;
        },
        // TODO: Check the trigger bits for Channel 1, 2, 4 (HIGH_PERIOD)
        // TODO: Triggering Channel 3 and 4 resets them.
        MemMap.CH2_HIGH_PERIOD => {
            const ch2_period_high: Ch12PeriodHigh = @bitCast(val);
            if(ch2_period_high.trigger) {
                curr_audio_ctrl.ch2_running = true;
                self.ch2_step_counter = 0;
                // TODO: I am assuming that this is how this works, Pandocs is extremly vague about this.
                // Gameboy Sound Emulation Blog is implemented completly differently.
                const ch2_length: Ch12Length = @bitCast(memory.*[MemMap.CH2_LENGTH]);
                self.ch2_length_timer = ch2_length.initial_length;
            }
            memory.*[MemMap.SOUND_CONTROL] = @bitCast(curr_audio_ctrl);
        },
        MemMap.CH2_LENGTH => {
            // TODO: I am assuming that this is how this works, Pandocs is extremly vague about this.
            // Gameboy Sound Emulation Blog is implemented completly differently.
            const ch2_length: Ch12Length = @bitCast(memory.*[MemMap.CH2_LENGTH]);
            self.ch2_length_timer = ch2_length.initial_length;
        },
        else => {
            memory.*[addr] = val;
        },
    }
}

pub fn step(self: *Self, mmu: *MMU, buffer: *DoubleBuffer) void {
    self.stepCounters(mmu);
    self.stepSampleGeneration(mmu, buffer);
}

fn stepCounters(self: *Self, mmu: *MMU) void {
    const memory: *[]u8 = mmu.getRaw();
    const sequencer: Sequencer = self.stepSequencer(memory.*[MemMap.DIVIDER]);

    var audio_ctrl: AudioControl = @bitCast(memory.*[MemMap.SOUND_CONTROL]);
    if(!audio_ctrl.audio_enabled) {
        return;
    }

    const ch2PeriodHigh: Ch12PeriodHigh = @bitCast(memory.*[MemMap.CH2_HIGH_PERIOD]);
    // TODO: Implement other channels.
    // check if channels need to be turned off.
    if(audio_ctrl.ch2_running) {
        // TODO: Can also disabled through length timer and ch1 through frequency sweep overflow.

        // is DAC on?
        // TODO: Channel 3 DAC is controlled directly!
        const ch2Volume: Ch12Volume = @bitCast(memory.*[MemMap.CH2_VOLUME]);
        if(ch2Volume.initial_volume == 0 and ch2Volume.env_dir == 0) {
            audio_ctrl.ch2_running = false;
        }

        // length timer expired?
        if(sequencer.length_tick and ch2PeriodHigh.length_enable == 1) {
            self.ch2_length_timer += 1;
            if(self.ch2_length_timer >= 64) {
                audio_ctrl.ch2_running = false;
            }
        }
    }
    memory.*[MemMap.SOUND_CONTROL] = @bitCast(audio_ctrl);

    // ch2
    if(audio_ctrl.ch2_running) {
        // From: https://nightshade256.github.io/2021/03/27/gb-sound-emulation.html
        // TODO: Thise is actually wrong, because the first period change does not happen immediately. 
        // Pandocs states I need to increment it and wait until it overflows. 
        // TODO: This is completly wrong it increses the duty index up to 4 cycles!
        //
        self.ch2_step_counter, const overflow = @addWithOverflow(self.ch2_step_counter, 1);
        if(overflow == 1) {
            const ch2PeriodLow: u8 = memory.*[MemMap.CH2_LOW_PERIOD];
            const ch2PeriodHighPart: u3 = ch2PeriodHigh.period_high;
            if(ch2PeriodHighPart == 0) {}
            const ch2Period: u11 = ch2PeriodLow + (@as(u11, ch2PeriodHigh.period_high) << 8);
            self.ch2_step_counter = ch2Period;
            self.ch2_duty_idx +%= 1;
        }
        // if(self.ch2_step_counter == 0) {
        //     const ch2PeriodLow: u8 = memory.*[MemMap.CH2_LOW_PERIOD];
        //     const ch2Period: u11 = ch2PeriodLow + (@as(u11, ch2PeriodHigh.period_high) << 8);
        //     self.ch2_step_counter = (2048 - @as(u14, ch2Period)) * 4;
        //     self.ch2_duty_idx +%= 1;
        // }
        // self.ch2_step_counter -= 1;
    }
}

fn stepSampleGeneration(self: *Self, mmu: *MMU, buffer: *DoubleBuffer) void {
    defer self.sample_counter -= 1;
    if(self.sample_counter == 0) {
        const cycles_per_sample_min: i32 = CYCLES_PER_SAMPLE;
        // switch to a slower rate if the buffer is getting full!
        self.sample_counter = if(buffer.isGettingFull()) cycles_per_sample_min + 1 else cycles_per_sample_min;

        const memory: *[]u8 = mmu.getRaw();
        // TODO: This two array-buffer is pretty bad.
        var samples = [2]i16{0, 0};
        // TODO: Audio is disabled for now, way to broken :/
        // defer buffer.write(&samples) catch {
        //     // std.debug.print("write buffer is full, samples will be skipped!\n", .{});
        // };

        const audio_ctrl: AudioControl = @bitCast(memory.*[MemMap.SOUND_CONTROL]);
        if(!audio_ctrl.audio_enabled) {
            return;
        }

        const ch2Length: Ch12Length = @bitCast(memory.*[MemMap.CH2_LENGTH]);
        // TODO: Just a test full volume!
        const ch2Volume: u4 = 0xF;
        const ch2Duty: u1 = WAVE_DUTY_TABLE[ch2Length.wave_duty][self.ch2_duty_idx];
        // TODO: These two steps could be combined into a DAC function?
        const ch2Amplitude: u4 = ch2Duty * ch2Volume;
        // TODO: The DAC output actually slowly decreses towards 0.
        // Converts from Digital [x0-xF] to Analog [-1.0, 1.0]
        var ch2DACOutput: f32 = (@as(f32, @floatFromInt(ch2Amplitude)) / 7.5) - 1.0;        
        if(!audio_ctrl.ch2_running) {
            ch2DACOutput = 0.0; // Neutral.
        }

        if(ch2DACOutput != 0.0) {
            var b: u32 = 0;
            b += 1;
        }

        // TODO: Missing Mixing of multiple channels
        // TODO: use MemMap.SoundPanning to have each channel on left, right, both or neither side
        // "Simple Mixing and Panning".
        const leftSample: f32 = ch2DACOutput;
        const rightSample: f32 = ch2DACOutput;
        
        // TODO: Include the master volume value in here!
        const maxSample: f32 = @floatFromInt(std.math.maxInt(i16) - 1);
        const leftSampleFlt: f32 = leftSample * maxSample;
        samples[0] = @intFromFloat(leftSampleFlt);
        const rightSampleFlt: f32 = rightSample * maxSample;
        samples[1] = @intFromFloat(rightSampleFlt);

        if(samples[0] == -32766) {
            var a: u32 = 0;
            a += 1;
        }
    }
}

fn stepSequencer(self: *Self, div: u8) Sequencer {
    // TODO: Double speed mode we need to use the 6th bit!
    // TODO: This could better be implemented with more bit calculation!
    const mask = 0b1_0000;
    const old_bit: bool = (self.old_div & mask) == mask;
    const new_bit: bool = (div & mask) == mask;
    if(!new_bit and old_bit) {
        self.sequencer_counter +%= 1;
    }
    self.old_div = div;

    return Sequencer{
        // TODO: Can I use the bits to make this more readable?
        .length_tick = self.sequencer_counter % 2 == 0,
        .sweep_tick = self.sequencer_counter == 2 or self.sequencer_counter == 6,
        .volume_tick = self.sequencer_counter == 7
    };
} 
