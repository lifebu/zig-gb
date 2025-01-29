#CPU Model:
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

#Timing:
- CPU can only do one memory access per M-cycle
- CPU cannot use the data during the same M-cycle.
- One M-cycle for fetch, at least one M-cycle for execute.
- Fetch overlaps with last machine cycle of last instruction.
	=> Only that fetch can do memory access, not the execution.
- For Programmers: In practice think of a program as a sequence of non-overlapping instructions.

#SingleStepTests:
- 8-bit data pins, 16-bit address pins, (RWM)-pins: read, write, memory-request.
- RWM: They control the following cases:
	- Put data from register file onto data bus. (-WM).
	- Put data from data bus onto register file. (R-M).
	- Put data from alu onto register file: (-W-).
	- Put data from alu onto data bus: (???).
	- put data from data bus onto alu input: (???).
- null for address or data: bus is electrically disconnect.
	=> for convenience the single step test re-uses the last address generated.

#Idea:
- create uops to compose other operations of.
- so that the cpu can be ticket in 4MHz cycles.
- cpu reads a uops list. fetcher has it's own uops list.
- fetcher puts uops into cpu and itself (so that it keeps running).
- the ppu FIFO Pixel fetcher can work the same way.
	- It has 6 different uops.
	- but it's "program" is hardcoded!
- the CPU has 74 instruction families, can we have less uOps then that?
	- 26 ALU-OPS + 5 (NOP, SET_ADDR, DECORE_IR, IDU, SET_DBUS) + >= 4 (MISC uOPS)
	=> ~35 uOps => 47% of instructions families.
- We can define extra pseudo-registers to safe values in.
	- ADD, A, imm8:
		- Load imm8 into register Z.
		- LU: Add Z and a and assign to A.
	- WZ is another set of fake register!
- Maybe we have an IDU and ALU unit?
- gekkio: Gameboy technical reference:
	https://gekkio.fi/files/gb-docs/gbctr.pdf
	- For each of the instructions they define ALU op and a Misc op.
	- ALU op and Misc op can never happen at the same M-Cycle.
	- So you could define each T-Cycle as:
		- Change Addr bus.
		- Change Data bus.
		- Change IDU Op.
		- Change ALU Op and Operands OR Do Misc op.
		=> That might just be some structure, but is not required.
- Maybe we define uOps families similar to the instruction families?
	- Example: Setting the Address bus.
		- one uOps Family: SET_ADDR addr_src.
		- where addr_src can either be: BC, DE, HL, PC, SP, 0xFF00 + Z, 0xFF00 + C.
	- OR: we need operands for uops.
		- IDU+ might need to know where to put the result?
	- This would mean we have a static 512-element array that has the uop programms for each instrucion.
	- The uops programs are opcodes themselves that get decoded to have uops families?
- All ALU uOps:
	- INC, DEC, RLC, RRC, RL, RR, SL, SR, SWAP, SRL, 
	- ADJ (DAA-Adjust), NOT, SCF, CCF, ASSIGN (ld r,r), ADD, ADC, SUB, SBC, AND, 
	- XOR, OR, CP, BIT, RES, SET.
		=> 26 different operations.
		=> To decode this you need 5 bits.
		=> But also more to decode the possible inputs/outputs.
		=> Therefore try to encode inputs/outputs not operations!
	- Is something like RR and RRC the same bust just the carry is different?
		- So that one uop does RR. The other uops does the carry?
		=> RRA = RR, NOP
		=> RRC = RR, RRC?
- All Misc uOps:
	- Write-back WZ (3): r16 <- WZ, SP <- WZ, PC <- WZ
	- Conditional Check (?): cc
	- Change IME (2): IME <- 1, IME <- 0, (1 bit)
	- SetPC (restart) (1): PC <- restart-addr

#uOps:
- 1: NOP: Nothing.
- 2: SET_ADDR: Set address bus + RWM_PINS.
	- This needs two inputs: low 8-bit and high 8-bit.
	- The following can be on the Address bus:
	- SP, PC, HL, BC, DE, WZ (fake), 0xFF00+C, 0xFF00+Z, (PCH?)
		=> (3 bits)
	=> Define uops family!
	- And we can specify read, write, disconnect (2 bits).
		=> unsure if this is part of SET_ADD uop, or if we split setting RWM.
		=> RWM is mabye only relevant for setting the databus.
		=> Setting Databuse can also be used for ALU output, so splitting it makes sense?
	=> Have one uop for setting data-bus:
		- 2 bits for read/write/memory and some more bits for possible connections (ALU-out, registers?).

- 3: DECODE-IR: Decode (put uops into cpu) and put into IR.
	=> Decodes either IR or the interrupt-handler!
- 4: IDU+: IDU increment.
	=> uop family => have one uop for IDU that uses a bit to say if it is IDU+ or IDU-
- 5: IDU-: IDU decrement.
- 6: ALU-IO: Set ALU inputs and outputs.
	=> Maybe not needed with uops families.
- 6: ALU-INC: ALU increment.
	=> Can this just be ALU-ADD? with 1 as the input?
	=> ALU-ADD changes carry, ALU-INC does not (maybe you have the same carry result?).
	=> Otherwise they are the same.
- 7: ALU-DEC: Alu decrement.
- 8: ALU-ADD: Alu add.

#Instruction Families:
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
