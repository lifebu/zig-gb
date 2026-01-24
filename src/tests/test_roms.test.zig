const std = @import("std");
const test_options = @import("test_options");

// TODO: Use modules for the tests to not use relative paths like this!
const APU = @import("../apu.zig");
const APUVoid = @import("../apu_void.zig");
const Config = @import("../config.zig");
const Core = @import("../core.zig");
const CPU = @import("../cpu.zig");
const def = @import("../defines.zig");
const PPU = @import("../ppu.zig");
const PPUVoid = @import("../ppu_void.zig");

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

const CoreType = switch(test_options.test_filter) {
    .all => Core.Core(APU, CPU, PPU),
    .cart => Core.Core(APUVoid, CPU, PPUVoid),
    .cpu => Core.Core(APUVoid, CPU, PPUVoid),
    .memory => Core.Core(APUVoid, CPU, PPUVoid),
    .mmio => Core.Core(APUVoid, CPU, PPUVoid),
    .ppu => Core.Core(APUVoid, CPU, PPU),
    .apu => Core.Core(APU, CPU, PPUVoid),
};

const ResultMemory = struct { addr: u16, value: u8 };
const RomTestConfig = struct {
    // TODO: Add a path_filter used for directories? So I can exclude some problematic instructions?
    /// Note: Either file or directory
    path: []const u8,
    // TODO: Can I define a slice of filters in the build script? 
    // Then I can split Halt tests from cpu instruction tests.
    // But still be able to test all cpu features?
    system: test_options.@"build.TestFilter",
    model: def.GBModel,
    exit: enum {
        none, blargg, breakpoint, // LD b,b
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
    context: union(enum) {
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
    pub fn generateCoreConfigs(self: Self, alloc: std.mem.Allocator) ![]Config {
        const path_stat = try std.fs.cwd().statFile(self.path);
        return switch(path_stat.kind) {
            .directory => blk: {
                // TODO: Use the contents of the filename to determine for which model this config would be and set emulation.model.
                // Use this later to filter out tests that do not work on a specific model.
                // This might need different "detection" methods (as people use different naming schemes).
                // Should self.model contain an "detect" entry? Or is it an optiona with a default null?
                var result: std.ArrayList(Config) = .empty;
                defer result.deinit(alloc);

                const dir: std.fs.Dir = try std.fs.cwd().openDir(self.path, .{ .iterate = true });
                var iter = dir.iterate();
                while(iter.next() catch unreachable) |entry| {
                    if(entry.kind != .file) {
                        continue;
                    }
                    if(!std.mem.eql(u8, std.fs.path.extension(entry.name), ".gb")) {
                        continue;
                    }

                    const new: *Config = try result.addOne(alloc);
                    new.* = .default;
                    new.emulation.model = self.model;
                    new.files.rom = try std.fmt.allocPrint(alloc, "{s}{s}", .{ self.path, entry.name });
                    new.debug.disable_saves = true;
                    new.graphics.palette = test_palette;
                }

                break: blk try result.toOwnedSlice(alloc);
            },
            .file => blk: {
                const result: []Config = try alloc.alloc(Config, 1);
                errdefer alloc.free(result);

                result[0] = .default;
                result[0].emulation.model = self.model;
                result[0].files.rom = self.path;
                result[0].debug.disable_saves = true;
                result[0].graphics.palette = test_palette;
                break: blk result;
            },
            else => @panic("Unknown type of path in test rom config!"),
        };
    }
    pub fn exitConditionHit(self: Self, alloc: std.mem.Allocator, core: anytype, last_ppu_lcd_y: *u8) !bool {
        return switch (self.exit) {
            .none => false,
            .blargg => blk: {
                const lcd_y: u8 = core.ppu.lcd_y;
                if(lcd_y == 144 and last_ppu_lcd_y.* == 143) {
                    const vram_text: []const u8 = try parseAscii(alloc, core.ppu.vram, blargg_char_low);
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
            .memory => @panic("memory passing not yet supported"),
            .trace => @panic("memory passing not yet supported"),
            .text => |expected| txt: {
                break: txt std.mem.containsAtLeast(u8, context, 1, expected);
            },
            .fibonacci => fib: {
                const r8 = core.cpu.registers.r8;
                break: fib r8.b == 3 and r8.c == 5 and r8.d == 8 and r8.e == 13 and r8.h == 21 and r8.l == 34;
            },
            .screenshot => @panic("screenshot passing not yet supported"),
        };
    }
    // TODO: How to do that for the other cases? What is their output?
    pub fn getContext(self: Self, alloc: std.mem.Allocator, core: anytype) ![]const u8 {
        return switch(self.context) {
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
const blargg_path = "playground/game-boy-test-roms/blargg/";
const bully_path = "playground/game-boy-test-roms/bully/";
const dmg_acid_path = "playground/game-boy-test-roms/dmg-acid2/";
const mbc3_tester_path = "playground/game-boy-test-roms/mbc3-tester/";
const mooneye_path = "playground/game-boy-test-roms/mooneye-test-suite/";
const scribbltests = "playground/game-boy-test-roms/scribbltests/";

// TODO: Go through every test and collect results and print a statistics how many passed and which failed. 
// Have the statistics give me passing rates for each test suite (like blargg: passed/skipped/failed/total).
// This is also because we immediately return on the first failed test!
// TODO: Can we generate a test for each rom and filter them like in test.zig?
const rom_test_configs: [1]RomTestConfig = .{
    // .{ .path = blargg_path ++ "dmg_sound/rom_singles/",
    //     .system = .apu, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 360 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    // .{ .path = blargg_path ++ "cpu_instrs/individual/",
    //     .system = .cpu, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 1160 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    // .{ .path = blargg_path ++ "halt_bug.gb",
    //     .system = .cpu, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 200 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    // .{ .path = blargg_path ++ "instr_timing/instr_timing.gb",
    //     .system = .cpu, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 140 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    // .{ .path = blargg_path ++ "mem_timing/individual/",
    //     .system = .memory, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 140 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    .{ .path = blargg_path ++ "mem_timing-2/rom_singles/",
        .system = .memory, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 140 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    // OAM Bug currently not implemented.
    // .{ .path = blargg_path ++ "oam_bug/rom_singles/",
    //     .system = .ppu, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 360 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },

    // .{ .path = bully_path ++ "bully.gb",
    //     .system = .all, .model = .dmg, .exit = .none, .timeout = .{ .frame = 140 }, .pass = .{ .screenshot = bully_path ++ "bully.png" }, .context = .none },

    // .{ .path = dmg_acid_path ++ "dmg-acid2.gb",
    //     .system = .ppu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .{ .screenshot = dmg_acid_path ++ "dmg-acid2-dmg.png" }, .context = .none },

    // TODO: This test loops, I need a new timeout exit condition.
    // .{ .path = mbc3_tester_path ++ "mbc3-tester.gb",
    //     .system = .cart, .model = .dmg, .exit = .none, .timeout = .{ .frame = 140 }, .pass = .{ .screenshot = mbc3_tester_path ++ "mbc3-tester-dmg.png" }, .context = .none },

    // .{ .path = mooneye_path ++ "acceptance/bits/",
    //     .system = .memory, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/boot/",
    //     .system = .memory, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 120 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/halt/",
    //     .system = .cpu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 120 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/instr/daa.gb",
    //     .system = .cpu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/instr_timing/",
    //     .system = .cpu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/interrupts/ie_push.gb",
    //     .system = .cpu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/oam_dma/",
    //     .system = .memory, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/ppu/",
    //     .system = .ppu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // Serial is currently not supported.
    // .{ .path = mooneye_path ++ "acceptance/serial/boot_sclk_align-dmgABCmgb.gb",
    //     .system = .ppu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/timer/",
    //     .system = .mmio, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "emulator-only/mbc1/",
    //     .system = .cart, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // MBC2 is currently not supported
    // .{ .path = mooneye_path ++ "emulator-only/mbc2/",
    //     .system = .cart, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "emulator-only/mbc5/",
    //     .system = .cart, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },

    // TODO: These test need a new timeout exit condition.
    // .{ .path = scribbltests ++ "lycscx/lycscx.gb",
    //     .system = .ppu, .model = .dmg, .exit = .none, .timeout = .{ .frame = 140 }, .pass = .{ .screenshot = scribbltests ++ "lycscx/lycscx-cgb-dmg.png" }, .context = .none },
    // .{ .path = scribbltests ++ "lycscy/lycscy.gb",
    //     .system = .ppu, .model = .dmg, .exit = .none, .timeout = .{ .frame = 140 }, .pass = .{ .screenshot = scribbltests ++ "lycscy/lycscy-cgb-dmg.png" }, .context = .none },
    // .{ .path = scribbltests ++ "palettely/palettely.gb",
    //     .system = .ppu, .model = .dmg, .exit = .none, .timeout = .{ .frame = 140 }, .pass = .{ .screenshot = scribbltests ++ "palettely/palettely-dmg.png" }, .context = .none },
    // .{ .path = scribbltests ++ "scxly/scxly.gb",
    //     .system = .ppu, .model = .dmg, .exit = .none, .timeout = .{ .frame = 140 }, .pass = .{ .screenshot = scribbltests ++ "scxly/scxly-dmg.png" }, .context = .none },
};

pub fn runTestRomsTests(filter: test_options.@"build.TestFilter") !void {
    const alloc = std.testing.allocator;
    var irq_joypad: bool = false;

    // TODO: consider using a temporary allocator (FixedBufferAllocator) for each test.
    // Allocate the memory for each test upfront. We are loosing 3 seconds for all blargg tests for example.
    // For each test_config or each core_config (can have multiple for directories).
    var hit_any_rom: bool = false;
    for (rom_test_configs) |test_config| {
        // TODO: Add a max test cycle count to the build options => don't do a test if it's cycle count is larger than that.
        if(filter != .all and test_config.system != filter) {
            continue;
        }
        hit_any_rom = true;

        const timeout_cycles: usize = test_config.getTimeoutCycles();
        const configs: []Config = try test_config.generateCoreConfigs(alloc);
        defer {
            if(configs.len > 1) { // directory => need to clean up strings
                for(configs) |config| if(config.files.rom) |rom| alloc.free(rom);
            }
            alloc.free(configs);
        }

        for(configs) |config| {
            var core: CoreType = .{};
            // TODO: Add to the config file if we support save files or not => do not create or open save files for test roms.
            core.init(alloc, config);
            defer core.deinit(alloc, config);

            var last_ppu_lcd_y: u8 = 0;
            var exit_cond_hit: bool = false;
            var cycle_count: u32 = 0;
            while(cycle_count <= timeout_cycles) : (cycle_count += 1) {
                core.cyle(&irq_joypad);
                exit_cond_hit = try test_config.exitConditionHit(alloc, &core, &last_ppu_lcd_y);
                if(exit_cond_hit) break;
            }

            std.testing.expectEqual(true, exit_cond_hit or test_config.exit == .none) catch |err| {
                std.debug.print("Failed: {s}: {s}\n", .{ config.files.rom.?, "rom has exit condition but it timed out." });
                return err;
            };

            const context: []const u8 = try test_config.getContext(alloc, &core);
            defer alloc.free(context);
            const passed: bool = test_config.passed(&core, context);
            std.testing.expectEqual(true, passed) catch |err| {
                std.debug.print("Failed: {s}\n", .{ config.files.rom.? });
                std.debug.print("Context: {s}\n", .{ context });
                return err;
            };
        }
    }

    if(!hit_any_rom) return error.SkipZigTest;
}
