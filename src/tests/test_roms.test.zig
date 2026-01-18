const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const Config = @import("../config.zig");
const Core = @import("../core.zig");
const def = @import("../defines.zig");

const cpu_breakpoint_op = 0x40; // LD B, B
const test_palette: def.Palette = .{ 
    .color_0 = .{ 0x00, 0x00, 0x00 }, 
    .color_1 = .{ 0x55, 0x55, 0x55 }, 
    .color_2 = .{ 0xAA, 0xAA, 0xAA }, 
    .color_3 = .{ 0xFF, 0xFF, 0xFF } 
};

const ascii_low = 32;
const ascii_high = 128;
const ascii_len = ascii_high - ascii_low;
const mooneye_char_low = 0x8200;
const blargg_char_low = 0x8200;

fn parseAscii(alloc: std.mem.Allocator, vram: [def.vram_size]u8, char_low: u16) ![]const u8 {
    const char_high = char_low + (ascii_len * def.tile_size_byte);

    var writer: std.io.Writer.Allocating = .init(alloc);
    defer writer.deinit();

    for(0..def.tile_map_size_y) |y| {
        const y_cast: u16 = @intCast(y);

        var line_has_content: bool = false;
        var line_writer: std.io.Writer.Allocating = .init(alloc);
        defer line_writer.deinit();

        for(0..def.tile_map_size_x) |x| {
            const x_cast: u16 = @intCast(x);
            const tilemap_addr: u16 = def.vram_tile_map_9800 + x_cast + (y_cast * def.tile_map_size_y);

            const tile_addr_offset: u16 = vram[tilemap_addr];
            const tile_addr: u16 = def.tile_8000 + (tile_addr_offset * def.tile_size_byte);
            const tile_addr_ascii = std.math.clamp(tile_addr, char_low, char_high);
            const ascii: u8 = @intCast((tile_addr_ascii - char_low) / def.tile_size_byte);
            const char: u8 = ascii + 32;
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

const ResultMemory = struct { addr: u16, value: u8 };
const RomTestConfig = struct {
    /// Note: Either file or directory
    path: []const u8,
    // TODO: Have a way to specify which version of subsystems to use for tests. Not using the APU? Then use a void apu => Faster.
    // TODO: Maybe Core is not a struct but a Generic (like ArrayList?) You can either specify the build-option version or a version where you specify the type for ppu, etc.
    systems: u8,
    // TODO: Auto detect model from filename? Do I need specific revisions? (DMG A, B, C)
    model: def.GBModel,
    exit: enum {
        none, breakpoint, // LD b,b
    },
    // TODO: How do we skip the boot rom?
    // Currently wastes: 5.892.625 cycles or 84 Frames or 1,4 seconds
    timeout: union(enum) {
        cycle: usize,
        frame: usize,
        sec: usize,
    },
    pass: union(enum) {
        fibonacci: void,
        text: []const u8,
        // TODO: Binary of the screenshot? path of the screenshot? How to compare?
        screenshot: []const u8,
        memory: []ResultMemory,
        // TODO: Using an externally generated trace of a given format and compare each state of the emulator to that.
        trace: []const u8,
    },
    fail_ctx: union(enum) {
        // TODO: Try to remove none as we get more support for different test suites.
        none: void,
        memory: []ResultMemory,
        // Binary of the screenshot? path of the screenshot? How to compare?
        screenshot: []const u8,
        text_parsing: enum {
            blargg, gambatte, mooneye,
        },
    },

    const Self = @This();
    pub fn getTimeoutCycles(self: Self) usize {
        return switch(self.timeout) {
            .cycle => |value| value,
            .frame => |value| value * def.t_cycles_per_frame,
            .sec => |value| value * def.t_cycles_in_60fps * 60,
        };
    }
    pub fn generateCoreConfig(self: Self, alloc: std.mem.Allocator) ![]Config {
        const path_stat = try std.fs.cwd().statFile(self.path);
        return switch(path_stat.kind) {
            // TODO: Generate multiple Configs for directories
            .directory => @panic("directories not yet supported"),
            .file => file: {
                const result: []Config = try alloc.alloc(Config, 1);
                errdefer alloc.free(result);

                result[0] = .default;
                result[0].emulation.model = self.model;
                result[0].files.rom = self.path;
                break: file result;
            },
            else => @panic("Unknown type of path in test rom config!"),
        };
    }
    pub fn exitConditionHit(self: Self, core: *const Core) bool {
        return switch (self.exit) {
            .none => false,
            .breakpoint => core.cpu.registers.r8.ir == cpu_breakpoint_op,
        };
    }
    pub fn passed(self: Self, core: *const Core, context: []const u8) bool {
        return switch(self.pass) {
            .memory => @panic("memory passing not yet supported"),
            .trace => @panic("memory passing not yet supported"),
            .text => |expected| txt: {
                break: txt std.mem.containsAtLeast(u8, context, 1, expected);
            },
            .fibonacci => fib: {
                const r8 = core.cpu.registers.r8;
                break: fib r8.b == 3 and r8.c == 5 and r8.d == 8 and r8.e == 13 and r8.h == 21 and r8.l == 34;
            },
            .screenshot => @panic("memory passing not yet supported"),
        };
    }
    // TODO: How to do that for the other cases? What is their output?
    pub fn getContext(self: Self, alloc: std.mem.Allocator, core: *const Core) ![]const u8 {
        return switch(self.fail_ctx) {
            .none => "",
            .memory => "",
            .screenshot => "",
            .text_parsing => |parse_type| parse: {
                break: parse switch (parse_type) {
                    .blargg => try parseAscii(alloc, core.ppu.vram, blargg_char_low),
                    .gambatte => "",
                    .mooneye => try parseAscii(alloc, core.ppu.vram, mooneye_char_low),
                };
            },
        };
    }
};
// TODO: How do we filter for specific systems? Example: I am working on the cpu and I want to only run cpu test roms + my cpu unit tests.
const mooneye_path = "playground/game-boy-test-roms/mooneye-test-suite/";
const blargg_path = "playground/game-boy-test-roms/blargg/";

// TODO: How can I use a directory? All mooneye tests are the same for example.
//  => But this also has exceptions.
//  => For directory also define if it is just this directoy or all subdirectories.
const rom_test_configs: [2]RomTestConfig = .{
    .{ .path = mooneye_path ++ "acceptance/div_timing.gb", 
        .systems = 0, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 100 }, .pass = .fibonacci, .fail_ctx = .{ .text_parsing = .mooneye } },
    .{ .path = blargg_path ++ "cpu_instrs/individual/01-special.gb", 
        .systems = 0, .model = .dmg, .exit = .none, .timeout = .{ .frame = 240 }, .pass = .{ .text = "Passed" }, .fail_ctx = .{ .text_parsing = .blargg } },
    // .{ .path = mooneye_path ++ "acceptance/boot_div-S.gb", 
    //     .systems = 0, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 100 }, .pass = .fibonacci, .fail_ctx = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/interrupts/ie_push.gb", 
    //     .systems = 0, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 100 }, .pass = .fibonacci, .fail_ctx = .{ .text_parsing = .mooneye } },
};

pub fn runTestRomsTests() !void {
    const alloc = std.testing.allocator;

    var irq_joypad: bool = false;

    for (rom_test_configs) |test_config| {
        const timeout_cycles: usize = test_config.getTimeoutCycles();
        const configs: []Config = try test_config.generateCoreConfig(alloc);
        defer alloc.free(configs);

        for(configs) |config| {
            // TODO: Also pass subsystems to core or config.
            var core: Core = .{};
            core.init(alloc, config);
            defer core.deinit(alloc, config);

            var exit_cond_hit: bool = false;
            var cycle_count: u32 = 0;
            while(cycle_count <= timeout_cycles) : (cycle_count += 1) {
                core.cyle(&irq_joypad);
                exit_cond_hit = test_config.exitConditionHit(&core);
                if(exit_cond_hit) break;
            }

            std.testing.expectEqual(true, exit_cond_hit or test_config.exit == .none) catch |err| {
                std.debug.print("Failed: {s}: {s}\n", .{ test_config.path, "rom has exit condition but it timed out." });
                return err;
            };

            const context: []const u8 = try test_config.getContext(alloc, &core);
            defer alloc.free(context);
            const passed: bool = test_config.passed(&core, context);
            std.testing.expectEqual(true, passed) catch |err| {
                std.debug.print("Failed: {s}\n", .{ test_config.path });
                std.debug.print("Context: {s}\n", .{ context });
                return err;
            };
        }
    }
}
