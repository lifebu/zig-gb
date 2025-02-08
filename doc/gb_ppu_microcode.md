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
	- Pixel fetcher is uOps, Pixel Pushing is tried every frame.
    - When is pixel pushing suspended:
        - When backgroud FIFO is empty (Window)
	- uOps:
        - CLEAR_FIFO
		- NOP
		- PUSH_PIXEL
		- FETCH_TILE
		- FETCH_DATA_LOW
		- FETCH_DATA_HIGH
        - FETCH_CONSTRUCT
		- FETCH_PUSH:
			If it fails, adds itself into queue.
	- So Pixel fetcher is:
		- FETCH_TILE, NOP, FETCH_DATA_LOW, NOP, FET_DATA_HIGH, FETCH_CONSTRUCT, FETCH_PUSH

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
FETCH_PUSH
