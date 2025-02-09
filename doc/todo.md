# src3:
- Run emulator itself in thread. Use double-buffer to communicate audio and video data to platform.
    => Errors in the emulator do not crash software (logs with errors).
    => You can re-run emulator at crash (dll hot-reload)!
    => You can have a breakpoint for debugger?
- Use platform to have a set if initialization options for emulator (config menu, etc).
- Add more debugging tools using imgui.
- Once we have cgb support, it can just switch out a different cpu-core for the emulator!
- Add .dll hot-reloading of emulator code.
- Some of the data that I need to create with the uOps i could do with a memory arena scratch space (like the fetcher_data_low, fetcher_data_high).

# Runtime Library.
- Test out the sokol: https://github.com/floooh/sokol
- It has ImGUI, OpenGL, Window Framework, args passing and audio subsystem.
- And official and automatically generated zig binding!
- especially the audio system seems way nicer, because I can decide if I want a callback system or a push system (the latter sounds easier for my purposes).


# Version 1.0:
## Define 1.0:
- Move everything not "required" to 2.0?

## Bugs / Missing.
- MMU:
    - slices and for-loops are ranges excluding max.
    - switches are ranges including max.
    - Check all uses of the MemMap and fix it accordingly.
    - would explain some off-by-one errors!
    - also check all the tests and add more specific tests that make sure that ranges are correctly adhered to.
    - example: Clear out the entire OAM, use DMA Transfer and check the the number of written bytes is the expected OAM size.
- PPU:
    - YFlip:
        - If you have double height object the y-Flip applies to the entire object.
    - Objects:
        - Selection Priority.
        - 10 Objects per Line.
        - Object-Object Priority.
        - Object Performance.
    - Window:
        - One pixel is missing.
    - Midframe Behaviour.
        - When certain scroll registers are fetched!
    - Timing:
        - Correct Mode 3 length (penalties).
    - Stat:
        - What stat does the PPU have when you turn it off?
        - The PPU Mode needs to be 0.
        - I set the initial mode for the PPU to 0x80, but it should be 0x85!
        https://www.reddit.com/r/Gameboy/comments/a1c8h0/what_happens_when_a_gameboy_screen_is_disabled/

## Testing
- Cart: MBC, Header, ROM/RAM.
    - MBC1: ROM+RAM+BAT.
    - MBC3: ROM+TIMER(RTC)+RAM+BAT
    - MBC5: ROM+RAM+BAT+RUMBLE
- Test ROMS:
    - Blargg (CPU)
    - MealyBug (PPU)
    - Mooneye (All)
    - Acid2 (PPU)
    - SameSuite (All)
    - Double-halt-cancel: https://github.com/nitro2k01/little-things-gb/tree/main/double-halt-cancel
    - windesync: https://github.com/nitro2k01/little-things-gb/tree/main/windesync-validate
- PPU
    - Static: MemoryDump + Picture => Compare them.
    - Dynamic: MemoryDump + Picture + CPUWriteList (perCycle) => Compare them.
        - Compare each written pixel.
        - MemoryDump: When VBlank starts?
        - CPUWriteList: Each Write to PPU accessible memory.

## Refactor
- Asserts (Defensive Programming, Tigerbeetle).
    - Add a bunch of logs of a game does something it should not do (like accessing ROM during OAM DMA Transfer).
- CPU: Instructions, HALT, Halt-Bug.
- Cart: MBC, Header, ROM/RAM.
- Interrupts:
    cpu.IsInterruptRunning(): currentlyRunning: bool, 
    cpu.ExecInterrupt(): State machine: BLANK, SAVE_PC_LOW, SAVE_PC_HIGH, JUMP 
        - runs for multiple cycles
    https://mgba.io/2018/03/09/holy-grail-bugs-revisited/#the-phantom-of-pinball-fantasies
- PPU:
- Timer and Divider.

- Platform
- Platform Timing (window fps, vs gb fps).
- Testsetup:
    - Allow to run single test and all tests.
- General Code Cleanup / Quality.

