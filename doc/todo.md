# Version 1.0:
## Define 1.0:
- Move everything not "required" to 2.0?

## Bugs / Missing.
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
- CPU: STOP, HALT, EI Delay, DI, Halt-Bug
- Cart: MBC, Header, ROM/RAM.
- Input:
    - Test different InputState combinations and the resulting bit with test flags?
- Interrupts
- MMU: OAM-BUG, Read/Write Behavior.
- Test ROMS:
    - Blargg (CPU)
    - MealyBug (PPU)
    - Mooneye (All)
    - Acid2 (PPU)
    - SameSuite (All)
- PPU
    - Static: MemoryDump + Picture => Compare them.
    - Dynamic: MemoryDump + Picture + CPUWriteList (perCycle) => Compare them.
        - Compare each written pixel.
        - MemoryDump: When VBlank starts?
        - CPUWriteList: Each Write to PPU accessible memory.

## Refactor
- Asserts (Defensive Programming, Tigerbeetle).
- CPU: Instructions, STOP, HALT, EI, Halt-Bug.
- Cart: MBC, Header, ROM/RAM.
- Input
- Interrupts:
    cpu.IsInterruptRunning(): currentlyRunning: bool, 
    cpu.ExecInterrupt(): State machine: BLANK, SAVE_PC_LOW, SAVE_PC_HIGH, JUMP 
        - runs for multiple cycles
    https://mgba.io/2018/03/09/holy-grail-bugs-revisited/#the-phantom-of-pinball-fantasies
- MMU: OAM-BUG, Read/Write Behavior, Access Rights (DMA, VRAM, OAM).
- PPU:
- Timer and Divider.

- Platform Timing (window fps, vs gb fps).
- Testsetup:
    - Allow to run single test and all tests.

## Audio / APU
- Platform: sf::Sound, sf::SoundBuffer (loadFromSamples: sample array (int16), channels, sample-rate). 
- TBD

## Debugging Features
- Dependencies:
    - csfml, cimgui, csfml-imgui
- VRAM Viewer, Color-coded tiles?

## Building
- Build with package manager.
- Test Build on windows.

## Github
- Automatic builds
- Automated Testing
- Releases.
- Documentation/Readme.

## User Features
- CLI
- Emulator
- Gracefull Errorhandling (like illegal instructions).
- UI / Menus / Config:
    - Keybinds, Controller.
    - Colors (Color Palette for DMG).
- Savegames
- Savestates
- Fast-forward
- Rapidfire

# Version 2.0:
- CGB.
- SGB.
- Serial.
- Infrared.
- Boot Roms / Startup.
- Cheats: GameGenie / GameShark

# Version 3.0:
- GBA
