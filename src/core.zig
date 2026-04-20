const std = @import("std");
const assert = std.debug.assert;
const tracy = @import("tracy");

const CPU = @import("cpu.zig");
const Cart = @import("cart.zig");
const Config = @import("config.zig");
const MMIO = @import("mmio.zig");
const Memory = @import("memory.zig");
const def = @import("defines.zig");

pub fn Core(apu_type: type, ppu_type: type) type {
    return struct {
        const Self = @This();

        apu: apu_type = .empty,
        cart: Cart = .{},
        cpu: CPU = .{},
        memory: Memory = .{},
        ppu: ppu_type = .empty,
        mmio: MMIO = .{},

        pub fn init(self: *Self, io: std.Io, alloc: std.mem.Allocator, config: Config) void {
            self.* = .{};
            self.apu.init(config.emulation.apu_plugin);
            self.cart.init();
            self.cpu.init(alloc, config.emulation.skip_boot_rom);
            self.memory.init(config.emulation.model, config.emulation.skip_boot_rom);
            self.ppu.init(config.emulation.ppu_plugin);
            self.mmio.init();

            assert(config.files.rom != null);
            self.cart.loadFile(io, alloc, config.files.rom.?, config.debug.disable_saves);
        }

        pub fn deinit(self: *Self, io: std.Io, alloc: std.mem.Allocator, config: Config) void {
            self.cpu.deinit(alloc);

            assert(config.files.rom != null);
            self.cart.deinit(io, alloc, config.files.rom.?, config.debug.disable_saves);
        }

        pub fn frame(self: *Self, input_state: def.InputState) void {
            const zone = tracy.Zone.begin(.{ .name = "frame", .src = @src(), .color = .alice_blue });
            defer zone.end();

            var irq_joypad: bool = self.mmio.updateInputState(&input_state);

            var cycle_count: u32 = 0;
            while(cycle_count <= def.t_cycles_per_frame) : (cycle_count += 1) {
                self.cyle(&irq_joypad);
            }
        }

        pub fn cyle(self: *Self, irq_joypad: *bool) void {
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

            self.cpu.pushInterrupts(irq_vblank, irq_stat, irq_timer, irq_serial, irq_joypad.*);
            irq_joypad.* = false; // TODO: Not the nicest, okay for now.
            request.logAndReject();
        }
    };
}

