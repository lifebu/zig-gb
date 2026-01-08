const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

const work_ram_size = mem_map.wram_high - mem_map.wram_low;

pub const State = struct {
    // boot
    rom_enabled: bool = false,

    rom: [def.boot_rom_size]u8 = [1]u8{0} ** def.boot_rom_size,

    // dma
    // TODO: Try to simplify all the state of dma. Maybe a microcode machine?
    is_running: bool = false,
    start_addr: u16 = 0x0000,
    offset: u16 = 0,
    counter: u3 = 0,
    byte: u8 = 0,
    is_read: bool = false,

    dma: u8 = 0,

    // mmu
    // TODO: remove this giant memory block.
    memory: [def.addr_space]u8 = .{0} ** def.addr_space,

    // wram
    work_ram: [work_ram_size]u8 = .{0} ** work_ram_size,
};

pub fn init(state: *State) void {
    state.* = .{};

    // TODO: Which boot rom to use should be an option.
    // TODO: Not hard-coded relative paths like this?
    const file = std.fs.cwd().openFile("data/bootroms/dmg_boot.bin", .{}) catch unreachable;
    const len = file.readAll(&state.rom) catch unreachable;
    std.debug.assert(len == state.rom.len);
    state.rom_enabled = true;
}

pub fn cycle(state: *State, req: *def.Request) void {
    cycleDMA(state, req);
}

fn cycleDMA(state: *State, req: *def.Request) void {
    // TODO: Clean this code up.
    if(!state.is_running) {
        return;
    }

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
        req.* = .{ .requestor = .dma, .address = source_addr, .value = .{ .read = &state.byte } };
    } else {
        const dest_addr: u16 = mem_map.oam_low + state.offset;
        req.* = .{ .requestor = .dma, .address = dest_addr, .value = .{ .write = state.byte } };

        state.offset += 1;
        state.is_running = (dest_addr + 1) < mem_map.oam_high;
    }
    state.is_read = !state.is_read;
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
                state.is_running = true;
                state.start_addr = @as(u16, state.dma) << 8;
                state.offset = 0;
                state.counter = 5; // Nothing happens for the first 5 cycles.
                state.is_read = true;
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
        else => {
            // TODO: Move that to def.Request.
            // if (req.isValid()) std.log.warn("r/w lost: {f}", .{ req });
            // req.reject();
        },
    }
}
