const std = @import("std");
const sokol = @import("sokol");

const Config = @import("config.zig");
const Core = @import("core.zig");
const def = @import("defines.zig");
const Platform = @import("platform.zig");


const state = struct {
    var allocator: std.heap.GeneralPurposeAllocator(.{}) = undefined;
    var core: ?Core = null;
    var config: Config = .default;
    var platform: Platform = .{};
};


export fn init() void {
    state.allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = state.allocator.allocator();

    // TODO: Maybe change this function to loadOrCreate()?
    state.config.load(alloc, def.config_path) catch {
        state.config.save(alloc, def.config_path) catch unreachable;
    };
    errdefer state.config.deinit(alloc);
    state.config.parseArgs(alloc) catch unreachable;

    state.platform.init(state.config, imgui_cb);

    if(state.config.files.rom) |rom_file| {
        imgui_cb(rom_file);
    }
}

fn imgui_cb(file_path: []const u8) void {
    const alloc = state.allocator.allocator();
    // TODO: memory management of that rom string is super annoying, can we do that better?
    if(state.config.files.rom) |data| alloc.free(data);
    state.config.files.rom = file_path;

    if(state.core) |*loaded_core| {
        loaded_core.deinit(alloc);
    }
    state.core = .{};
    state.core.?.init(state.config, alloc);
}

export fn frame() void {
    const alloc = state.allocator.allocator();

    if(state.core) |*loaded_core| {
        loaded_core.frame(state.platform.input_state);
        state.platform.frame(alloc, loaded_core.ppu.colorIds, &loaded_core.apu.samples);
    } else {
        state.platform.frame(alloc, def.default_color_ids, null);
    }
}

export fn deinit() void {
    const alloc = state.allocator.allocator();
    if(state.core) |*loaded_core| {
        loaded_core.deinit(alloc);
        state.core = null;
    }

    state.config.deinit(alloc);
    state.platform.deinit();
    _ = state.allocator.deinit();
}

pub fn main() void {
    state.platform.run(init, frame, deinit);
}
