const std = @import("std");
const imgui = @import("cimgui");

const def = @import("defines.zig"); 

pub const State = struct {
    imgui_visible: bool = false,
    alloc: std.mem.Allocator = undefined,
    dump_dialog_open: bool = false,
    current_dir: std.fs.Dir = undefined,
    // TODO: Need to find a good way for imgui (ui) to tell the system that the user did something.
    imgui_cb: ?*const fn ([]u8) void = null,
};

pub fn init(state: *State, alloc: std.mem.Allocator, imgui_cb: *const fn ([]u8) void) void {
    state.alloc = alloc;
    state.imgui_cb = imgui_cb;
    state.current_dir = std.fs.cwd().openDir(".", .{ .iterate = true }) catch unreachable;
}

pub fn render(state: *State) void {
    if(!state.imgui_visible) {
        return;
    }

    if(imgui.igBeginMainMenuBar()) {
        if(imgui.igBeginMenu("File")) {
            if(imgui.igMenuItem("Load Dump")) {
                state.dump_dialog_open = !state.dump_dialog_open;
            }
            imgui.igEndMenu();
        }

        if(state.dump_dialog_open) {
            const menu_height = 18;
            imgui.igSetNextWindowPos(.{ .x = 0, .y = menu_height }, imgui.ImGuiCond_Once);
            imgui.igSetNextWindowSize(.{ .x = def.window_width, .y = def.window_height - menu_height }, imgui.ImGuiCond_Once);
            _ = imgui.igBegin("File Dialog", 0, imgui.ImGuiWindowFlags_NoResize | imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoCollapse);

            if(imgui.igSelectable("..")) {
                state.current_dir = state.current_dir.openDir("..", .{ .iterate = true }) catch unreachable;
            }

            var iter = state.current_dir.iterate();
            while(iter.next() catch unreachable) |entry| {
                switch(entry.kind) {
                    .directory => {
                        const title = std.fmt.allocPrintZ(state.alloc, "[Dir] {s}", .{ entry.name }) catch unreachable;
                        defer state.alloc.free(title);
                        if(imgui.igSelectable(@ptrCast(title))) {
                            state.current_dir = state.current_dir.openDir(entry.name, .{ .iterate = true }) catch unreachable;
                        }
                    },
                    .file => {
                        var sequence = std.mem.split(u8, entry.name, ".");
                        _ = sequence.next(); // skip filename
                        if(sequence.next()) |extension| {
                            if(!std.mem.eql(u8, extension, "dump")) {
                                continue;
                            }
                        } else { // has no extension.
                            continue;
                        }
                        const title = std.fmt.allocPrintZ(state.alloc, "[File] {s}", .{ entry.name }) catch unreachable;
                        defer state.alloc.free(title);
                        if(imgui.igSelectable(@ptrCast(title))) {
                            const full_path = state.current_dir.realpathAlloc(state.alloc, entry.name) catch unreachable;
                            defer state.alloc.free(full_path);
                            if(state.imgui_cb) |callback| {
                                callback(full_path);
                            }
                        }
                    },
                    else => {},
                }
            }

            imgui.igEnd();
        }

        imgui.igEndMainMenuBar();
    }
} 
