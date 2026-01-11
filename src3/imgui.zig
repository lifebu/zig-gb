const std = @import("std");
const imgui = @import("cimgui");

const Config = @import("config.zig");
const def = @import("defines.zig"); 

const Self = @This();


imgui_visible: bool = false,
gb_dialog_open: bool = false,
current_dir: std.fs.Dir = undefined,
// TODO: Need to find a good way for imgui (ui) to tell the system that the user did something.
imgui_cb: ?*const fn ([]u8) void = null,


pub fn init(self: *Self, config: Config, imgui_cb: *const fn ([]u8) void) void {
    self.imgui_cb = imgui_cb;

    const has_rom: bool = config.files.rom != null;
    self.imgui_visible = !has_rom;
    self.gb_dialog_open = !has_rom;

    const start_dir = config.files.last_dir orelse ".";
    self.current_dir = std.fs.cwd().openDir(start_dir, .{ .iterate = true }) catch unreachable;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator, config: *Config) void {
    const full_path = self.current_dir.realpathAlloc(alloc, ".") catch unreachable;
    if(config.files.last_dir) |data| alloc.free(data);
    config.files.last_dir = full_path;
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

        if(self.gb_dialog_open) {
            ShowFileDialogue(self, alloc, "gb");
        }

        imgui.igEndMainMenuBar();
    }
} 

fn dirLessThan(_: void, lhs: std.fs.Dir.Entry, rhs: std.fs.Dir.Entry) bool {
    if(lhs.kind != rhs.kind) {
        return lhs.kind == .directory;
    }
    return std.mem.order(u8, lhs.name, rhs.name) == .lt;
}
pub fn ShowFileDialogue(self: *Self, alloc: std.mem.Allocator, file_extension: []const u8) void {
    const menu_height = 18;
    imgui.igSetNextWindowPos(.{ .x = 0, .y = menu_height }, imgui.ImGuiCond_Once);
    imgui.igSetNextWindowSize(.{ .x = def.window_width, .y = def.window_height - menu_height }, imgui.ImGuiCond_Once);
    _ = imgui.igBegin("File Dialog", 0, imgui.ImGuiWindowFlags_NoResize | imgui.ImGuiWindowFlags_NoMove | imgui.ImGuiWindowFlags_NoCollapse);

    if(imgui.igSelectable("..")) {
        self.current_dir = self.current_dir.openDir("..", .{ .iterate = true }) catch unreachable;
    }

    var info: std.ArrayList(std.fs.Dir.Entry) = .empty;
    defer {
        for(info.items) |item| { alloc.free(item.name); }
        info.deinit(alloc);
    }

    var iter = self.current_dir.iterate();
    while(iter.next() catch unreachable) |entry| {
        if(entry.kind == .directory or entry.kind == .file) {
            const new_entry: std.fs.Dir.Entry = .{ .kind = entry.kind, .name = alloc.dupe(u8, entry.name) catch unreachable };
            info.append(alloc, new_entry) catch unreachable;
        }
        // switch(entry.kind) {
        //     .directory => {
        //         const new_entry: std.fs.Dir.Entry = .{ .kind = entry.kind, .name = alloc.dupe(u8, entry.name) catch unreachable };
        //         info.append(alloc, new_entry) catch unreachable;
        //     },
        //     .file => {
        //         const new_entry: std.fs.Dir.Entry = .{ .kind = entry.kind, .name = alloc.dupe(u8, entry.name) catch unreachable };
        //         info.append(alloc, new_entry) catch unreachable;
        //     },
        //     else => {},
        // }
    }

    std.mem.sort(std.fs.Dir.Entry, info.items, {}, dirLessThan);
    for(info.items) |item| {
        switch(item.kind) {
            .directory => {
                const title = std.fmt.allocPrintSentinel(alloc, "[Dir] {s}", .{ item.name }, 0) catch unreachable;
                defer alloc.free(title);

                if(imgui.igSelectable(@ptrCast(title))) {
                    self.current_dir = self.current_dir.openDir(item.name, .{ .iterate = true }) catch unreachable;
                }
            },
            .file => {
                var sequence = std.mem.splitAny(u8, item.name, ".");
                _ = sequence.next(); // skip filename
                if(sequence.next()) |extension| {
                    if(!std.mem.eql(u8, extension, file_extension)) {
                        continue;
                    }
                } else { // has no extension.
                    continue;
                }
                const title = std.fmt.allocPrintSentinel(alloc, "[File] {s}", .{ item.name }, 0) catch unreachable;
                defer alloc.free(title);

                if(imgui.igSelectable(@ptrCast(title))) {
                    // Note: cleaned up by config and main.
                    const full_path = self.current_dir.realpathAlloc(alloc, item.name) catch unreachable;
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
