const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const sokol = @import("sokol");

const APU = @import("apu.zig");
const Config = @import("config.zig");
const Core = @import("core.zig");
const def = @import("defines.zig");
const Platform = @import("platform.zig");
const PPU = @import("ppu.zig");

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
    .default_callstack_depth = 10,
};

const CoreType = Core.Core(APU.Apu, PPU.Ppu);
const state = struct {
    var alloc: std.mem.Allocator = undefined;
    var io: std.Io = undefined;
    // TODO: Keeping args in memory all the time seems wasteful, just to get them later?
    var args: std.process.Args = undefined;
    var core: ?CoreType = null;
    var config: Config = .default;
    var platform: Platform = .{};
    var last_platform_time: u64 = 0;
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
    const platform_delta: u64 = sokol.time.since(state.last_platform_time);
    if(state.core) |*loaded_core| {
        const start: u64 = sokol.time.now();
        loaded_core.frame(state.platform.input_state);
        const core_delta: u64 = sokol.time.since(start);
        state.last_platform_time = sokol.time.now();
        state.platform.frame(state.io, state.alloc, loaded_core.ppu.getFrontBuffer(), loaded_core.apu.getSamples(), core_delta, platform_delta);
    } else {
        state.platform.frame(state.io, state.alloc, def.default_color_ids, null, null, null);
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

    tracy.cleanExit(state.io);
}

pub fn main(init_minimal: std.process.Init.Minimal) void {
    state.args = init_minimal.args;

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();

    const use_debug_allocator: bool = builtin.mode == .Debug;
    const base_alloc: std.mem.Allocator = if(use_debug_allocator) debug_allocator.allocator() else std.heap.c_allocator;
    var tracy_allocator: tracy.Allocator = .{ .parent = base_alloc };
    state.alloc = tracy_allocator.allocator();

    var io_impl: std.Io.Threaded = .init(state.alloc, .{ 
        .argv0 = .init(.{ .vector = init_minimal.args.vector }), 
        .environ = .{ .block = init_minimal.environ.block } 
    });
    defer io_impl.deinit();
    state.io = io_impl.io();

    state.platform.run(init, frame, deinit);
}
