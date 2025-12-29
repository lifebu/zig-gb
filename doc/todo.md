# src3:
## APU:
- CH3: Length timer + "Frame Sequencer" is working.
     - Test this on CH 1,2,4 later as well.
- CH2,CH1: Is Square duty pattern correctly read (left-to-right) for any frequency and all duty patterns?
- CH2,CH1: Is Duty table read at correct frequency for all period value?
- CH2,CH1: Is Volume sweep implemented for: Different initial volumes, both directions, different paces?
     - Test this on CH4 later as well.
- CH1: Is frequency sweep implemented for different step sizes, both directions, different paces?
- CH4: Is LFSR implemented for: Different shifts + divides and both widths (7 or 15).
- CH1-4: Does trigger bit and is_channel_on status bit work?
- Test All channels and their timing va a generated .txt file.
     - Input: CPU writes to APU registers at given cycle count.
     - Output: APU channel state change at given cycle count.
- APU can be turned on and off.
- Write some tests (or atleast todos) for more specific audio behaviour from documentations.
- Audio cleanup (HPF, etc).

## Audio Sampling:
- If the application runs with less than 60fps, the audio has more cracks => need to generate more samples.
- We should never let the audio device starve out of samples (how to detect that?)
- We also should never waste any samples (i.e, the platform sound buffer is already full).

## CPU:
- Interrupt Sources
    - VBlanK: Add tests!
    - Stat 

## Memory
- Split the memory each system manages it's own. systems have a cycle() and memory() function.
    - Both called by main!
    - How do we handle more generic memory? like the Interrupts?
    - Interrupt Flag:
        - 1: Each system hast their internal flag (bool). PPU has VBlank and Stat bools.
        Combine all flags into one struct of bool* that the CPU can r/w.
        - 2: CPU owns IF. Other systems can push to CPU and CPU can r/w.
        - 3: External system owns IF.
            => Not through request system multiple IF writes can happen in a single cycle!
