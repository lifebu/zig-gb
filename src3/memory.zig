const std = @import("std");
const assert = std.debug.assert;

const def = @import("defines.zig");
const Fifo = @import("util/fifo.zig");
const mem_map = @import("mem_map.zig");

const oam_size = mem_map.oam_high - mem_map.oam_low;
const work_ram_size = mem_map.wram_high - mem_map.wram_low;

const DmaMicroOp = enum { nop, read, write };
const DmaFifo = Fifo.RingbufferFifo(DmaMicroOp, 8);
const dma_start: [4]DmaMicroOp = .{ .nop, .nop, .nop, .nop };
const dma_step: [4]DmaMicroOp = .{ .nop, .read, .nop, .write };

pub const State = struct {
    // boot
    rom_enabled: bool = true,

    rom: [def.boot_rom_size]u8 = @splat(0),

    // dma
    dma_fifo: DmaFifo = .{}, 
    src_addr: u16 = 0x000,
    dest_addr: u16 = 0x000,
    dest_limit: u16 = 0x000,
    byte: u8 = 0,

    dma: u8 = 0,

    // mmu
    // TODO: remove this giant memory block.
    memory: [def.addr_space]u8 = @splat(0),

    // wram
    work_ram: [work_ram_size]u8 = @splat(0),
};

pub fn init(state: *State, path: []const u8) void {
    state.* = .{};

    const file = std.fs.cwd().openFile(path, .{}) catch unreachable;
    const len = file.readAll(&state.rom) catch unreachable;
    std.debug.assert(len == state.rom.len);
}

pub fn cycle(state: *State, req: *def.Request) void {
    cycleDMA(state, req);
}

fn cycleDMA(state: *State, req: *def.Request) void {
    const uop = state.dma_fifo.readItem() orelse return;
    if(req.address < mem_map.hram_low or req.address > (mem_map.hram_high) - 1) {
        req.reject(); // DMA Bus conflict
    }

    switch(uop) {
        .nop => {},
        .read => {
            req.* = .{ .requestor = .dma, .address = state.src_addr, .value = .{ .read = &state.byte } };
            state.src_addr += 1;
        },
        .write => {
            req.* = .{ .requestor = .dma, .address = state.dest_addr, .value = .{ .write = state.byte } };
            state.dest_addr += 1;

            assert(state.dma_fifo.isEmpty());
            if(state.dest_addr <= state.dest_limit) {
                state.dma_fifo.write(&dma_step);
            }
        },
    }
}

pub fn request(state: *State, req: *def.Request) void {
    switch (req.address) {
        0...(def.boot_rom_size - 1) => {
            if(!state.rom_enabled) {
                return;
            }
            if(req.isWrite()) {
                req.reject();
            } else {
                const rom_idx: u16 = req.address - 0;
                req.apply(&state.rom[rom_idx]);
            }
        },
        mem_map.wram_low...(mem_map.wram_high - 1) => {
            const wram_idx: u16 = req.address - mem_map.wram_low;
            req.apply(&state.work_ram[wram_idx]);
        },
        mem_map.echo_low...(mem_map.echo_high - 1) => {
            const wram_idx: u16 = req.address - mem_map.echo_low;
            req.apply(&state.work_ram[wram_idx]);
        },
        mem_map.dma => {
            req.apply(&state.dma);
            if(req.isWrite()) {
                state.src_addr = @as(u16, state.dma) << 8;
                state.dest_addr = mem_map.oam_low;
                state.dest_limit = mem_map.oam_high - 1;
                state.dma_fifo.write(&dma_start);
                state.dma_fifo.write(&dma_step);
            }
        },
        mem_map.boot_rom => {
            if(!state.rom_enabled) {
                return;
            }
            if(req.isWrite()) {
                state.rom_enabled = false;
            }
            req.reject(); // TODO: Should subsequent reads be able to read this?
        },
        mem_map.unused_low...(mem_map.unused_high - 1) => {
            req.reject();
        },
        else => {},
    }
}
