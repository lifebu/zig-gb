const std = @import("std");
const assert = std.debug.assert;

const def = @import("defines.zig");
const Fifo = @import("util/fifo.zig");
const mem_map = @import("mem_map.zig");

const Self = @This();

const dmg_rom: *const[256:0]u8 = @embedFile("bootroms/dmg_boot.bin");

const oam_size = mem_map.oam_high - mem_map.oam_low;
const work_ram_size = mem_map.wram_high - mem_map.wram_low;

const DmaMicroOp = enum { nop, read, write };
const DmaFifo = Fifo.RingbufferFifo(DmaMicroOp, 8);
const dma_start: [4]DmaMicroOp = .{ .nop, .nop, .nop, .nop };
const dma_step: [4]DmaMicroOp = .{ .nop, .read, .nop, .write };


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


pub fn init(self: *Self, model: def.GBModel) void {
    self.* = .{};
    switch (model) {
        .dmg => self.rom = dmg_rom.*,
    }
}

pub fn cycle(self: *Self, req: *def.Request) void {
    cycleDMA(self, req);
}

fn cycleDMA(self: *Self, req: *def.Request) void {
    const uop = self.dma_fifo.readItem() orelse return;
    if(req.address < mem_map.hram_low or req.address > (mem_map.hram_high) - 1) {
        req.reject(); // DMA Bus conflict
    }

    switch(uop) {
        .nop => {},
        .read => {
            req.* = .{ .requestor = .dma, .address = self.src_addr, .value = .{ .read = &self.byte } };
            self.src_addr += 1;
        },
        .write => {
            req.* = .{ .requestor = .dma, .address = self.dest_addr, .value = .{ .write = self.byte } };
            self.dest_addr += 1;

            assert(self.dma_fifo.isEmpty());
            if(self.dest_addr <= self.dest_limit) {
                self.dma_fifo.write(&dma_step);
            }
        },
    }
}

pub fn request(self: *Self, req: *def.Request) void {
    switch (req.address) {
        0...(def.boot_rom_size - 1) => {
            if(!self.rom_enabled) {
                return;
            }
            if(req.isWrite()) {
                req.reject();
            } else {
                const rom_idx: u16 = req.address - 0;
                req.apply(&self.rom[rom_idx]);
            }
        },
        mem_map.wram_low...(mem_map.wram_high - 1) => {
            const wram_idx: u16 = req.address - mem_map.wram_low;
            req.apply(&self.work_ram[wram_idx]);
        },
        mem_map.echo_low...(mem_map.echo_high - 1) => {
            const wram_idx: u16 = req.address - mem_map.echo_low;
            req.apply(&self.work_ram[wram_idx]);
        },
        mem_map.dma => {
            req.apply(&self.dma);
            if(req.isWrite()) {
                self.src_addr = @as(u16, self.dma) << 8;
                self.dest_addr = mem_map.oam_low;
                self.dest_limit = mem_map.oam_high - 1;
                self.dma_fifo.write(&dma_start);
                self.dma_fifo.write(&dma_step);
            }
        },
        mem_map.boot_rom => {
            if(!self.rom_enabled) {
                return;
            }
            if(req.isWrite()) {
                self.rom_enabled = false;
            }
            req.reject(); // TODO: Should subsequent reads be able to read this?
        },
        mem_map.unused_low...(mem_map.unused_high - 1) => {
            req.reject();
        },
        else => {},
    }
}
