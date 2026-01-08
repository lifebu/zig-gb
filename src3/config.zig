const std = @import("std");
const sokol = @import("sokol");

const Self = @This();

const Files = struct {
    rom: ?[]const u8 = null,
    boot_rom: ?[]const u8 = null,
};
const Audio = struct {
    stereo_audio: bool = true,
    sample_rate: u17 = 44_100,
    volume: f32 = 0.15,
};
const Keybinds = struct {
    key_up: sokol.app.Keycode = .UP,
    key_down: sokol.app.Keycode = .DOWN,
    key_left: sokol.app.Keycode = .LEFT,
    key_right: sokol.app.Keycode = .RIGHT,
    key_start: sokol.app.Keycode = .W,
    key_select: sokol.app.Keycode = .S,
    key_a: sokol.app.Keycode = .A,
    key_b: sokol.app.Keycode = .D,
};
const Color = struct { r: u8, g: u8, b: u8 };
const Graphics = struct {
    resolution_scale: u4 = 3, 
    palette_0: Color = .{ .r = 224, .g = 248, .b = 208 },
    palette_1: Color = .{ .r = 136, .g = 192, .b = 112 },
    palette_2: Color = .{ .r = 52, .g = 104, .b = 86 },
    palette_3: Color = .{ .r = 8, .g = 24, .b = 32 },
};
const Emulation = struct {
    model: enum {
        dmg,
    } = .dmg,
    ppu: enum {
        void,
        frame,
        cycle,
    } = .cycle,
    apu: enum {
        void,
        cycle,
    } = .cycle,
};
const Debug = struct {
    enable_gb_breakpoint: bool = false,
};

files: Files = .{},
audio: Audio = .{},
keybinds: Keybinds = .{},
graphics: Graphics = .{},
emulation: Emulation = .{},
debug: Debug = .{},

pub const default: Self = .{};
pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    if(self.files.rom) |data| alloc.free(data);
    if(self.files.boot_rom) |data| alloc.free(data);
}

pub fn load(self: *Self, alloc: std.mem.Allocator, path: []const u8) !void {
    const content0 = try std.fs.cwd().readFileAllocOptions(alloc, path, std.math.maxInt(u32), null, .of(u8), 0);
    defer alloc.free(content0);

    var diagnostics: std.zon.parse.Diagnostics = .{};
    defer diagnostics.deinit(alloc);
    self.* = std.zon.parse.fromSlice(Self, alloc, content0, &diagnostics, .{ .free_on_error = true }) catch |err| {
        std.log.err("Failed to parse config file, will use default: {f}.\n", .{diagnostics});
        return err;
    };

    if(self.files.boot_rom == null) {
        self.files.boot_rom = try std.fmt.allocPrint(alloc, "data/bootroms/dmg_boot.bin", .{});
    }
}

pub fn save(self: Self, alloc: std.mem.Allocator, path: []const u8) !void {
    var writer: std.io.Writer.Allocating = .init(alloc);
    defer writer.deinit();
    std.zon.stringify.serialize(self, .{}, &writer.writer) catch unreachable;

    var result: std.ArrayList(u8) = writer.toArrayList();
    defer result.deinit(alloc);

    std.fs.cwd().writeFile(.{ .data = result.items, .sub_path = path }) catch unreachable;
}

pub fn parseArgs(state: *Self, alloc: std.mem.Allocator) !void {
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    _ = args.next(); // File itself
    const file_arg: ?[]const u8 = args.next(); 
    const file_path: []const u8 = file_arg orelse return;
    const file_extension: []const u8 = std.fs.path.extension(file_path);
    if (std.mem.eql(u8, file_extension, ".gb")) {
        state.files.rom = try alloc.dupe(u8, file_path);
    } else {
        std.log.err("unknown type of file: {s}\n", .{ file_path });
    }
}
