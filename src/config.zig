const std = @import("std");
const sokol = @import("sokol");

const def = @import("defines.zig");

const Self = @This();

const Files = struct {
    rom: ?[]const u8 = null,
    last_dir: ?[]const u8 = null,
};
const Audio = struct {
    // TODO: Sample rate would be harder to do as apu needs that info as well.
    stereo_audio: bool = true,
    volume: f32 = 0.10,
};
const Graphics = struct {
    // TODO: This does not work right now. Need a way to change the resolution later in sokol.
    //resolution_scale: u4 = 3, 
    palette: def.Palette = .{},
};
const Emulation = struct {
    model: def.GBModel = .dmg,
    skip_boot_rom: bool = false,
};
const Debug = struct {
    enable_gb_breakpoint: bool = false,
    disable_saves: bool = false,
};

files: Files = .{},
audio: Audio = .{},
keybinds: def.Keybinds = .{},
graphics: Graphics = .{},
emulation: Emulation = .{},
debug: Debug = .{},

pub const default: Self = .{};
pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    if(self.files.rom) |data| alloc.free(data);
    if(self.files.last_dir) |data| alloc.free(data);
}

pub fn load(self: *Self, io: std.Io, alloc: std.mem.Allocator, path: []const u8) !void {
    const content0 = try std.Io.Dir.cwd().readFileAllocOptions(io, path, alloc, .unlimited, .of(u8), 0);
    defer alloc.free(content0);

    var diagnostics: std.zon.parse.Diagnostics = .{};
    defer diagnostics.deinit(alloc);
    self.* = std.zon.parse.fromSliceAlloc(Self, alloc, content0, &diagnostics, .{ .free_on_error = true }) catch |err| {
        std.log.warn("Failed to parse config file, will use default: {f}.", .{diagnostics});
        return err;
    };
}

pub fn save(self: Self, io: std.Io, alloc: std.mem.Allocator, path: []const u8) !void {
    var writer: std.Io.Writer.Allocating = .init(alloc);
    defer writer.deinit();
    std.zon.stringify.serialize(self, .{}, &writer.writer) catch unreachable;

    var result: std.ArrayList(u8) = writer.toArrayList();
    defer result.deinit(alloc);

    std.Io.Dir.cwd().writeFile(io, .{ .data = result.items, .sub_path = path }) catch unreachable;
}

pub fn parseArgs(state: *Self, alloc: std.mem.Allocator, args: std.process.Args) !void {
    var iter: std.process.Args.Iterator = try args.iterateAllocator(alloc);
    defer iter.deinit();

    _ = iter.next(); // File itself
    const file_arg: ?[]const u8 = iter.next(); 
    const file_path: []const u8 = file_arg orelse return;
    const file_extension: []const u8 = std.fs.path.extension(file_path);
    if (std.mem.eql(u8, file_extension, ".gb")) {
        state.files.rom = try alloc.dupe(u8, file_path);
    } else {
        std.log.err("unknown type of file: {s}", .{ file_path });
    }
}