## Audio / APU
- Platform: sf::Sound, sf::SoundBuffer (loadFromSamples: sample array (int16), channels, sample-rate). 
- TBD
https://nightshade256.github.io/2021/03/27/gb-sound-emulation.html
https://github.com/bwhitman/pushpin/blob/master/src/gbsound.txt

- Example of using sfml and audio:
https://github.com/aracitdev/GameBoyEmu/tree/master/Apu

- Started to work on the apu, but the sound is completly broken.
    - Disabled for now.
    - Need to revisit this with more debugging features (imgui).
    - And start step by step
        - generate hardcoded 50% duty squarewave.
        - generate by using i16 duty table with frequency index.
        - generate by using u1 duty table with frequency index and convert to i16.
        - incorporate volume and mixing.

- Hardware Registers: Read/Write Behavior
    - Audio: NR11, NR13, NR14, NR21, NR23, NR24, NR31, NR33, NR34, NR41, NR44, NR52
    https://gbdev.io/pandocs/Hardware_Reg_List.html

## Debugging Features
- Dependencies:
    - csfml, cimgui, csfml-imgui
- VRAM Viewer
    - BG Map, Tiles, OAM, Palettes (~BGB).
    - Color-coded tiles
- IO MAP:
    - State of entire system.
- Joypad Visualization.
- CPU State:
- Audio:
    - Fillpercent of the double buffer write buffer.
- Some other ideas:
    https://www.reddit.com/r/EmuDev/comments/1fu5tgd/finally_i_made_a_gameboycolor_emulator/
    https://www.reddit.com/r/EmuDev/comments/fe1pnq/began_with_my_second_emulator_project_today_i_hit/
    https://www.reddit.com/r/EmuDev/comments/tb4o6p/my_game_boy_advance_emulator_running_iridion_ii/
    https://www.reddit.com/r/EmuDev/comments/mzpx30/adding_a_pokemon_trainer_to_my_gb_emulator_would/
    https://www.reddit.com/r/EmuDev/comments/tiwlxr/i_added_a_gui_debugger_to_my_game_boy_color/
- Maybe allow input-scripts to be run?
    - Like that one Nintendo-DS Emulator?
- Debugging:
    - set breakpoints depending on PC, Reading/Writing specific memory adresses (similar to bgb).

## Building
- Build with package manager.
- Test Build on windows.

## Github
- Github Actions:
    - Automatic builds
    - Automated Testing
- Releases.
- Documentation/Readme.
- Github Pages

## User Features
- CLI
- Gracefull Errorhandling (like illegal instructions).
- UI / Menus / Config:
    - Keybinds, Controller.
    - DMG Color Palette.
    d Hardware Revision (to load Boot roms).
        - Select Boot Roms (GB, SGB, GBC, GBA).
    - Multiplayer setup.
    - Window size (Multiples).
    - FPS Target.
    - Frameskip.
    - Audio: Mute, Enable/Disable Channels, Sample rate, audio buffer size, volume.
- Emulator
    - Savegames
    - Reset.
    - Load Game, Recentlist.

# Version 2.0:
- CPU:
    - STOP (+ Tests!).
    - No licenced game uses this outside fo CGB speed switching.
- CGB.
- Hardware Registers: Read/Write Behavior
    - CGB: KEY1
    - CGB: HDMA1-5
    - CGB: RP (Infrared)
    - CGB: PCM12, PCm34
    https://gbdev.io/pandocs/Hardware_Reg_List.html
- Serial.
- Boot Roms / Startup.
    - SameBoy has open source boot roms!
- Cheats: GameGenie / GameShark

## User Features
- Emulator:
    - Rewind
    - Savestates
    - Fast-forward
    - Rapidfire

# Version 3.0:
- GBA

# Maybe:
- MMU:
    - ECHO-RAM: Not used by any licenced game (forbidden by nintendo).
- Cart:
    - Alternative Wiring of MBC1.
    - MBC1M (Multi cart).
    - MBC5: Rumble.
    - MBC3: RTC.
- Infrared.
- SGB.
- CPU:
    - Halt-Bug: Have not found a shipped game with this bug.
- Interrupts:
    - Spurious Stat Interrupt (DMG Bug).
- MMU: OAM-BUG
    - No shipped game would trigger this.
