const std = @import("std");
const assert = std.debug.assert;

const def = @import("defines.zig");
const Fifo = @import("util/fifo.zig");

const Self = @This();

const dmg_rom: *const[def.boot_rom_size:0]u8 = @embedFile("bootroms/dmg_boot.bin");
const work_ram_size = def.wram_high - def.wram_low;

pub const BootRom = packed struct(u8) {
    finished: bool = false, _: u7 = 0,
};

const DmaMicroOp = enum { nop, bus_conflict, read, write };
const DmaFifo = Fifo.RingbufferFifo(DmaMicroOp, 8);
const dma_start: [4]DmaMicroOp = .{ .nop, .nop, .nop, .nop };
const dma_step: [4]DmaMicroOp = .{ .bus_conflict, .read, .bus_conflict, .write };

// boot
boot: BootRom = .{},
boot_rom: [def.boot_rom_size]u8 = @splat(0),

// dma
dma_fifo: DmaFifo = .{}, 
src_addr: u16 = 0x000,
dest_addr: u16 = 0x000,
dest_limit: u16 = 0x000,
byte: u8 = 0,

dma: u8 = 0,

// wram
work_ram: [work_ram_size]u8 = @splat(0),


pub fn init(self: *Self, model: def.GBModel, skip_boot_rom: bool) void {
    self.* = .{};
    self.boot.finished = skip_boot_rom;
    switch (model) {
        .dmg => self.boot_rom = dmg_rom.*,
    }
}

pub fn cycle(self: *Self, req: *def.Request) void {
    cycleDMA(self, req);
}

fn cycleDMA(self: *Self, req: *def.Request) void {
    const uop = self.dma_fifo.readItem() orelse return;
    switch(uop) {
        .nop => {},
        .bus_conflict => {
            dmaBusConflict(req);
        },
        .read => {
            dmaBusConflict(req);
            req.* = .{ .requestor = .dma, .address = self.src_addr, .value = .{ .read = &self.byte } };
            self.src_addr += 1;
        },
        .write => {
            dmaBusConflict(req);
            req.* = .{ .requestor = .dma, .address = self.dest_addr, .value = .{ .write = self.byte } };
            self.dest_addr += 1;

            assert(self.dma_fifo.isEmpty());
            if(self.dest_addr <= self.dest_limit) {
                self.dma_fifo.write(&dma_step);
            }
        },
    }
}

fn dmaBusConflict(req: *def.Request) void {
    if(req.address < def.hram_low or req.address > (def.hram_high) - 1) {
        req.reject(); // DMA Bus conflict
    }
}

pub fn request(self: *Self, req: *def.Request) void {
    switch (req.address) {
        0...(def.boot_rom_size - 1) => {
            if(!self.boot.finished) {
                const rom_idx: u16 = req.address - 0;
                req.applyAllowedRW(&self.boot_rom[rom_idx], 0xFF, 0x00);
            }
        },
        def.wram_low...(def.wram_high - 1) => {
            const wram_idx: u16 = req.address - def.wram_low;
            req.apply(&self.work_ram[wram_idx]);
        },
        def.echo_low...(def.echo_high - 1) => {
            const wram_idx: u16 = req.address - def.echo_low;
            req.apply(&self.work_ram[wram_idx]);
        },
        def.dma => {
            req.apply(&self.dma);
            if(req.isWrite()) {
                self.src_addr = @as(u16, self.dma) << 8;
                self.dest_addr = def.oam_low;
                self.dest_limit = def.oam_high - 1;
                self.dma_fifo.write(&dma_start);
                self.dma_fifo.write(&dma_step);
            }
        },
        def.boot_rom => {
            const mask_write: u8 = if(self.boot.finished) 0x00 else 0x01;
            req.applyAllowedRW(&self.boot, 0x01, mask_write);
        },
        def.unused_low...(def.unused_high - 1) => {
            req.reject();
        },
        else => {},
    }
}
