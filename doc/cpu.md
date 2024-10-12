
# Testing 
- using the blargg-gb test roms I can run them and wait until they are finished.
- they are finished when the cpu has reached an JR instruction that jumps to itself (endless loop).
- then you can compare the pixels of the cpu texture with pixels of a known good screenshot.
- if they differ => something failed.

- Every test seems to use the same tileset it loads. 
- If that is the case, we could then use the tilemap data in memory and convert that into a message.
- This means, that I can decode the actual message on screen. 
- And this means the test can run headless.

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
