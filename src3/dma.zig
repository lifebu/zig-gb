const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

pub const State = struct {
    dma: u8 = 0,

    // TODO: Try to simplify all the state of dma. Maybe a microcode machine?
    is_running: bool = false,
    start_addr: u16 = 0x0000,
    offset: u16 = 0,
    counter: u3 = 0,

    byte: u8 = 0,
    is_read: bool = false,
};

pub fn init(state: *State) void {
    state.* = .{};
}

pub fn cycle(state: *State, req: *def.Request) void {
    if(!state.is_running) {
        return;
    }

    // DMA Bus conflict.
    if(req.address < mem_map.hram_low or req.address > mem_map.hram_high) {
        req.reject(); // DMA Bus conflict
    }
    
    state.counter, const overflow = @subWithOverflow(state.counter, 1);
    if(overflow == 0) {
        return;
    }
    // read: 2 cycles, write: 2 cycles => 4 cycles per byte.
    state.counter = 1;

    if(state.is_read) {
        const source_addr: u16 = state.start_addr + state.offset;
        req.* = .{ .address = source_addr, .value = .{ .read = &state.byte } };
    } else {
        const dest_addr: u16 = mem_map.oam_low + state.offset;
        req.* = .{ .address = dest_addr, .value = .{ .write = state.byte } };

        state.offset += 1;
        state.is_running = (dest_addr + 1) < mem_map.oam_high;
    }
    state.is_read = !state.is_read;
}

pub fn request(state: *State, req: *def.Request) void {
    switch (req.address) {
        mem_map.dma => {
            req.apply(&state.dma);
            if(req.isWrite()) {
                state.is_running = true;
                state.start_addr = @as(u16, state.dma) << 8;
                state.offset = 0;
                state.counter = 5; // Nothing happens for the first 5 cycles.
                state.is_read = true;
            }
        },
        else => {},
    }
}
