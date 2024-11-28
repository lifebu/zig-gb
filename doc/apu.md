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
