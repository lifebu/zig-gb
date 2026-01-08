const std = @import("std");

const APU = @import("apu.zig");
const CART = @import("cart.zig");
const CLI = @import("cli.zig");
const CPU = @import("cpu.zig");
const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");
const MEMORY = @import("memory.zig");
const MMIO = @import("mmio.zig");
const PPU = @import("ppu.zig");
const Platform = @import("platform.zig");

const state = struct {
    var allocator: std.heap.GeneralPurposeAllocator(.{}) = undefined;
    var apu: APU.State = .{};
    var cart: CART.State = .{};
    var cli: CLI.State = .{};
    var cpu: CPU.State = .{};
    var memory: MEMORY.State = .{};
    var platform: Platform.State = .{};
    var ppu: PPU.State = .{};
    var mmio: MMIO.State = .{};
};

export fn init() void {
    state.allocator = std.heap.GeneralPurposeAllocator(.{}){};
    APU.init(&state.apu);
    CART.init(&state.cart);
    CLI.init(&state.cli, state.allocator.allocator());
    CPU.init(&state.cpu, state.allocator.allocator());
    MEMORY.init(&state.memory);
    PPU.init(&state.ppu);
    Platform.init(&state.platform, imgui_cb);
    MMIO.init(&state.mmio);

    // TODO: Better way to do this? Not in main function!
    if(state.cli.dumpFile) |dumpFile| {
        imgui_cb(dumpFile);
    }
}

fn imgui_cb(dump_path: []const u8) void {
    const file_type: def.FileType = CLI.getFileType(dump_path);
    CPU.loadDump(&state.cpu, file_type, state.allocator.allocator());
    CART.loadDump(&state.cart, dump_path, file_type, state.allocator.allocator());
}

export fn frame() void {
    var irq_joypad: bool = MMIO.updateInputState(&state.mmio, &state.platform.input_state);
    //var irq_joypad: bool = INPUT.updateInputState(&state.input, &state.platform.input_state);
    // Note: GB runs at 59.73Hz. This software runs at 60Hz.
    // TODO: It would be better to just let the system run to the end of the next vblank. How to do that when the PPU is disabled?
    const cycles_per_frame = 70224; 
    for(0..cycles_per_frame) |_| {
        // TODO: Consider creating a list of active systems that are ticked every cycle by calling their memory and cycle functions.
        // Deactivating a system means moving it to the inactive set.
        var request: def.Request = .{};
        CPU.cycle(&state.cpu, &request);
        CPU.request(&state.cpu, &request);
        MEMORY.cycle(&state.memory, &request);
        
        MEMORY.request(&state.memory, &request);
        CART.request(&state.cart, &request);
        MMIO.request(&state.mmio, &request);
        APU.request(&state.apu, &request);
        PPU.request(&state.ppu, &state.memory.memory, &request);

        const irq_serial, const irq_timer = MMIO.cycle(&state.mmio);
        const irq_vblank, const irq_stat = PPU.cycle(&state.ppu, &state.memory.memory);
        const sample: ?def.Sample = APU.cycle(&state.apu);
        if(sample) |value| {
            Platform.pushSample(&state.platform, value);
        }

        CPU.pushInterrupts(&state.cpu, irq_vblank, irq_stat, irq_timer, irq_serial, irq_joypad);
        irq_joypad = false; // TODO: Not the nicest, okay for now.
        request.logAndReject();
    }

    Platform.frame(&state.platform, state.ppu.colorIds);
}

export fn deinit() void {
    CPU.deinit(&state.cpu, state.allocator.allocator());
    CART.deinit(&state.cart, state.allocator.allocator());
    CLI.deinit(&state.cli, state.allocator.allocator());
    Platform.deinit();
    _ = state.allocator.deinit();
}

pub fn main() void {
    Platform.run(init, frame, deinit, &state.platform);
}
