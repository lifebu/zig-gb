
# Testing 
- using the blargg-gb test roms I can run them and wait until they are finished.
- they are finished when the cpu has reached an JR instruction that jumps to itself (endless loop).
- then you can compare the pixels of the cpu texture with pixels of a known good screenshot.
- if they differ => something failed.

- Every test seems to use the same tileset it loads. 
- If that is the case, we could then use the tilemap data in memory and convert that into a message.
- This means, that I can decode the actual message on screen. 
- And this means the test can run headless.

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
01-special.gb: DAA missing.
02-interrupts.gb: No interrupts.
03-op sp,hl.gb: Infinite loop?
04-op r,imm.gb: Infinite loop?
05-op rp.gb: PASSED!
06-ld r,r.gb: PASSED!
07-jr,jp,call,ret,rst.gb: Test always resets, so fail? 
08-misc instrs.gb: Test always resets, so fail? 
09-op r,r.gb: Test Failed
10-bit ops.gb: PASSED!
11-op a,(hl).gb: Missing Instruction: 0xCB37 

## Testing PPU
It would be awesome to have the same trace testing for the ppu.

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


