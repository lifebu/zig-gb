const std = @import("std");
const build_options = @import("build_options");
const assert = std.debug.assert;
const tracy = @import("tracy");

const APU = @import("apu.zig");
const Config = @import("config.zig");
const Cart = @import("cart.zig");
const CPU = @import("cpu.zig");
const def = @import("defines.zig");
const Memory = @import("memory.zig");
const MMIO = @import("mmio.zig");
const PPU = @import("ppu.zig");
const PPUVoid = @import("ppu_void.zig");

const Self = @This();


apu: switch (build_options.apu_model) {
    .void => APU,
    .cycle => APU,
} = .{},
cart: Cart = .{},
cpu: switch (build_options.cpu_model) {
    .instruction => CPU,
    .cycle => CPU,
} = .{},
memory: Memory = .{},
ppu: switch(build_options.ppu_model) {
    .void => PPUVoid,
    .frame => PPU,
    .cycle => PPU,
} = .{},
mmio: MMIO = .{},


pub fn init(self: *Self, alloc: std.mem.Allocator, config: Config) void {
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

pub fn deinit(self: *Self, alloc: std.mem.Allocator, config: Config) void {
    self.cpu.deinit(alloc);

    assert(config.files.rom != null);
    self.cart.deinit(alloc, config.files.rom.?);
}

// TODO: Should you be able to run the core for a set of cycles instead of an entire frame? Maybe for debug purposes? (Like rendering?)
pub fn frame(self: *Self, input_state: def.InputState) void {
    const zone = tracy.Zone.begin(.{ .name = "frame", .src = @src(), .color = .alice_blue });
    defer zone.end();

    var irq_joypad: bool = self.mmio.updateInputState(&input_state);

    var cycle_count: u32 = 0;
    while(cycle_count <= def.t_cycles_per_frame) : (cycle_count += 1) {
        var request: def.Request = .{};
        self.cpu.cycle(&request);
        self.cpu.request(&request);
        self.memory.cycle(&request);
        
        self.memory.request(&request);
        self.cart.request(&request);
        self.mmio.request(&request);
        self.apu.request(&request);
        self.ppu.request(&request);

        const irq_serial, const irq_timer = self.mmio.cycle();
        const irq_vblank, const irq_stat = self.ppu.cycle();
        self.apu.cycle();

        self.cpu.pushInterrupts(irq_vblank, irq_stat, irq_timer, irq_serial, irq_joypad);
        irq_joypad = false; // TODO: Not the nicest, okay for now.
        request.logAndReject();
    }
}
