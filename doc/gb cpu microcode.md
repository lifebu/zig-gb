# CPU Model:
- Pins:
	- interrupt signals.
	- 8-bit bidirectional data bus.
	- 16-bit address bus controlled by cpu.
- Control Unit: 
	- decodes instructions
	- generates control signals for cpu core
	- checks and dispatches interrupts (Request in, Acknowledge out)
- Register file:
	- 16-bit program counter (PC), 16-bit stack pointer (SP), 
	- 8-bit accumulator (A), 8-bit flags register (F), 
	- register pairs (BC, DE, HL)
	- 8-bit instruction register (IR)
	- interrupt enable (IE).
- ALU:
	- 8-bit ALU, 
	- 2 8-bit input ports,
	- ALU outputs to register file or CPU data bus.
- IDU:
	- 16-bit Increment/Decrement Unit.
	- Operates on the 16-bit address bus.
	- IDU outputs into register file (16-bit register, or register pair).
	- can work in parallel to ALU.

# CPU Variant Decoding.
- I can decode the variant faster If I define a zig packed struct of size u8 with the corresponding relevant bits (for example 3) combined into a type that immediately gives me the variant.
- Then I do not need to do some bit-twiddling.

# Timing:
- CPU can only do one memory access per M-cycle
- CPU cannot use the data during the same M-cycle.
- One M-cycle for fetch, at least one M-cycle for execute.
- Fetch overlaps with last machine cycle of last instruction.
	=> Only that fetch can do memory access, not the execution.
- For Programmers: In practice think of a program as a sequence of non-overlapping instructions.

# SingleStepTests:
- 8-bit data pins, 16-bit address pins, (RWM)-pins: read, write, memory-request.
- RWM: They control the following cases:
	- Put data from register file onto data bus. (-WM).
	- Put data from data bus onto register file. (R-M).
	- Put data from alu onto register file: (-W-).
	- Put data from alu onto data bus: (???).
	- put data from data bus onto alu input: (???).
- null for address or data: bus is electrically disconnect.
	=> for convenience the single step test re-uses the last address generated.

# Idea:
- CPU uops @4MHz => CPU is clocked like rest of system.
- the ppu FIFO Pixel fetcher can work the same way.
- ~512 instructions, 74 instruction families:
	- 26 ALU-OPS + 5 (NOP, SET_ADDR, DECORE_IR, IDU, SET_DBUS) + >= 4 (MISC uOPS)
	=> ~35 uOps => 47% of instructions families.
- Define one pseudo 16-bit register WZ for temporary results.
- gekkio: Gameboy technical reference:
	https://gekkio.fi/files/gb-docs/gbctr.pdf
    - They use ALU op and Misc op. They can never happen at same time.
    => T-Cycles: Addr bus, Data bus, IDU Op, (ALU Op or Misc Op).
- End all microcode with DECORE_IR uop.
    => So that the next instructions will automatically be fetched.
- Use uOp families:
    - SET_ADDR encodes source address to use like:
    - BC, DE, HL, PC, SP, 0xFF00 + Z, 0xFF00 + C.
- For everything we need more than 256 combinations from on byte.
    => Split into execution units?
    - So that each unit can do stuff in parallel to other units?
    - Like taking a cycle to set the IDU does not impede the ALU from setting up?

# uOps
## Encoding:
- 2 Byte Encoding.
- 1st Byte is Function.
- 2nd Byte are Parameters.

## Categories:
- DBUS: Register, ALU-Out and External.
- ADDR: Set Addressbus
- IDU: (Function + Output).
- DECODE: IR, Interrupt.
- ALU: Both Inputs, Function.

## Timing:
0: ADDR + IDU 
1: DBUS
2: ALU/MISC
3: DECODE

## NOP
## STOP and HALT
## ALU uOps (26):
- INC, DEC, RLC, RRC, RL, RR, SL, SR, SWAP, SRL, 
- ADJ (DAA-Adjust), NOT, SCF, CCF, ASSIGN (ld r,r), ADD, ADC, SUB, SBC, AND, 
- XOR, OR, CP, BIT, RES, SET.
    26 => 5-bits 
