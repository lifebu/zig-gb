# PPU Microcode:
- Instead of a huge switch-case with sub-functions I can define a microcode for the PPU just like the CPU that does all of the ppu state management and logic implicitly.
- For repeated operations (like OAMScan), do I define one 80-cycle uOps buffer or do I create looping operations?
	=> Looping might make this more complicated.
	=> Maybe it is okay to have a 456-uOps long array, that can be partially filled.
	=> We can also define subset of the 456-uOps array to use by defining a value we module with when incrementing the uOps-Index
		=> Looping.
- Try to balance the cycles if possible (do that once everything works an measure it).

OAM_SCAN:
	- Takes 80 cycles for 40 objects => 2 cycles/object
	- Output: 10 objects that need to be drawn in that line (don't know if I copy the entire objects or keep a list of objectIDs).
	- Input: OAMs (Yposition), LY, LCDC (Objectsize)
	- Logic:
		- Scan OAMs sequentially until you find up to 10 suitable-positioned objects.
		- Convert Object-YPosition and see if it is inside that line.
	- uOps:
		- OAM_CHECK idx
		- LOOP or ADVANCE_MODE(ppu_mode, new_mode)

HBLANK:
	- During OAM_SCAN and DRAW and keep count of Dots in Line.
		- Maybe with a general dot counter for all dots of the ppu?
	- Fill buffer with remaining uOps.
	- uOps:
		- NOP
		- ADVANCE_MODE(ppu_mode, new_mode)

VBLANK:
	- Fixed set of Dots (456 dots).
	- When it loads a new line of uOps it either ends with a ADVANCE_MODE(ppu_mode, VBLANK) or ADVANCE_MODE(ppu_mode, OAM_SCAN).
	- uOps:
		- NOP
		- INC_LCD_Y
		- ADVANCE_MODE(ppu_mode, new_mode)

DRAW:
    - Drawing Windows and Objects:
        - "The Ultimate Game Boy Talk": Using window and object comparitors.
        - Can I load the entire line of pixels as uOps assuming that we don't have any window?
        - And then overlay instructions where we are triggering the window and obj code that will reset the fetch and the fifo?
        - So we have a static part (render all backgrounds for that line) and a dynamic part of the uOps buffer that we create depending on the actual content of that line!
        - So we can define the entire line rendering when we enter draw mode!
    - When is WY and WX actuall checked and triggered?
        - WY is only checked once during OAM_SCAN. If the check succeeds, the window is active for this scanline.
        - WX seems to be read multiple time per scanline.
    - Drawing Objects:
        - Y Coordinate is only checked once per scanline.
        - X Coordinate is stored once per scanline in a sprite store.
    - Pixel fetcher and and pixel pusher are running at the same time in draw mode. How to handle that best?
        - 1. Pixel fetcher is uOps, Pixel Pushing is tried every frame.
        - 2. Have a second machine for the pixel pusher?
        - 3. Microcode is split between pixel code and fetcher code?
            - split byte into both nibble?
            - stil requires two "machines".
        !- 4. Having more special instructions.
            - All FETCH instructions also try a pixel push?
            - => Requires a "FETCH_NOP".
        => Problem: We do not know through the uOps itself which mode we are in.
        => Because NOP is used outside of draw!
    - When is pixel pushing suspended:
        - When backgroud FIFO is empty (Window)
	- uOps:
        - CLEAR_FIFO
		- NOP
		- PUSH_PIXEL
		- FETCH_TILE
		- FETCH_DATA
        - FETCH_CONSTRUCT
		- FETCH_PUSH:
			If it fails, adds itself into queue.
	- So Pixel fetcher is:
		- FETCH_TILE, NOP_DRAW, FETCH_DATA, NOP_DRAW, FET_DATA, FETCH_CONSTRUCT, FETCH_PUSH

# uOps 
NOP 
ADVANCE_MODE(new_mode)
    - 4 Modes (2-bit)
OAM_CHECK
INC_LCD_Y
CLEAR_FIFO
PUSH_PIXEL
FETCH_TILE(tileMapPos):
    - Calculates tile address.
FETCH_DATA_LOW
    - Use tile address to get first bitplane
FETCH_DATA_HIGH
    - Use tile address to get second bitplane
FETCH_CONSTRUCT:
    - Construct Fifo info from 2bpp data.
    - This is slightly different for objects and background pixels
FETCH_PUSH
