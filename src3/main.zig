const std = @import("std");
const sokol = @import("sokol");

const APU = @import("apu.zig");
const Config = @import("config.zig");
const Cart = @import("cart.zig");
const CPU = @import("cpu.zig");
const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");
const Memory = @import("memory.zig");
const MMIO = @import("mmio.zig");
const PPU = @import("ppu.zig");
const Platform = @import("platform.zig");


const state = struct {
    var allocator: std.heap.GeneralPurposeAllocator(.{}) = undefined;
    var apu: APU = .{};
    var cart: Cart = .{};
    var config: Config = .default;
    var cpu: CPU = .{};
    var memory: Memory = .{};
    var platform: Platform = .{};
    var ppu: PPU = .{};
    var mmio: MMIO = .{};
};


export fn init() void {
    state.allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = state.allocator.allocator();

    state.config.load(alloc, def.config_path) catch {
        state.config.save(alloc, def.config_path) catch unreachable;
    };
    errdefer state.config.deinit(alloc);
    state.config.parseArgs(alloc) catch unreachable;

    state.apu.init();
    state.cart.init();
    state.cpu.init(alloc);
    state.memory.init(state.config.emulation.model);
    state.ppu.init();
    state.platform.init(state.config, imgui_cb);
    state.mmio.init();

    // TODO: Better way to do this? Not in main function!
    if(state.config.files.rom) |rom_file| {
        imgui_cb(rom_file);
    }
}

fn imgui_cb(file_path: []const u8) void {
    state.config.files.rom = file_path;
    state.cart.loadFile(file_path, state.allocator.allocator());
}

export fn frame() void {
    var irq_joypad: bool = state.mmio.updateInputState(&state.platform.input_state);
    //var irq_joypad: bool = INPUT.updateInputState(&state.input, &state.platform.input_state);
    // Note: GB runs at 59.73Hz. This software runs at 60Hz.
    // TODO: It would be better to just let the system run to the end of the next vblank. How to do that when the PPU is disabled?
    const cycles_per_frame = 70224; 
    for(0..cycles_per_frame) |_| {
        // TODO: Consider creating a list of active systems that are ticked every cycle by calling their memory and cycle functions.
        // Deactivating a system means moving it to the inactive set.
        var request: def.Request = .{};
        state.cpu.cycle(&request);
        state.cpu.request(&request);
        state.memory.cycle(&request);
        
        state.memory.request(&request);
        state.cart.request(&request);
        state.mmio.request(&request);
        state.apu.request(&request);
        state.ppu.request(&state.memory.memory, &request);

        const irq_serial, const irq_timer = state.mmio.cycle();
        const irq_vblank, const irq_stat = state.ppu.cycle(&state.memory.memory);
        const sample: ?def.Sample = state.apu.cycle();
        if(sample) |value| {
            state.platform.pushSample(value);
        }

        state.cpu.pushInterrupts(irq_vblank, irq_stat, irq_timer, irq_serial, irq_joypad);
        irq_joypad = false; // TODO: Not the nicest, okay for now.
        request.logAndReject();
    }

    state.platform.frame(state.ppu.colorIds);
}

export fn deinit() void {
    const alloc = state.allocator.allocator();
    state.cpu.deinit(alloc);
    state.cart.deinit(alloc);
    state.config.deinit(alloc);
    state.platform.deinit();
    _ = state.allocator.deinit();
}

pub fn main() void {
    state.platform.run(init, frame, deinit);
}
