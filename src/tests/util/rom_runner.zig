const std = @import("std");
const test_options = @import("test_options");

// TODO: Use modules for the tests to not use relative paths like this!
const APU = @import("../../apu.zig");
const APUVoid = @import("../../apu_void.zig");
const Config = @import("../../config.zig");
const Core = @import("../../core.zig");
const CPU = @import("../../cpu.zig");
const def = @import("../../defines.zig");
const PPU = @import("../../ppu.zig");
const PPUVoid = @import("../../ppu_void.zig");

const cpu_breakpoint_op: u8 = 0x40; // LD B, B
const test_palette: def.Palette = .{ 
    .color_0 = .{ 0x00, 0x00, 0x00 }, 
    .color_1 = .{ 0x55, 0x55, 0x55 }, 
    .color_2 = .{ 0xAA, 0xAA, 0xAA }, 
    .color_3 = .{ 0xFF, 0xFF, 0xFF } 
};

const bully_char_low: u16 = 0x9200;
const mooneye_char_low: u16 = 0x8200;
const blargg_char_low: u16 = 0x8200;
const ascii_table: [96]u8 = .{
    ' ', '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',',  '-', '.', '/', 
    '0', '1', '2', '3', '4', '5', '6', '7',  '8', '9', ':', ';', '<',  '=', '>', '?',
    '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G',  'H', 'I', 'J', 'K', 'L',  'M', 'N', 'O',
    'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W',  'X', 'Y', 'Z', '[', '\\', ']', '^', '_',
    '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g',  'h', 'i', 'j', 'k', 'l',  'm', 'n', 'o',
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w',  'x', 'y', 'z', '{', '|',  '}', '~', ' ',
};

const mbc3_char_low: u16 = 0x8000;
const mbc3_check: u8 = 'c';
const mbc3_fail: u8 = 'f';
const mbc3_table: [39]u8 = .{ 
    ' ', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E',
    'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U',
    'V', 'W', 'X', 'Y', 'Z', mbc3_check, mbc3_fail,
};

fn parseChar(alloc: std.mem.Allocator, ppu: anytype, char_table: []const u8, char_low: u16) ![]const u8 {
    const char_len: u16 = @intCast(char_table.len);
    const char_high: u16 = char_low + (char_len * def.tile_size_byte);
    const tilemap_base_addr: u16 = if(ppu.lcd_control.bg_map_area == .map_9800) def.vram_tile_map_9800 else def.vram_tile_map_9C00;
    const tile_base_addr: u16 = if(ppu.lcd_control.bg_window_tile_data == .tile_8800) def.tile_8800 else def.tile_8000;

    var writer: std.io.Writer.Allocating = .init(alloc);
    defer writer.deinit();

    for(0..def.tile_map_size_y) |y| {
        const y_cast: u16 = @intCast(y);

        var line_has_content: bool = false;
        var line_writer: std.io.Writer.Allocating = .init(alloc);
        defer line_writer.deinit();

        for(0..def.tile_map_size_x) |x| {
            const x_cast: u16 = @intCast(x);
            const tilemap_addr: u16 = tilemap_base_addr + x_cast + (y_cast * def.tile_map_size_y);

            const tile_addr_offset: u16 = ppu.vram[tilemap_addr];
            const tile_addr: u16 = tile_base_addr + (tile_addr_offset * def.tile_size_byte);
            const tile_addr_table: u16 = std.math.clamp(tile_addr, char_low, char_high);
            const table_offset: u8 = @intCast((tile_addr_table - char_low) / def.tile_size_byte);
            const char: u8 = char_table[table_offset];
            line_has_content |= (char != ' ');

            try line_writer.writer.writeByte(char);
        }

        if(line_has_content) {
            try line_writer.writer.writeByte('\n');
            const line: []u8 = try line_writer.toOwnedSlice();
            defer alloc.free(line);
            _ = try writer.writer.write(line);
        }
    }

    return try writer.toOwnedSlice();
}