## ALU Inputs:
- 8bit register: A, B, C, D, E, H, L, W, Z, SPL, SPH,
    => Do we define each input individually?
    - 11 => 4-bits per inputs.
=> 13 bits.
## SET_ADDR
- SP, PC, HL, BC, DE, WZ (fake), 0xFF00+C, 0xFF00+Z, (PCH?)
    => 3 bits
## IDU
- IDU+, IDU-, Nothing
    => 3 bits
- And IDU Target!
## SET_DBUS
- RWM: External->Register, Register->External, ALU->External, ALU->Register
    => 2 bits.
- IR, A, B, C, D, E, H, L, W, Z, SPL, SPH, PCH, PCL
    => 14 => 4 bits.
    => strict superset of ALU inputs => use same encoding for both.
## DECODE
- IR or Interrupt
## Misc
- Write-back WZ (3): r16 <- WZ, SP <- WZ, PC <- WZ
- Conditional Check (?): cc
- Change IME (2): IME <- 1, IME <- 0, (1 bit)
- SetPC (restart) (1): PC <- restart-addr


# Instruction Family Implementations:
- Instruction (NumBytes NumCycles): uOps
	- Between M-Cycles: the state from the last M-cycle on the memory bus.
- FETCH(~ 4): SET_ADDR, IDU+, NOP, NOP
- NOP(1 4): DECODE->IR, NOP, NOP, NOP
	- Between M-Cycles: [[PC, OPCODE, "R-M"]] (Fetch output).
- LD r16, imm16(? ?):
- LD [r16mem], A(? ?):
- LD a, [r16mem](? ?):
- LD [imm16], sp(? ?):
- INC r16(1 8): SET_ADDR, IDU+, NOP, NOP + FETCH(~ 4)
	- Address used in first M-cycle => no fetch interleaved.
	- Between M-Cycles: [[PC, OPCODE, "R-M"], [-, -, "---"]]}
- DEC r16(1 8): SET_ADDR, IDU-, NOP, NOP + FETCH(~ 4)
	- Address used in first M-cycle => no fetch interleaved.
	- Between M-Cycles: [[PC, OPCODE, "R-M"], [-, -, "---"]]}
- ADD HL, r16(?):
- INC r8(1 4): SET_ADDR, IDU+, ALU-IO, ALU-INC.
	- Between M-Cycles: [[PC, OPCODE, "R-M"]]
- DEC r8(1 4): SET_ADDR, IDU+, ALU-IO, ALU-DEC.
	- Between M-Cycles: [[PC, OPCODE, "R-M"]]
- LD r8, imm8(?):
- RLCA(?):
- RRCA(?):
- RLA(?):
- RRA(?):
- DAA(?):
- CPL(?):
- SCF(?):
- CCF(?):
- JR imm8(?):
- JR cond, imm8(?):
- STOP(?):
- LD r8, r8(?):
- HALT(?):
- ADD a, r8(1, 4): SET_ADDR, IDU+, ALU-IO, ALU-ADD
	- Between M-Cycles: [[PC, OPCODE, "R-M"]]
- ADC a, r8(?):
- SUB a, r8(?):
- SBC a, r8(?):
- AND a, r8(?):
- XOR a, r8(?):
- OR a, r8(?):
- CP a, r8(?):
- ADD a, imm8(2, 8): SET_ADDR, IDU+, NOP, NOP + ADD a, r8(1, 4)
	=> Once cycle to load immediate, Once cycle for add.
	- Between M-Cycles: [[PC , OPCODE, "R-M"], [PC+1, [PC+1] , "R-M"]]
