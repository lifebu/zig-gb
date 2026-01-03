# MMU
## Goals:
- Use as little system memory as possible with predicteable memory access patterns.
- You cannot access some memory all the time: Writes do nothing, Reads return open bus value (define).
- Writing to memory has side effects.
- DMA creates bus conflict with CPU.

## Design:
- Each Subsystem owns it's own memory and has cycle() and memory() function.
- memory() is of shape: memory(request: *Request)
    - Writes: change internal state or ignore, Reads: change data ptr with actual value or open bus value.
    - Subsystem can apply or reject the request.
    - A request that has been applied once can be applied again, but this does nothing.
    - Subsystems can change the request (Only useful for DMA).
- CPU.cycle() returns a memory request struct with address, ptr to value and if it is read or write.
- Request structure allows for as little code as possible for most use cases.
- Bus Conflicts: DMA rejects requests from the cpu that are not from the hram.
- Interrupt Flag: CPU owns it. Other subsystems return their irq. Will be pushed to the CPU each cycle.
    
## Data
### What memory we have:
- rom, cart_ram, boot_rom, boot_rom_enable,
- lcd, vram, oam, oam_dma
- audio, ie, if
- serial, joypad, timer_div,
- wram, hram

### Who uses memory?
- cpu: hram, ie, if, all memory
- boot: boot_rom, boot_rom_enable
- cart: rom, cart_ram
- dma: oam_dma, ally memory
- input: joypad, if
- timer: timer_div, if
- ppu: lcd, vram, oam, if
- apu: audio
- serial: serial, if

### Who "owns" memory?
- cpu: hram, interrupt_enable, interrupt_flag (if)
- boot: boot_rom, boot_rom_enable
- cart: rom, cart_ram
- dma: oam_dma, ally memory
- input: joypad
- timer: timer_div
- ppu: lcd, vram, oam
- apu: audio
- serial: serial

## V2:
- It would be interesting to work on an actual bus system. 
- But I think this would make the emulator so much more complicated.
https://retrocomputing.stackexchange.com/questions/11811/how-does-game-boy-sharp-lr35902-hram-work
https://iceboy.a-singer.de/doc/mem_patterns.html


# CART 
## Goals:
- ROM is read only.
- Can switch different rom/ram banks by writing magic values.
- Supports different kinds of mbcs with different controll ranges.

## Design:
- CartTypeTable + TypeFeatureTable
- Uses stored offsets to return the rom locations on request.
    - rom_bank_low: first 16kByte, usually 0.
    - rom_bank_high: second 16kByte.
    - ram_bank: full 8kByte external ram.
    - ram_enabled: is the ram connected at all.

