# Info
p = passed, f = failed, ~ = depends
- Need to write a sytem to automatically run test roms for a certain hardware (like cpu).

# age-test-roms
- made to complement other test suites.

# Bully
- https://github.com/Ashiepaws/BullyGB/wiki
f- Initial DIV value (after boot rom ran).
- BOOT Register.
- DMA Bus Conflicts.
- Echo RAM.
- Initial VRAM (after boot rom ran).
- Uninitialized RAM State (Starts with FF or 00).
- Unused IO registers return FF.

# blargg
p- cpu_instrs
p- instr_timing
~- interrupt_time 
    => only gbc
p- mem_timing
p- mem_timing-2
f- oam_bug
    => Probably not important to implement.

# !!! dmg-acid2
- Line based PPU Test. Does not write during mode 3 (DRAW).
f- flickering and a lot of details are wrong.
    https://github.com/mattcurrie/dmg-acid2?tab=readme-ov-file
    https://www.reddit.com/r/EmuDev/comments/18a3157/dmgacid2_bug/
    https://www.reddit.com/r/EmuDev/comments/rjw2e4/gameboy_dmgacid2_weird_halt_behavior/
    https://imgur.com/x2R66WQ
    => Uses a lot of LYC interrupts to do work during oam scan on specific lines.

# Gambatte:
- Huge sweep of tests for ppu, halt, apu, interrupts. Seems very detailed.

# GBMicroTest:
- large collection of as-small-as-possible tests to check cycle-accurate timing issues.
- Useful when you have basic functionality there and need to track down timing issues.

# little-things-gb.
- firstwhite: first frame is blank after enabling lcdc.
- Telling LYs: Input order timings.

# mbc3 tester:
p- Tests mbc3 rom banks and switching.

# mealybug-tearoom-tests
- Focuses on changes made to PPU registers during mode 3 (DRAW).
    - Do this after dmg-acid2

# !!! mooneye-test-suite
- large collection of tests from gekkio
    => I think I will try to pass most of these for now.
- wilbertpol: fork of mooneye-test-suite, seems to be very old now.

# rtc3test
- Tests MBC3 real time clock.

# SameSuite
- SameBoy Emulator. Only for very specific behaviour tests.

# !!! scribbltests
- Some small ppu tests that check different basic features.
p- scxly
p- winpos
f- palettely
p- lycscy
f- lycscx
f- fairylake

# strikethrough
- only some specific oam dma behaviour.

# turtle-tests
f- window_y_trigger (ly = wy trigger test).
f- window_y_trigger_wx_offscreen.
