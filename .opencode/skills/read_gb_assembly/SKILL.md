---
name: "read_gb_assembly"
description: "Explains how to read Game Boy Z80 assembly, including CPU registers, flags, and common patterns"
version: "1.0.0"
tools: ["read", "grep"]
permissions: ["project"]
---

# How to Read Game Boy Assembly

## CPU Registers
The Game Boy CPU (LR35902, similar to Z80) has these 16-bit registers:

| Register | Hi | Lo | Purpose |
|----------|----|----|---------|
| AF | A | F | Accumulator & Flags |
| BC | B | C | General purpose |
| DE | D | E | General purpose |
| HL | H | L | General purpose (often used for memory pointers) |
| SP | - | - | Stack Pointer |
| PC | - | - | Program Counter |

Most registers can be accessed as 16-bit (e.g., `BC`) or 8-bit (e.g., `B`, `C`).

## Flags Register (F)
Lower 8 bits of AF contain these flags:

| Bit | Name | Meaning |
|-----|------|---------|
| 7 | Z | Zero flag - set if result is zero |
| 6 | N | Subtraction flag (BCD) |
| 5 | H | Half Carry flag (BCD) |
| 4 | C | Carry flag - set on overflow |

## Common Instruction Patterns

### Loading and Storing
```
ld a, $80      ; Load immediate value $80 into A
ld b, a        ; Copy A into B
ld (hl), a     ; Store A into memory at HL
ld a, (hl)     ; Load from memory at HL into A
ld a, (1234h)  ; Load from absolute address (16-bit)
ldh (<FFxx>),a ; Load to/from FF00+FFxx (I/O registers)
```

### Arithmetic
```
add a, b       ; A = A + B
add a, $10    ; A = A + immediate
inc a          ; A = A + 1 (sets Z flag)
dec a          ; A = A - 1 (sets Z flag)
xor a          ; A = A XOR A (clears A, sets Z, clears C)
cp a, b        ; Compare: sets flags based on A - B (doesn't modify A)
```

### Flow Control
```
jp nz, label   ; Jump if Zero flag NOT set
jp z, label    ; Jump if Zero flag IS set
jp nc, label   ; Jump if Carry flag NOT set
jr nz, +8      ; Relative jump if not zero (shorter encoding)
call label     ; Push PC to stack, jump to label
ret            ; Pop PC from stack, return
reti           ; Return from interrupt
```

### Stack Operations
```
push af        ; Push AF onto stack
pop bc         ; Pop into BC
```

### Special
```
di             ; Disable interrupts
ei             ; Enable interrupts
nop            ; No operation (1 cycle delay)
halt           ; Halt CPU until interrupt
```

## I/O Registers (FF00-FF7F)
Common ones:
- `P1` (FF00): Joypad
- `DIV` (FF04): Divider register (increments continuously)
- `TIMA` (FF05): Timer counter
- `TMA` (FF06): Timer modulo
- `TAC` (FF07): Timer control
- `IF` (FF0F): Interrupt flag
- `IE` (FFFF): Interrupt enable

## Reading Examples from Test Code

From `timer/tim00.s`:
```
xor a          ; A = A XOR A = 0 (common way to clear A)
ld b, 4        ; Load 4 into B
ldh (<DIV), a  ; Write 0 to DIV register
ld a, b        ; A = B = 4
ldh (<TIMA), a ; Write 4 to TIMA
ld a, %00000100; Load binary 00000100 into A (start 4096 Hz timer)
ldh (<TAC), a  ; Write to timer control
nops 252       ; Execute 252 NOPs (252 cycle delay)
ldh a, (<TIMA) ; Read TIMA into A
```

Key patterns to notice:
- `xor a` is idiomatic for "clear A"
- `ld a, b` copies between 8-bit registers
- `ldh` accesses I/O registers in FF00-FF7F range
- `nops N` creates precise delays
- Comments often explain what cycles/timing behavior is being tested