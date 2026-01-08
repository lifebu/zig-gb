const std = @import("std");
const imgui = @import("cimgui");

const def = @import("defines.zig"); 

pub const State = struct {
    imgui_visible: bool = false,
    str_buff: [256]u8 = undefined,
    gb_dialog_open: bool = false,
    current_dir: std.fs.Dir = undefined,
    // TODO: Need to find a good way for imgui (ui) to tell the system that the user did something.
    imgui_cb: ?*const fn ([]u8) void = null,
};

pub fn init(state: *State, imgui_cb: *const fn ([]u8) void) void {
    state.imgui_cb = imgui_cb;
    state.current_dir = std.fs.cwd().openDir(".", .{ .iterate = true }) catch unreachable;
}

pub fn render(state: *State) void {
    if(!state.imgui_visible) {
        return;
    }

    if(imgui.igBeginMainMenuBar()) {
        if(imgui.igBeginMenu("File")) {
            if(imgui.igMenuItem("Load GB")) {
                state.gb_dialog_open = !state.gb_dialog_open;
            }
            imgui.igEndMenu();
        }

        if(imgui.igBeginMenu("Exit (CTRL+Q)")) {
            imgui.igEndMenu();
        }

        // TODO: Once we have a config file I can save the last folder that was opened and open the file dialog there.
        if(state.gb_dialog_open) {
            ShowFileDialogue(state, "gb");
        }

        imgui.igEndMainMenuBar();
    }
} 

pub fn ShowFileDialogue(state: *State, file_extension: []const u8) void {
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
                const title = std.fmt.bufPrintZ(&state.str_buff, "[Dir] {s}", .{ entry.name }) catch unreachable;
                if(imgui.igSelectable(@ptrCast(title))) {
                    state.current_dir = state.current_dir.openDir(entry.name, .{ .iterate = true }) catch unreachable;
                }
            },
            .file => {
                var sequence = std.mem.splitAny(u8, entry.name, ".");
                _ = sequence.next(); // skip filename
                if(sequence.next()) |extension| {
                    if(!std.mem.eql(u8, extension, file_extension)) {
                        continue;
                    }
                } else { // has no extension.
                    continue;
                }
                const title = std.fmt.bufPrintZ(&state.str_buff, "[File] {s}", .{ entry.name }) catch unreachable;
                if(imgui.igSelectable(@ptrCast(title))) {
                    const full_path = state.current_dir.realpath(entry.name, &state.str_buff) catch unreachable;
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