- ADC a, imm8(?):
- SUB a, imm8(?):
- SBC a, imm8(?):
- AND a, imm8(?):
- XOR a, imm8(?):
- OR a, imm8(?):
- CP a, imm8(?):
- RET cond(?):
- RET(?):
- RETI(?):
- JP cond, imm16(?):
- JP imm16(?):
- JP HL(?):
- CALL cond, imm16(?):
- CALL imm16(?):
- RST tgt3(?):
- POP r16stk(?):
- PUSH r16stk(?):
- LDH [c], a(?):
- LDH [imm8], a(?):
	- We are setting 0xFF00 + Z on the address bus.
	- 0xFF00 is the high 8-bit and Z the low 8-bit.
	- Maybe we can set the high and low 8-bit of the address bus individually?
	- With this construct setting "PC" to the address buss actually sets high-PC and low-PC to the address bus!
	- If we see PC as two registers (P and C) that we can never individually address, setting PC to the buss or DE is the same!
	- Setting PC, SP, HL, DE, BC are all the same!
- LD [imm16], a(?):
- LDH a, [c](?):
- LDH a, [imm8](?):
- LD a, [imm16](?):
- ADD SP, imm8(?):
- LD HL, SP + imm8(?):
- LD SP, HL(?):
- DI(?):
- EI(?):
- RLC r8(?):
- RRC r8(?):
- RL r8(?):
- RR r8(?):
- SLA r8(?):
- SRA r8(?):
- SWAP r8(?):
- SRL r8(?):
- BIT b3, r8(?):
- RES b3, r8(?):
- SET b3, r8(?):


## All Ops:

- ALU: ADD, A <- A + A 
- ALU: ADD, A <- A + B 
- ALU: ADD, A <- A + C 
- ALU: ADD, A <- A + D 
- ALU: ADD, A <- A + E 
- ALU: ADD, A <- A + H 
- ALU: ADD, A <- A + L 
- ALU: ADD, A <- A + Z 
- ALU: ADD, A <- A + adj (DAA) 
- ALU: ADD, H <- SPH +c adj (sign)
- ALU: ADD, L <- SPL + Z
- ALU: ADD, W <- SPH +c adj (sign)
- ALU: ADD, Z <- SPL + Z
- ALU: ADD, A <- A + 1 
- ALU: ADD, B <- B + 1 
- ALU: ADD, C <- C + 1 
- ALU: ADD, D <- D + 1 
- ALU: ADD, E <- E + 1 
- ALU: ADD, H <- H + 1 
- ALU: ADD, L <- L + 1 
- ALU: ADD, L <- Z + 1 
- ALU: ADD, H <- H +c B 
- ALU: ADD, H <- H +c D 
- ALU: ADD, H <- H +c H 
- ALU: ADD, H <- H +c SPH 
- ALU: ADD, L <- L + C 
- ALU: ADD, L <- L + E 
- ALU: ADD, L <- L + L 
- ALU: ADD, L <- L + SPL 
- ALU: ADC, A <- A +c A 
- ALU: ADC, A <- A +c B 
- ALU: ADC, A <- A +c C 
- ALU: ADC, A <- A +c D 
- ALU: ADC, A <- A +c E 
- ALU: ADC, A <- A +c H 
- ALU: ADC, A <- A +c L 
- ALU: ADC, A <- A +c Z 
- ALU: AND, A <- A & A 
- ALU: AND, A <- A & B 
- ALU: AND, A <- A & C 
- ALU: AND, A <- A & D 
- ALU: AND, A <- A & E 
- ALU: AND, A <- A & H 
- ALU: AND, A <- A & L 
- ALU: AND, A <- A & Z 
- ALU: ASSIGN, a <- a
- ALU: ASSIGN, a <- b
- ALU: ASSIGN, a <- c
- ALU: ASSIGN, a <- d
- ALU: ASSIGN, a <- e
- ALU: ASSIGN, a <- h
- ALU: ASSIGN, a <- l
- ALU: ASSIGN, b <- a
- ALU: ASSIGN, b <- b
- ALU: ASSIGN, b <- c
- ALU: ASSIGN, b <- d
- ALU: ASSIGN, b <- e
- ALU: ASSIGN, b <- h
- ALU: ASSIGN, b <- l
- ALU: ASSIGN, c <- a
- ALU: ASSIGN, c <- b
- ALU: ASSIGN, c <- c
- ALU: ASSIGN, c <- d
- ALU: ASSIGN, c <- e
- ALU: ASSIGN, c <- h
- ALU: ASSIGN, c <- l
- ALU: ASSIGN, d <- a
- ALU: ASSIGN, d <- b
- ALU: ASSIGN, d <- c
- ALU: ASSIGN, d <- d
- ALU: ASSIGN, d <- e
- ALU: ASSIGN, d <- h
- ALU: ASSIGN, d <- l
- ALU: ASSIGN, e <- a
- ALU: ASSIGN, e <- b
- ALU: ASSIGN, e <- c
- ALU: ASSIGN, e <- d
- ALU: ASSIGN, e <- e
- ALU: ASSIGN, e <- h
- ALU: ASSIGN, e <- l
- ALU: ASSIGN, h <- a
- ALU: ASSIGN, h <- b
- ALU: ASSIGN, h <- c
- ALU: ASSIGN, h <- d
- ALU: ASSIGN, h <- e
- ALU: ASSIGN, h <- h
- ALU: ASSIGN, h <- l
- ALU: ASSIGN, l <- a
- ALU: ASSIGN, l <- b
- ALU: ASSIGN, l <- c
- ALU: ASSIGN, l <- d
- ALU: ASSIGN, l <- e
- ALU: ASSIGN, l <- h
- ALU: ASSIGN, l <- l
- ALU: ASSIGN, a <- z
- ALU: ASSIGN, b <- z
- ALU: ASSIGN, c <- z
- ALU: ASSIGN, d <- z
- ALU: ASSIGN, e <- z
- ALU: ASSIGN, h <- z
- ALU: ASSIGN, l <- z
- ALU: ASSIGN, cf <- 1
- ALU: BIT, bit b, r 
    => 64 