- Memory:
    - Use:
        - CPU: hram, interrupt_enable (cycle), interrupt_flag (cycle), all memory (cycle)
        - BOOT: boot_rom, boot_rom_enable 
        - CART: rom, cart_ram
        - DMA: dma, rom (cycle), vram (cycle), cart_ram (cycle), work_ram (cycle), oam (cycle)
        - INPUT: joypad, interrupt_flag (updateInputState) 
        - TIMER: timer, timer_control, divider, timer_mod, interrupt_flag (cycle). 
        - PPU: lcd_control, lcd_stat, oam, vram, interrupt_flag (cycle), scroll_x, scroll_y, 
            window_x, window_y, lcd_y, lcd_y_compare, dmg_palette, bg_palette, obj_palette, obj_palette_0, obj_palette_1
        - APU: Audio registers
        - SERIAL: serial_data, serial_control, interrupt_flag (cycle)

    - owned:
        - CPU: hram, interrupt_enable
            => add memory function to the cpu itself! 
        - BUS: interrupt_flag
        - BOOT: boot_rom, boot_rom_enable
        - CART: rom, cart_ram
        - DMA: dma
        - INPUT: joypad
        - TIMER: timer, timer_control, divider, timer_mod
        - PPU: lcd_control, lcd_stat, oam, vram, scroll_x, scroll_y, 
            window_x, window_y, lcd_y, lcd_y_compare, dmg_palette, bg_palette, obj_palette, obj_palette_0, obj_palette_1
            vram_bank, 
        - APU: Audio registers
        - SERIAL: serial_data, serial_control
        !- RAM: work_ram, echo_ram

    # Issues:
    ?- What does the cpu.cycle() return? the BUS.State struct?

    - Buses:
        - If we have an internal_bus (soc_bus), reads/writes are protected from the dma and the cpu could access them.
        => Do research when and how the cpu is reading / accessing the interrupt_flag and interrupt_enable.
        => Do research how the cpu core accesses systems on the soc (can the cpu access them at tcycle speed).
        https://retrocomputing.stackexchange.com/questions/11811/how-does-game-boy-sharp-lr35902-hram-work
        https://iceboy.a-singer.de/doc/mem_patterns.html
        => This confirms that we have an soc_bus (internal) and external_bus.
        - How does the cpu "know" which buss to put the data onto?
            - if (address < 0xFEA0) then external else internal.
            - 0xFEA0: Start of the first unused area.
            - or: if(address >= 0xFF00) internal else external.
            - 0xFF00: Start of I/O registers.

    - Ideas:
        - Move HRAM to CPU => cpu gets a memory() function.  
        - Add RAM (work_ram and echo_ram) 
        - DMA can also return a memory request.
            - overwrites the cpu memory request.
                - ONLY FOR THE EXTERNAL BUS.
            - if the cpu does a write, just discard the request.
            - if the cpu does a read, first we set the request.data.* to 0xFF (so cpu gets a open buss value response)
                - Then we will set the bus state to write and request.data to what the dma wants to write.
        - Rename memory request do bus.
            => BUS.State (like CPU.State).
            => DMG only has one external bus and one internal bus (for I/O).
            => GBC has two external busses (cart_ram + cart_rom vs. work_ram + echo_ram).
                - If the memory request functions only take a bus as the argument, you can control and see at the callside which bus this system uses.
                - Makes it easy to add a new bus to the GBC, just give the function a different pointer to a bus!
            - Lets me rename the memory() function to request()!

    - Memory Request v2:
        - remove mmu.
        - only have memory request that is returned from cpu or the dma.
        - each subsystem only has the memory that it needs to (so emulator data and their registers).
        example main:
        pub const Request = struct {
            read: ?u16 = null,
            write: ?u16 = null,
            data: *u8 = undefined,
        }

        var cpu_request: ?def.Request = cpu.cycle();
        dma.request(&request); // DMA conflict here!
        dma.cycle(&request);
        // TODO: Could also move this into each subsystem.
        switch(cpu_request.getAddress()) {
            mem_map.rom_low..mem_map.rom_high => {
                boot.request(&request);
                cart.request(&request);
            },
            mem_map.wram_low..mem_map.wram_high,
            mem_map.echo_low..mem_map.echo_high => {
                ram.request(&request);
            },
            mem_map.joypad => {
                input.request(&request);
            },
            mem_map.timer_low..mem_map.timer_high => {
                timer.request(&request);
            },
            mem_map.vram_low..mem_map.vram_high,
            mem_map.oam_low..mem_map.oam_high => {
                ppu.request(&request);
            },
            mem_map.audio_low..mem_map.audio_high => {
                apu.request(&request);
            },
        }
        
        boot.cycle();
        cart.cycle();
        input.cycle();
        timer.cycle();
        ppu.cycle();
        apu.cycle();

- add define for open bus value as 0xFF!
- cpu returns memory requests, subsystems react to it.
- Cart: only do request() not cycle(), do not copy to the rom/ram data blocks, just calculate indices! 

## Next:
- How to split subsystems:
    - I currently have a large set of .zig files and "subsystems".
    - Most of them have very little logic and code.
    - Combine them (ram.zig, input.zig, dma.zig, timer.zig, cart.zig, boot.zig, etc.).
    - Maybe I have a more generic "SoC" Class that houses simple subsystems that are to small to fit into their own thing.
        => But how should that one be named?
        - ram, boot and IF are "cold storage"?
        - IOMMU? just io?
- Cart: Merge boot rom onto cart?

- Think about having all subsystems be their own micro op machine?
    - Are the subsystems machines where they have two steps for each microop.
        - 1st: Check memory request.
        - 2nd: Do work.
        - so we do two microops per cycle in each system?
    - DMA:
    - APU:
    - CART:
    - BOOT: Only request() function.
    - INPUT: Only request() function.
    - TIMER:
