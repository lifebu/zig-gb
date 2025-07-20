const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");
// TODO: Remove that dependency.
const MMU = @import("mmu.zig");

pub const State = struct {
    is_running: bool = false,
    start_addr: u16 = 0x0000,
    offset: u16 = 0,
    counter: u3 = 0,
};

pub fn init(_: *State) void {
}

pub fn cycle(state: *State, mmu: *MMU.State, request: *def.MemoryRequest) void {
    // TODO: Need a better way to communicate memory ready and requests so that other systems like the dma don't need to know the mmu.
    // And split the on-write behavior and memory request handling from the cycle function?
    if(request.write) |address| {
        if(address == mem_map.dma) {
            state.is_running = true;
            state.start_addr = @as(u16, request.data.*) << 8;
            state.offset = 0;
            state.counter = 0;

            mmu.memory[address] = request.data.*;
            request.write = null;
            // TODO: While it is running I need to implement the bus conflict behavior for the cpu, 
            // the cpu will not be able to write and when it reads it will read the current byte of the dma transfer.
        }
    }

    // Maybe I can use a small uop machine for the dma so that I don't need so many if conditions everywhere?
    if(state.is_running) {
        // first time we overflow after 8 cycles for first write.
        state.counter, const overflow = @addWithOverflow(state.counter, 1);
        if(overflow == 0) {
            return;
        }

        // Setting to 4 means that after the first time, we overflow every 4 cycles.
        // TODO: Using an actual uop machine means that the overflow timins are implicit.
        state.counter = 4;
        const source_addr: u16 = state.start_addr + state.offset;
        const dest_addr: u16 = mem_map.oam_low + state.offset;
        const data: u8 = mmu.memory[source_addr];
        mmu.memory[dest_addr] = data;

        state.offset += 1;
        state.is_running = (dest_addr + 1) < mem_map.oam_high;
    }
}
