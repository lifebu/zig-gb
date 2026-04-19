const std = @import("std");
const build_options = @import("build_options");
const sokol = @import("sokol");

const APU = @import("apu.zig");
const Config = @import("config.zig");
const Core = @import("core.zig");
const CPU = @import("cpu.zig");
const def = @import("defines.zig");
const Platform = @import("platform.zig");
const PPU = @import("ppu.zig");
const PPUVoid = @import("ppu_void.zig");

// tracy (required to be in root file).
pub const tracy_impl = @import("tracy_impl");
pub const tracy = @import("tracy");
// TODO: This creates a dependency loop? If I call it "tracy_options"???
pub const tracy_option: tracy.options = .{
    .on_demand = false,
    .no_broadcast = false,
    .only_localhost = false,
    .only_ipv4 = false,
    .delayed_init = false,
    .manual_lifetime = false,
    .verbose = false,
    .data_port = null,
    .broadcast_port = null,
    .default_callstack_depth = 0,
};

const APUType = switch (build_options.apu_model) {
    .void => APU, .cycle => APU,
};
const CPUType = switch (build_options.cpu_model) {
    .cycle => CPU, .instruction => CPU,
};
const PPUType = switch (build_options.ppu_model) {
    .void => PPUVoid, .cycle => PPU, .frame => PPU,
};
const CoreType = Core.Core(APUType, CPUType, PPU);
const state = struct {
    var alloc: std.mem.Allocator = undefined;
    var io: std.Io = undefined;
    // TODO: Keeping args in memory all the time seems wasteful, just to get them later?
    var args: std.process.Args = undefined;
    var core: ?CoreType = null;
    var config: Config = .default;
    var platform: Platform = .{};
};


export fn init() void {
    // TODO: Maybe change this function to loadOrCreate()?
    state.config.load(state.io, state.alloc, def.config_path) catch {
        state.config.save(state.io, state.alloc, def.config_path) catch unreachable;
    };
    errdefer state.config.deinit(state.alloc);
    state.config.parseArgs(state.alloc, state.args) catch unreachable;

    state.platform.init(state.io, state.config, imgui_cb);

    if(state.config.files.rom) |rom_file| {
        // TODO: This is pretty bad. imgui callback frees the previous string.
        // Which makes rom_file invalid iff you use a launch parameter.
        const dupe = state.alloc.dupe(u8, rom_file) catch unreachable;
        errdefer state.alloc.free(dupe);

        imgui_cb(dupe);
    }
}

fn imgui_cb(file_path: []const u8) void {
    if(state.core) |*loaded_core| {
        loaded_core.deinit(state.io, state.alloc, state.config);
    }

    // TODO: memory management of that rom string is super annoying, can we do that better?
    if(state.config.files.rom) |data| state.alloc.free(data);
    state.config.files.rom = file_path;

    state.core = .{};
    state.core.?.init(state.io, state.alloc, state.config);
}

export fn frame() void {
    if(state.core) |*loaded_core| {
        const start: u64 = sokol.time.now();
        loaded_core.frame(state.platform.input_state);
        const core_delta: u64 = sokol.time.since(start);
        state.platform.frame(state.io, state.alloc, loaded_core.ppu.front_buffer, &loaded_core.apu.samples, core_delta);
    } else {
        state.platform.frame(state.io, state.alloc, def.default_color_ids, null, null);
    }
}

export fn deinit() void {
    if(state.core) |*loaded_core| {
        loaded_core.deinit(state.io, state.alloc, state.config);
        state.core = null;
    }

    state.platform.deinit(state.io, state.alloc, &state.config);

    // TODO: This is for not writing the rom name into the config. This is pretty stupid.
    if(state.config.files.rom) |data| state.alloc.free(data);
    state.config.files.rom = null;
    state.config.save(state.io, state.alloc, def.config_path) catch unreachable;

    state.config.deinit(state.alloc);
}

pub fn main(pinit: std.process.Init) void {
    state.io = pinit.io;
    // TODO: Creates panic at deinit()?
    // var tracy_allocator: tracy.Allocator = .{ .parent = state.allocator.allocator() };
    // state.alloc = tracy_allocator.allocator();
    state.alloc = if(build_options.tracy_enabled) pinit.gpa else pinit.gpa;
    state.args = pinit.minimal.args;

    state.platform.run(init, frame, deinit);
}
