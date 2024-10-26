- Fix rest of TODOs from mmio:
    - Correct interrupt flag implementation.
    - Interrupt routine overlay.
- Add that the ppu fakes the status registers each frame (LY, Modes).
    - Just so that some games can already run with that fake ppu!
- Cleanup CPU code!

# Tetris State:
- Waits forever to get an VBlank interrupt.
    - 0x02ED
- The VBlank interrupt handler starts at 0x017E.    
    - interrupt handler writes 1 to a @ 0x0205.
    - It also issues an OAM DMA transfer during one of it's calls.
        - 0xFFB6