- main function: a way to have an array of "machines" that I can call?
    - Nice: I can remove systems that are currently not active.
        => BOOT and DMA will remove itself from the list of systems => No need to check if it is active.
        - But who will add the DMA to the active list of systems?
        => When the PPU or APU are turned of => they are removed from the systems list.
    => This is basically saving that state out of band!
    => Dynamic list of active systems!
    - So I am saving if a system is active or not out of band instead of in a bool.
    - Maybe keep an inactive system list?
    - A list of systems would also allow to load different versions of the emulator (dmg ppu vs. gbc ppu).
    pub fn cycle() ?Bus.State {}
    pub fn memory(bus: *Bus.State) void {}
    - Those systems can have a cycle function that optionally returns an BUS.State!

- go from functions with the state as first parameter, to "c++ objects" that load the state implicitly!
- Really standardize the order of declarations and definitions (constants, functions, etc).
- Cart:
    - Add tests for different mbc!
- Add CPU memory access rights (writing to vram), onwrite behaviour, memory requests.
- Think about how the code for loading and initializing the emulator should work.
    - Loading from command line and using the imgui ui.
    - Initialization and Deinitialization logic for all subsystems.
    - MBC for example can write the content of CartRAM to disk when you unload a rom or close the program.
- Add support for savegames.
- Refactor how the access rights system should work.
    - CPU returns it's pin state every cycle.
    - All systems will only get the cpu pins as input in their cycle function.
    - Consider splitting the memory block into the subsystems?
        - example: div, timer, timer_mod exists as 3 registers in the state of timer.zig.
        - So the timer no longer has to know the mmu memory block (better for cache?).
        - When cpu requests a write or read only the timer reacts to it.
        - This means there is no longer a race that the correct subsystem reacts before the mmu as their are disjoint.
        - Splitting memory means we waste loss on unused memory?
        - How are requests then applied fast? subsystem has to do more tests? With the address we already know which subsystem will do this (can we dispatch?)
- How should bus conflicts work? especially with the DMA?
- Change support for loading memory dumps.
    - As we don't save some state of the system (like cpu registers) with the dump. Running a dump would create false positive bugs.
    - I can still support this for testing subsystems like the ppu (draw a specific scene for a test).
    - And I can expand this for full savestate support.
- Refactoring timer, input and dma. They are mostly copied from old source code.
- STOP
- Enable all testing (cycle count, memory pins, etc) and make sure basic test code is cleaned up.
    - Cycle count.
    - MCycle pins. 
- Rework my test system and prepare for a better testing enviroment
    - Custom testrunner?
- Interrupt Sources:
    - Serial.
- APU
- Try to unify the Uop Order:
    - Currently one default case and two exceptions exist:
        - Default: AddrIdu => Dbus (PushPins) => ApplyPins + (ALU or MISC or Nop) => Decode or Nop 
        - JR r8, JR cond r8: Nop => Nop => Alu => IduAdjust 
        - INC (HL), etc: AddrIdu => ALU => Dbus (PushPins) => ApplyPins
- Go over ToDos and do cleanup in cpu.zig!
    - compress genOpcodeBanks
        - Combine RETI, RET and RET cond
    - replace ConditionalCheck with FlagFileID?

## Other:
- Compile the sdhc (sokol shader compiler) myself instead of having binaries here.
    => Has build.zig: https://github.com/floooh/sokol-tools/blob/master/build.zig
- Run emulator itself in thread. Use double-buffer to communicate audio and video data to platform.
    => Errors in the emulator do not crash software (logs with errors).
    => You can re-run emulator at crash (dll hot-reload)!
    => You can have a breakpoint for debugger?
    => The thread itself runs at the exact gb frame-rate (59.7Hz) using sleeps!
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

Try out different types of emulation:
    => MattKC talking about types of emulation:
    https://www.youtube.com/watch?v=lMGu6Ng_3yA
- Interpreter (current version).
- JIT-Dynamic recompilation.
https://rodrigodd.github.io/2023/09/02/gameroy-jit.html
- Dynamic recompilation
    - Coulde try to advance.
- Static recompilation => Save recompilation into asm file.

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
