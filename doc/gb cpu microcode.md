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
	- Put data from alu onto register file: (R--).
	- Put data from alu onto data bus: (-W-).
	- put data from data bus onto alu input: (RW-).
- null for address or data: bus is electrically disconnect.
	=> for convenience the single step test re-uses the last address generated.

# Idea:
- CPU uops @4MHz => CPU is clocked like rest of system.
- the ppu FIFO Pixel fetcher can work the same way.
- ~512 instructions, 74 instruction families:
	- 26 ALU-OPS + ALU_SET_INPUT + 6 (NOP, STOP, HALT, SET_ADDR+IDU, DECORE, SET_DBUS) + >= 4 (MISC uOPS)
	=> ~37 uOps => 50% of instructions families (73).
- Define one pseudo 16-bit register WZ for temporary results.
- gekkio: Gameboy technical reference:
	https://gekkio.fi/files/gb-docs/gbctr.pdf
    - They use ALU op and Misc op. They can never happen at same time.
    => T-Cycles: Addr bus, Data bus, IDU Op, (ALU Op or Misc Op).
- End all microcode with DECORE uop.
    => So that the next instructions will automatically be fetched.
- Use uOp families:
    - SET_ADDR encodes source address to use like:
    - BC, DE, HL, PC, SP, 0xFF00 + Z, 0xFF00 + C.
- For everything we need more than 256 combinations from on byte.
    => Split into execution units?
    - So that each unit can do stuff in parallel to other units?
    - Like taking a cycle to set the IDU does not impede the ALU from setting up?

# Open Topics:
- How does interrupt handling work?
    - When we start a new M-Cycle, the cpu checks the interrupt signal line.
    - If all conditions are met, the uOps fifo is cleared and replaced with the uOps of the corresponding interrupt handler.
        => Note: clearing the fifo removes the instruction we already decoded. 
        If the interrupt handler saves PC, this should be fine.
    - We can also implement the interrupt handler as instructions instead of uops (this needs decoding).
    - PC needs to be restored later, so we need to save it.
    - So for the CPU, the interrupt handler is just like normal code.
- How do we allow/disallow memory access to u8/u16 via the MMU?
- How do we write back data we requested from memory into the register file?
    - Example: We requested an address and the mmu has given us a result.
    - When do we check this? We can check this in SET_ADDR, because it is always the first instruction in each M-Cycle.
        => If this is not guaranteed, we can add an WRITE_BACK uop to fill this position.
- How do other subsystems react to writes from the CPU? (OnWrite Behaviour).
    - Maybe if we have a globally accessible nullable pin-set of the cpu?
    - THe other subsystems can each tick check if we have a pin-set and react to it?
    - The current visible pin-set is saved in the MMU, so that other systems can react.
    - The cpu requests that memory will be changed.
    - Every subsystem can check if they allow it. If not, they remove the request from the mmu.
    - The mmu is the last in the line and if no one has objected so far, it will apply the request.
    - Instead of using a nullable pin-set we can use a default value that always succeeds.
        - A read request on an address the cpu has always access to?
- How exactly do UOps Parameter work?
    => Does this mean we don't decode variants, but we cast parameters?
- How does Stop/Halt work?
- How can we create a simple system to update the flag register?
    - A lot of ALU Ops change them almost the same.
- How to write the tests?
    https://github.com/floooh/chipz/blob/main/tests/z80ctc.test.zig
- How does the cc check work?
    - The uop table has the set of instructions if the check succeeds.
    - When the check fails, the rest of the uops are discarded and we decode a nop instruction.

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
- ALU/MISC: Both Inputs, Function, Misc functions

## Timing:
0: ADDR + IDU 
1: DBUS
2: ALU/MISC
3: DECODE + PUSH_PINS

## NOP
## STOP and HALT
## ALU uOps (26):
Op-Byte:
    - INC, DEC, RLC, RRC, RL, RR, SL, SR, SWAP, SRL, 
    - ADJ (DAA-Adjust), NOT, SCF, CCF, ASSIGN (ld r,r), ADD, ADC, SUB, SBC, AND, 
    - XOR, OR, CP, BIT, RES, SET.
        26 => 5-bits 
Parameters:
    ALU Inputs:
    - 8bit register: A, B, C, D, E, H, L, W, Z, SPL, SPH,
        => Do we define each input individually?
        - 11 => 4-bits per inputs.
    => 13 bits.
## SET_ADDR + IDU
- SP, PC, HL, BC, DE, WZ (fake), 0xFF00+C, 0xFF00+Z, (PCH?)
    => 3 bits
    IDU:
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
- IR or Interrupt (Check Pins).
## Misc
- Write-back WZ (3): r16 <- WZ, SP <- WZ, PC <- WZ
- Conditional Check (?): cc
- Change IME (2): IME <- 1, IME <- 0, (1 bit)
- SetPC (restart) (1): PC <- restart-addr
## PUSH_PINS
- The last step each 4-cycle interval is to set the output pins (DBUS, ADDR) so that mmu can update values.
- This swaps the pins. The cpu has an internal pin-set that is switched in that cycle.
- MMU only applies the request once.
- (Still unsure how that works).


# Instruction Family Implementations:
## Explaination
- Instruction (NumBytes NumCycles): uOps
	- Between M-Cycles: the state from the last M-cycle on the memory bus.

https://gekkio.fi/files/gb-docs/gbctr.pdf
https://github.com/SingleStepTests/sm83

## Instructions:
- FETCH(~ 4): SET_ADDR, IDU+, NOP, NOP
- NOP(1 4): SET_ADDR & IDU+, SET_DBUS, NOP, DECODE+PUSH_PINS
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
