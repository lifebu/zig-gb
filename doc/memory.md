# Memory Goals:
- Use as little system memory as possible with predicteable memory access patterns.
- You cannot access some memory all the time: Writes do nothing, Reads return open bus value (define).
- Writing to memory has side effects.
- DMA creates bus conflict with CPU.

# Design:
- Each Subsystem owns it's own memory and has cycle() and memory() function.
- memory() is of shape: memory(request: *Request)
    - Writes: change internal state or ignore, Reads: change data ptr with actual value or open bus value.
    - Subsystem can apply or reject the request.
    - A request that has been applied once can be applied again, but this does nothing.
    - Subsystems can change the request (Only useful for DMA).
- CPU.cycle() returns a memory request struct with address, ptr to value and if it is read or write.
    
# Open Questions:

## How should Memory request struct be structured?
- With as little code I want to express in a subsystem that I react to a read/write.


## How to handle DMA BUS conflicts?
- request = DMA.memory(request);
- Either the DMA just returns the input or it overwrites it.
- On CGB the DMA would block depending on which address it reads from (two busses).

## How do we handle Interrupt Flag?
### Requirements
- Each subystem can write to the IF.
- CPU can read/write to the IF.
- Multiple IF writes could happen in a single cycle.
- IF writes from subsystems are like events. they only happen one frame.

### Options
- CPU owns IF.
- Subystem returns if it interrupts (const joypad_irq = input.cycle()).
    => PPU can return 2 interrupts
- After each cycle we call cpu.pushInterrupts() with all the bools.
    => CPU will or them with the current values!

# Ideas / Data
## Memory:
- rom, cart_ram, boot_rom, boot_rom_enable,
- lcd, vram, oam, oam_dma
- audio, ie, if
- serial, joypad, timer_div,
- wram, hram

## Who uses memory?
- cpu: hram, ie, if, all memory
- boot: boot_rom, boot_rom_enable
- cart: rom, cart_ram
- dma: oam_dma, ally memory
- input: joypad, if
- timer: timer_div, if
- ppu: lcd, vram, oam, if
- apu: audio
- serial: serial, if

## Who "owns" memory?
- cpu: hram, interrupt_enable, interrupt_flag (if)
- boot: boot_rom, boot_rom_enable
- cart: rom, cart_ram
- dma: oam_dma, ally memory
- input: joypad
- timer: timer_div
- ppu: lcd, vram, oam
- apu: audio
- serial: serial

# V2:
- It would be interesting to work on an actual bus system. 
- But I think this would make the emulator so much more complicated.
https://retrocomputing.stackexchange.com/questions/11811/how-does-game-boy-sharp-lr35902-hram-work
https://iceboy.a-singer.de/doc/mem_patterns.html
