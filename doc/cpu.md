
# Testing 
- You can dump the entire register set (12 Bytes) for all possible instructions (512).
- You could write a program that runs test instructions and dumps the results + registers into a certain region of memory.
- You can then run this testcode once on a known good emulator (or multiple?) and get a memory dump from that.
- You can then use the output and compare that to my cpu.
- If I structure it correctly i should be able to find differences in the resulting memory and use a structure to know which instruction did create a diff.
- you can use 128Bytes per Instruction.
