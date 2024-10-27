- Implement simple DMA transfer.
    - A thing that lives in the MMIO and transfers 1 byte per 4 cycles from a source location to the oam ram.
    - takes 640 cycles total, OAM is 160Bytes long.
- Fix the implementation for the timer.
    - And test it with the blargg timing rom!
- Add that the ppu fakes the status registers each frame (LY, Modes).
    - Just so that some games can already run with that fake ppu!
- check the rom header for the mbc version!
- implement mbcs: 
- Cleanup CPU code!

# MBC:



# Tetris State:
- Does, run, but no sprites!