- ALU: BIT, set b, r 
    => 64 
- ALU: BIT, res b, r 
    => 64 
- ALU: NOT, cf <- !cf
- ALU: NOT, A <- !A
- ALU: OR, A <- A | A 
- ALU: OR, A <- A | B
- ALU: OR, A <- A | C 
- ALU: OR, A <- A | D 
- ALU: OR, A <- A | E 
- ALU: OR, A <- A | H 
- ALU: OR, A <- A | L 
- ALU: OR, A <- A | Z 
- ALU: RL, A <- rl A
- ALU: RL, B <- rl B
- ALU: RL, C <- rl C
- ALU: RL, D <- rl D
- ALU: RL, E <- rl E
- ALU: RL, H <- rl H
- ALU: RL, L <- rl L
- ALU: RL, Z <- rl Z
- ALU: RLC, A <- rlc A
- ALU: RLC, B <- rlc B
- ALU: RLC, C <- rlc C
- ALU: RLC, D <- rlc D
- ALU: RLC, E <- rlc E
- ALU: RLC, H <- rlc H
- ALU: RLC, L <- rlc L
- ALU: RLC, Z <- rlc Z
- ALU: RRC, A <- rrc A
- ALU: RRC, B <- rrc B
- ALU: RRC, C <- rrc C
- ALU: RRC, D <- rrc D
- ALU: RRC, E <- rrc E
- ALU: RRC, H <- rrc H
- ALU: RRC, L <- rrc L
- ALU: RRC, Z <- rrc Z
- ALU: RR, A <- rr A
- ALU: RR, B <- rr B
- ALU: RR, C <- rr C
- ALU: RR, D <- rr D
- ALU: RR, E <- rr E
- ALU: RR, H <- rr H
- ALU: RR, L <- rr L
- ALU: RR, Z <- rr Z
- ALU: SLA, A <- sla A
- ALU: SLA, B <- sla B
- ALU: SLA, C <- sla C
- ALU: SLA, D <- sla D
- ALU: SLA, E <- sla E
- ALU: SLA, H <- sla H
- ALU: SLA, L <- sla L
- ALU: SLA, Z <- sla Z
- ALU: SRA, A <- sra A
- ALU: SRA, B <- sra B
- ALU: SRA, C <- sra C
- ALU: SRA, D <- sra D
- ALU: SRA, E <- sra E
- ALU: SRA, H <- sra H
- ALU: SRA, L <- sra L
- ALU: SRA, Z <- sra Z
- ALU: SRL, A <- srl A
- ALU: SRL, B <- srl B
- ALU: SRL, C <- srl C
- ALU: SRL, D <- srl D
- ALU: SRL, E <- srl E
- ALU: SRL, H <- srl H
- ALU: SRL, L <- srl L
- ALU: SRL, Z <- srl Z
- ALU: SUB, A <- A - A, (CP = SUB r with no Output)
- ALU: SUB, A <- A - B, (CP = SUB r with no Output)
- ALU: SUB, A <- A - C, (CP = SUB r with no Output)
- ALU: SUB, A <- A - D, (CP = SUB r with no Output)
- ALU: SUB, A <- A - E, (CP = SUB r with no Output)
- ALU: SUB, A <- A - H, (CP = SUB r with no Output)
- ALU: SUB, A <- A - L, (CP = SUB r with no Output)
- ALU: SUB, A <- A - Z, (CP = SUB r with no Output)
- ALU: SUB, A <- A - 1 
- ALU: SUB, B <- B - 1 
- ALU: SUB, C <- C - 1 
- ALU: SUB, D <- D - 1 
- ALU: SUB, E <- E - 1 
- ALU: SUB, H <- H - 1 
- ALU: SUB, L <- L - 1 
- ALU: SUB, L <- Z - 1 
- ALU: SWAP, A <- swap A
- ALU: SWAP, B <- swap B
- ALU: SWAP, C <- swap C
- ALU: SWAP, D <- swap D
- ALU: SWAP, E <- swap E
- ALU: SWAP, H <- swap H
- ALU: SWAP, L <- swap L
- ALU: SWAP, Z <- swap Z
- ALU: SBC, A <- A -c A 
- ALU: SBC, A <- A -c B 
- ALU: SBC, A <- A -c C 
- ALU: SBC, A <- A -c D 
- ALU: SBC, A <- A -c E 
- ALU: SBC, A <- A -c H 
- ALU: SBC, A <- A -c L 
- ALU: SBC, A <- A -c Z 
- ALU: XOR, A <- A ^ A 
- ALU: XOR, A <- A ^ B
- ALU: XOR, A <- A ^ C 
- ALU: XOR, A <- A ^ D 
- ALU: XOR, A <- A ^ E 
- ALU: XOR, A <- A ^ H 
- ALU: XOR, A <- A ^ L 
- ALU: XOR, A <- A ^ Z 
- ADDR: 0xFF00+C
- ADDR: 0xFF00+Z
- ADDR: BC
- ADDR: DE
- ADDR: HL
- ADDR: SP
- ADDR: PC
- ADDR: WZ
- IDU: IDU+, WZ <- IDU
- IDU: IDU+, PC <- IDU
- IDU: IDU+, HL <- IDU
- IDU: IDU-, HL <- IDU
- IDU: IDU+, SP <- IDU
- IDU: IDU-, SP <- IDU
- IDU: IDU+, BC <- IDU
- IDU: IDU-, BC <- IDU
- IDU: IDU+, DE <- IDU
- IDU: IDU-, DE <- IDU
- IDU: IDU-Assign, SP <- IDU
- DBUS: Register, IR <- Mem
- DBUS: Register, W <- Mem
- DBUS: Register, Z <- Mem
- DBUS: Mem <- ALU
- DBUS: Mem <- Register, A
- DBUS: Mem <- Register, B
- DBUS: Mem <- Register, C
- DBUS: Mem <- Register, D
- DBUS: Mem <- Register, E
- DBUS: Mem <- Register, H
- DBUS: Mem <- Register, L
- DBUS: Mem <- Register, Z
- DBUS: Mem <- Register, SPL
- DBUS: Mem <- Register, SPH
- MISC: BC <- WZ
- MISC: DE <- WZ
- MISC: HL <- WZ
- MISC: SP <- WZ
- MISC: PC <- WZ
- MISC: cc check

Next: p.114 JRe
=> We need two bytes for encoding, unless we can express one with the other and save some uOps.
