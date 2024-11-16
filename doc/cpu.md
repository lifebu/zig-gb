
# Testing 

zig test test/test.zig --test-filter "MMIO"

- using the blargg-gb test roms I can run them and wait until they are finished.
- they are finished when the cpu has reached an JR instruction that jumps to itself (endless loop).
- then you can compare the pixels of the cpu texture with pixels of a known good screenshot.
- if they differ => something failed.

- Every test seems to use the same tileset it loads. 
- If that is the case, we could then use the tilemap data in memory and convert that into a message.
- This means, that I can decode the actual message on screen. 
- And this means the test can run headless.

- SingleStepTests are generated from raddad772/jsmoo (misc/code_generation/sm83_tests/generation.js).

## Testing with logs:
Them:
zig build run -- 01-special.gb > cpu_log_good.txt 2>&1
My
zig build
./zig-out/bin/zig-gb > playground/cpu_log_bad.txt
diff playground/cpu_log_bad.txt playground/cpu_log_good.txt > playground/cpu_log_diff.txt

use other zig gb emulator for Testing
https://github.com/Ryp/gb-emu-zig

## Current Results:
01-special.gb: Passed
02-interrupts.gb: No interrupts.
03-op sp,hl.gb: Passed
04-op r,imm.gb: Passed
05-op rp.gb: Passed
06-ld r,r.gb: Passed
07-jr,jp,call,ret,rst.gb: Passed 
08-misc instrs.gb: Passed
09-op r,r.gb: Passed
10-bit ops.gb: Passed
11-op a,(hl).gb: Passed 

## Pipelining the CPU and other systems?
- Can I create a pipeline of known operations and execute them?
- So that the cpu has a set of those stages as well as the ppu?
- THen I have a set of ring-buffers for those operations?

## Testing PPU
It would be awesome to have the same trace testing for the ppu.

## Testing MMIO:
- Can I adapt the json SingleStepTests to also test timer?

### Maybe I can automate this process better?
I can run a generator process that creates the cpu logfiles with each instruction being a particular test-rom.
Would be awesome if this would work for all .gb files.
Maybe I can create a fork of a known good emulator for this?
Maybe my emulator can do that later once it's super stable?

# GB resources:
https://gbdev.io/

# Known test roms:
https://gbdev.io/resources.html#emulator-development
https://gbdev.gg8.se/files/roms/blargg-gb-tests/


# Saving memory.
- To save on memory and to have more of the actual emulator be cache friendly I can use some of the memory of the gameboy itself for the emulator.
- Echo RAM is a memory region around 7kb that the gb does not use (access to it gets rerouted to the WRAM).
- So i can place some of my data there.
- This means the entire program could just use the 64kByte of the memory range of the GB.



# MMU/MMIO
- I need to know which if them must be done on write or can be done at the start of next cycle.
    - W: On Write
    - C: Next Cycle
- I don't like to create a huge switch case that is always called on every write.

0x000-0x4000: MBC: 
C- Enable RAM.
C- Set ROM Bank.
C- Set RAM Bank.

0xFF00-0xFFF: F/O Registers: 
C- 0xFF00: Joypad: Could be updated at the start of each cycle.
    - Keep a copy for both lower nibbles in two bytes somewhere.
    - Depending on what test flag is set apply the lower nibbles to the bit.
    - Apply it every cycle.
W- 0xFF04: DIV: Divider:
    - Writing anything to this, resets the divider to 0x00.
C- 0xFF05: TIMA: Timer counter  
C- 0xFF06: TMA: Timer modulo
C- 0xFF07: TAC: Timer control.
C- 0xFF0F: Interrupt Flag.
C- 0xFFFF: Interrupt Enable.

0xFF40-0xFF4B: PPU.
- The PPU will just read those when it is updated.

- Interrupt Enable.  

# MBC Usage Statistics:
- How often some MBC exists => good for testing!
https://b13rg.github.io/Gameboy-MBC-Analysis/#usage-statistics
https://gbhwdb.gekkio.fi/cartridges/gb.html
- Most common MBCs are MBC1 and them MBC5.

- Roms:
None:
alleyway
Dr Mario
Tetris

MBC1:
Castlevania.
Darkwing Duck.
DK.
DKL 2.
DKL 3.
DKL.
DuckTales.
DuckTales2
Jungle Book
Jurassic Park.
Kirby
Kirby2.
link_awake.
little mermaid
metroid2.
super mario land.
tiny toon adventures

Other:
pkmn_blu: MBC5. 
pkmn_silv: MBC3. 