pub const ExitCondition = enum {
    none, timeout, blargg, breakpoint, // LD b,b
};
pub const Timeout = union(enum) {
    cycle: usize,
    frame: usize,
    sec: usize,
};
pub const ResultMemory = struct { addr: u16, value: u8 };
pub const Pass = union(enum) {
    fibonacci: void,
    mbc3: void,
    memory: []ResultMemory,
    text: []const u8,
};
pub const Context = union(enum) {
    none: void,
    memory: []ResultMemory,
    text_parsing: enum {
        bully, blargg, mbc3, gambatte, mooneye,
    },
};
pub const RomRunConfig = struct {
    const Self = @This();

    exit: ExitCondition,
    timeout: Timeout,
    pass: Pass,
    context: Context,
    core_config: Config = .{},

    pub fn getTimeoutInCycles(self: Self) usize {
        return switch(self.timeout) {
            .cycle => |value| value,
            .frame => |value| value * def.t_cycles_per_frame,
            .sec => |value| value * def.t_cycles_in_60fps * 60,
        };
    }
    pub fn hitExit(self: Self, alloc: std.mem.Allocator, core: anytype, last_ppu_lcd_y: *u8, cycle_count: usize) !bool {
        return switch (self.exit) {
            .none => false,
            .timeout => blk: {
                const timeout_cycles: usize = self.getTimeoutInCycles();
                break: blk cycle_count >= timeout_cycles;
            },
            .blargg => blk: {
                const lcd_y: u8 = core.ppu.lcd_y;
                if(lcd_y == 144 and last_ppu_lcd_y.* == 143) {
                    const vram_text: []const u8 = try parseChar(alloc, core.ppu, &ascii_table, blargg_char_low);
                    defer alloc.free(vram_text);

                    var iter = std.mem.splitBackwardsScalar(u8, vram_text, '\n');
                    while(iter.next()) |line| {
                        const has_passed: bool = std.mem.containsAtLeast(u8, line, 1, "Passed");
                        const has_failed: bool = std.mem.containsAtLeast(u8, line, 1, "Failed");
                        if(has_passed or has_failed) break: blk true;
                    }
                }
                last_ppu_lcd_y.* = lcd_y;
                break: blk false;
            },
            .breakpoint => core.cpu.registers.r8.ir == cpu_breakpoint_op,
        };
    }
    pub fn passed(self: Self, core: anytype, context: []const u8) bool {
        return switch(self.pass) {
            .fibonacci => blk: {
                const r8 = core.cpu.registers.r8;
                break: blk r8.b == 3 and r8.c == 5 and r8.d == 8 and r8.e == 13 and r8.h == 21 and r8.l == 34;
            },
            .mbc3 => blk: {
                break: blk !std.mem.containsAtLeastScalar(u8, context, 1, mbc3_fail);
            },
            .memory => @panic("memory passing not yet supported"),
            .text => |expected| blk: {
                break: blk std.mem.containsAtLeast(u8, context, 1, expected);
            },
        };
    }
    pub fn getContext(self: Self, alloc: std.mem.Allocator, core: anytype) ![]const u8 {
        return switch(self.context) {
            .none => "",
            .memory => @panic("memory context not yet supported"),
            .text_parsing => |parse_type| parse: {
                break: parse switch (parse_type) {
                    .blargg => try parseChar(alloc, core.ppu, &ascii_table, blargg_char_low),
                    .bully => try parseChar(alloc, core.ppu, &ascii_table, bully_char_low),
                    .mbc3 => try parseChar(alloc, core.ppu, &mbc3_table, mbc3_char_low),
                    .gambatte => "",
                    .mooneye => try parseChar(alloc, core.ppu, &ascii_table, mooneye_char_low),
                };
            },
        };
    }
};

const CoreType = switch(test_options.test_category) {
    .all => Core.Core(APU, CPU, PPU),
    .apu => Core.Core(APU, CPU, PPUVoid),
    .cart => Core.Core(APUVoid, CPU, PPUVoid),
    .cpu => Core.Core(APUVoid, CPU, PPUVoid),
    .instr => Core.Core(APUVoid, CPU, PPUVoid),
    .memory => Core.Core(APUVoid, CPU, PPUVoid),
    .mmio => Core.Core(APUVoid, CPU, PPUVoid),
    .ppu => Core.Core(APUVoid, CPU, PPU),
};

pub fn genCoreConfig(model: def.GBModel, force_boot_rom: bool, rom: []const u8) Config {
    var core_config: Config = .default;
    core_config.debug.disable_saves = true;
    core_config.emulation.model = model;
    core_config.emulation.skip_boot_rom = !force_boot_rom;
    core_config.graphics.palette = test_palette;
    core_config.files.rom = rom;
    return core_config;
}

pub fn isFiltered(path: []const u8) bool {
    if(test_options.test_filter) |test_filter| {
        if(!std.mem.containsAtLeast(u8, path, 1, test_filter)) {
            return true;
        }
    }
    if(test_options.test_exclude) |test_exclude| {
        var test_exclude_iter = std.mem.splitScalar(u8, test_exclude, ',');
        while (test_exclude_iter.next()) |exclude| {
            if(std.mem.containsAtLeast(u8, path, 1, exclude)) {
                return true;
            }
        }
    }
    return false;
}

pub fn run(run_config: RomRunConfig) !void {
    const alloc = std.testing.allocator;
    var irq_joypad: bool = false;
    const timeout_cycles: usize = run_config.getTimeoutInCycles();

    var core: CoreType = .{};
    core.init(alloc, run_config.core_config);
    defer core.deinit(alloc, run_config.core_config);

    var last_ppu_lcd_y: u8 = 0;
    var exit_cond_hit: bool = false;
    var cycle_count: u32 = 0;
    while(cycle_count <= timeout_cycles) : (cycle_count += 1) {
        core.cyle(&irq_joypad);
        exit_cond_hit = try run_config.hitExit(alloc, &core, &last_ppu_lcd_y, cycle_count);
        if(exit_cond_hit) break;
    }

    const context: []const u8 = try run_config.getContext(alloc, &core);
    defer alloc.free(context);

    std.testing.expectEqual(true, exit_cond_hit or run_config.exit == .none) catch |err| {
        std.debug.print("Failed: {s}: {s}\n", .{ run_config.core_config.files.rom.?, "rom has exit condition but it timed out." });
        std.debug.print("Context: {s}\n", .{ context });
        return err;
    };

    const passed: bool = run_config.passed(&core, context);
    std.testing.expectEqual(true, passed) catch |err| {
        std.debug.print("Failed: {s}\n", .{ run_config.core_config.files.rom.? });
        std.debug.print("Context: {s}\n", .{ context });
        return err;
    };
}
