const std = @import("std");
const imgui = @import("cimgui");

const def = @import("defines.zig"); 

const Self = @This();


imgui_visible: bool = false,
gb_dialog_open: bool = false,
current_dir: std.fs.Dir = undefined,
// TODO: Need to find a good way for imgui (ui) to tell the system that the user did something.
imgui_cb: ?*const fn ([]u8) void = null,


pub fn init(state: *Self, imgui_cb: *const fn ([]u8) void) void {
    state.imgui_cb = imgui_cb;
    state.current_dir = std.fs.cwd().openDir(".", .{ .iterate = true }) catch unreachable;
}

pub fn render(self: *Self, alloc: std.mem.Allocator) void {
    if(!self.imgui_visible) {
        return;
    }

    if(imgui.igBeginMainMenuBar()) {
        if(imgui.igBeginMenu("File")) {
            if(imgui.igMenuItem("Load GB")) {
                self.gb_dialog_open = !self.gb_dialog_open;
            }
            imgui.igEndMenu();
        }

        if(imgui.igBeginMenu("Exit (CTRL+Q)")) {
            imgui.igEndMenu();
        }

        // TODO: Once we have a config file I can save the last folder that was opened and open the file dialog there.
        if(self.gb_dialog_open) {
            ShowFileDialogue(self, alloc, "gb");
        }

        imgui.igEndMainMenuBar();
    }
} 

pub fn ShowFileDialogue(self: *Self, alloc: std.mem.Allocator, file_extension: []const u8) void {
    const menu_height = 18;
    imgui.igSetNextWindowPos(.{ .x = 0, .y = menu_height }, imgui.ImGuiCond_Once);
    imgui.igSetNextWindowSize(.{ .x = def.window_width, .y = def.window_height - menu_height }, imgui.ImGuiCond_Once);
    _ = imgui.igBegin("File Dialog", 0, imgui.ImGuiWindowFlags_NoResize | imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoCollapse);

    if(imgui.igSelectable("..")) {
        self.current_dir = self.current_dir.openDir("..", .{ .iterate = true }) catch unreachable;
    }

    // TODO: Can we have this sorted alphabetically?
    var iter = self.current_dir.iterate();
    while(iter.next() catch unreachable) |entry| {
        switch(entry.kind) {
            .directory => {
                const title = std.fmt.allocPrintSentinel(alloc, "[Dir] {s}", .{ entry.name }, 0) catch unreachable;
                defer alloc.free(title);

                if(imgui.igSelectable(@ptrCast(title))) {
                    self.current_dir = self.current_dir.openDir(entry.name, .{ .iterate = true }) catch unreachable;
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
                const title = std.fmt.allocPrintSentinel(alloc, "[File] {s}", .{ entry.name }, 0) catch unreachable;
                defer alloc.free(title);

                if(imgui.igSelectable(@ptrCast(title))) {
                    // Note: cleaned up by config and main.
                    const full_path = self.current_dir.realpathAlloc(alloc, entry.name) catch unreachable;
                    if(self.imgui_cb) |callback| {
                        callback(full_path);
                    }
                }
            },
            else => {},
        }
    }

    imgui.igEnd();
}
