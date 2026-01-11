const std = @import("std");
const build_options = @import("build_options");
const assert = std.debug.assert;

const APU = @import("apu.zig");
const Config = @import("config.zig");
const Cart = @import("cart.zig");
const CPU = @import("cpu.zig");
const def = @import("defines.zig");
const Memory = @import("memory.zig");
const MMIO = @import("mmio.zig");
const PPU = @import("ppu.zig");

const Self = @This();


apu: switch (build_options.apu_model) {
    .void => APU,
    .cycle => APU,
} = .{},
cart: Cart = .{},
cpu: CPU = .{},
memory: Memory = .{},
ppu: switch(build_options.ppu_model) {
    .void => PPU,
    .frame => PPU,
    .cycle => PPU,
} = .{},
mmio: MMIO = .{},


pub fn init(self: *Self, config: Config, alloc: std.mem.Allocator) void {
    self.* = .{};
    self.apu.init();
    self.cart.init();
    self.cpu.init(alloc);
    self.memory.init(config.emulation.model);
    self.ppu.init();
    self.mmio.init();

    assert(config.files.rom != null);
    self.cart.loadFile(config.files.rom.?, alloc);
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.cpu.deinit(alloc);
    self.cart.deinit(alloc);
}

// TODO: Should you be able to run the core for a set of cycles instead of an entire frame? Maybe for debug purposes? (Like rendering?)
pub fn frame(self: *Self, input_state: def.InputState) void {
    var irq_joypad: bool = self.mmio.updateInputState(&input_state);
    // Note: GB runs at 59.73Hz. This software runs at 60Hz.
    // TODO: It would be better to just let the system run to the end of the next vblank. How to do that when the PPU is disabled?
    const cycles_per_frame = 70224; 
    for(0..cycles_per_frame) |_| {
        var request: def.Request = .{};
        self.cpu.cycle(&request);
        self.cpu.request(&request);
        self.memory.cycle(&request);
        
        self.memory.request(&request);
        self.cart.request(&request);
        self.mmio.request(&request);
        self.apu.request(&request);
        self.ppu.request(&self.memory.memory, &request);

        const irq_serial, const irq_timer = self.mmio.cycle();
        const irq_vblank, const irq_stat = self.ppu.cycle(&self.memory.memory);
        self.apu.cycle();

        self.cpu.pushInterrupts(irq_vblank, irq_stat, irq_timer, irq_serial, irq_joypad);
        irq_joypad = false; // TODO: Not the nicest, okay for now.
        request.logAndReject();
    }
}
