# Minimum Samples:
- Due to a sfml limitation i am required to give the soundstream at least 330 mono-samples @ 48Khz, everytime OnGetData is called.
- 330 samples ~ 7ms => 8ms for safety
- min_samples = (SAMPLE_RATE * CHANNELS) / 1000 * 8ms = 384 for mono, 768 for stereo.

# Buffer size:
- read_buffer = min_samples
- write_buffer = 3 * min_samples

# Sample Generation:
- always generate samples regardless if the gb audio is enabled or not.
- rate:
    - a slower and a faster sample rate => switch to slower when buffer is slow.
    - cycles_per_sample_fast = floor(CPU_FREQ / SAMPLE_RATE).
    - cycles_per_sample_slow = cycles_per_sample_fast + 1
    - example: @48Khz: slow = 88 cycles, fast = 87 cycles.
- rate switching:
    - use slower if write_buffer has more then 2 * min_samples.
    - what rate to pick is determined every time we generate a new sample.

# Startup:
- Give soundstream min_samples empty samples until we have enough in write_buffer.

# Structure
Channel -> DAC -> Mixer -> Amplifier -> HighPassFilter
- channel: generates digital 4-bit value from the core channel and channels functions
    - channel core: (square, wave, noise), 
    - channel function: volume envelope, sweep, length.
    - channel functions are ticked by the frame sequencer (DIV-APU)
- DAC:
    - converts digital to analog for each channel.
- mixer: creates two stereo samples from all 4 channels.
- amplifier: defines the volume.
- HighPassFilter: smooths out transitions over time. 

## APU:
- runs on system clock (not affected by double speed).
- Trigger: trigger turns on a channel (if it's DAC runs). Also reset channel 3 and 4 (1 and 2 only reset by turning APU off).
- Volume & envelope:
    - Master volume control (for left and right outputs.)
    - Channel volume control.
    - Volume Envelope (Ch1, Ch2, Ch4): Adjusts volume over time.
- Length Timer:
    - Shut channel off after certain amount of time.
    - length timer ticks up @256Hz (DIV-APU) from initial value. turns off when it reaches 64 (256 for channel 3).

## Details:
- Channels:
    - Channels have a generation unit and a DAC.
    - DAC converts from 0x0-0xF to output value (-1 and 1, but can be arbitrary).
- DIV-APU Counter / Frame Sequencer:
    - counter is incremented when DIV's bit 4 (5 in double speed) goes to low (=> 512Hz, 8192 T-Cycles).
    - writing to DIV increments this counter!
    - Every nth DIV-APU tick the following functions are ticket (frame sequencer).
        - 8 (64Hz): Envelop Sweep.
        - 2: (256Hz): Sound length.
        - 4: (128Hz): CH1 freq sweep.
- DAC:
    - Channel x's DAC is enabled iff [NRx2] & $F8 != 0.
    - CH3's DAC is controlled by NR30 instead!
    - 0x0 => Analog 1, 0xF => Analog -1 (slope is negative!).
    - DAC disabled => Analog 0.
    - NR52: low 4 bits report if channels are on, not their DAC!
- Channel Activation:
    - Activate: Write to NRx4's MSB => If DAC is off, this will not activate it.
    - BUT: Disabled channel outputs 0, enabled DAC will output "analog 1".
    - Deactivated by:
        - Turning of its DAC.
        - Length timer expires.
        - CH1: Frequency sweep overflows the frequency.

## Channels:
- Pulse channels (CH1, CH2):
    - duty step counter: index into the selected waveform.
        - can only be reset by turning APU off.
    - duty step timer: increments at channel's sample rate (8 times channel frequency).
        - is reset by triggering this channel and APU off.
    - starting a pulse channel always outputs digital zero.
- Wave channel (CH3):
    - sample index counter: index into wave ram table.
        - increments at 32 times channels frequency.
        - each time it increments the sample is read from wave ram table.
        => sample #0 is skipped when you first start up CH3.
    - Buffer: does not emit samples directly, but read samples are stored in a buffer.
        - those are emitted continuously, this buffer is not cleared by retriggering channel.
        - buffer is cleared when turning on APU => Ch3 creates digital 0 when turning on.
    - Output level control???
- Noise Channel (CH4):
    - Uses a LFSR (Linear feedback shift register).
        - has 16 bits: 15 for curent state 1 Bit to store next bit to shift in.
    - When this channel is ticket (frequency in NR43):
        - LSFR_0 NOR LSFR_1 is written to bit 15.
        - In "short mode" we also copy to bit 7.
        - entire LFSR is shifted right.
        - Bit 0 selectects between 0 and chosen volume.
    - LFSR is set to 0 when (re)triggering the channel.
    - There is a case where the LFSR locks up!

# TODO:
d- Turning APU on/off
    - NR52 Audio Control
d- Triggering Channel.
d- Turning off Channel.
d- Core Square Function.
d- Frame Sequencer
d- Channel Length Timer.
d- DAC
- Mixer
- Amplifier

- Look at the warning boxes in pandocs to implement more nuanced behaviour.
- A set of compile time flags I can use to disable/enable channels and audio features:
    - Length timer, stereo mixing, volume, volume envelope, 
