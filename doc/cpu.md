
# Testing 
- using the blargg-gb test roms I can run them and wait until they are finished.
- they are finished when the cpu has reached an JR instruction that jumps to itself (endless loop).
- then you can compare the pixels of the cpu texture with pixels of a known good screenshot.
- if they differ => something failed.

# GB resources:
https://gbdev.io/

# Known test roms:
https://gbdev.io/resources.html#emulator-development
https://gbdev.gg8.se/files/roms/blargg-gb-tests/
