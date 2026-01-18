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

// TODO: These should be imported.
const tile_base_address = 0x8000;
const tile_map_base_address = 0x9800;
const tile_map_size_x = 32;
const tile_map_size_y = 32;
const tile_size_byte = 16;

const mooneye_char_base_address = 0x8200;
// TODO: This is basically the ascii table from 32-127 (printable characters).
const mooneye_char_table = [96]u8{
    ' ', '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/', 
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?',
    '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O',
    'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_',
    '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~', ' ',
};
// TODO: This function works but seems pretty complex for what it does => rewrite it.
fn parseMoonEye(alloc: std.mem.Allocator, vram: [def.vram_size]u8) ![]const u8 {
    var writer: std.io.Writer.Allocating = .init(alloc);
    defer writer.deinit();

    for(0..tile_map_size_y) |y| {
        var line_has_content: bool = false;
        var line_writer: std.io.Writer.Allocating = .init(alloc);
        defer line_writer.deinit();

        const y_cast: u16 = @intCast(y);
        for(0..tile_map_size_x) |x| {
            const x_cast: u16 = @intCast(x);
            const tile_map_addr: u16 = tile_map_base_address + x_cast + (y_cast * tile_map_size_y);
            const vram_idx: u16 = tile_map_addr - def.vram_low;
            const tile_addr_offset: u16 = vram[vram_idx];
            const tile_addr: u16 = tile_base_address + (tile_addr_offset * tile_size_byte);
            const min: bool = tile_addr >= mooneye_char_base_address;
            const max: bool = tile_addr < (mooneye_char_base_address + (mooneye_char_table.len * tile_size_byte));
            const in_table: bool = min and max;
            const table_idx: u16 = if(in_table) (tile_addr - mooneye_char_base_address) / tile_size_byte else 0;
            const char: u8 = mooneye_char_table[table_idx];
            try line_writer.writer.writeByte(char);
            line_has_content |= (char != ' ');
        }
        try line_writer.writer.writeByte('\n');
        if(line_has_content) {
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
    timeout: union(enum) {
        cycle: usize,
        frame: usize,
        sec: usize,
    },
    pass: union(enum) {
        fibonacci: void,
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
    // TODO: Generate multiple Configs for directories
    pub fn generateCoreConfig(self: Self, alloc: std.mem.Allocator) ![]Config {
        const path_stat = try std.fs.cwd().statFile(self.path);
        return switch(path_stat.kind) {
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
    pub fn passed(self: Self, core: *const Core) bool {
        return switch(self.pass) {
            .memory => @panic("memory passing not yet supported"),
            .trace => @panic("memory passing not yet supported"),
            .fibonacci => fib: {
                const r8 = core.cpu.registers.r8;
                break: fib r8.b == 3 and r8.c == 5 and r8.d == 8 and r8.e == 13 and r8.h == 21 and r8.l == 34;
            },
            .screenshot => @panic("memory passing not yet supported"),
        };
    }
    // TODO: How to do that for the other cases? What is their output?
    pub fn getFailContext(self: Self, alloc: std.mem.Allocator, core: *const Core, did_pass: bool) ![]const u8 {
        if(did_pass) return "";
        return switch(self.fail_ctx) {
            .none => "",
            .memory => "",
            .screenshot => "",
            .text_parsing => |parse_type| parse: {
                break: parse switch (parse_type) {
                    .blargg => "",
                    .gambatte => "",
                    .mooneye => try parseMoonEye(alloc, core.ppu.vram),
                };
            },
        };
    }
};
// TODO: How do we filter for specific systems? Example: I am working on the cpu and I want to only run cpu test roms + my cpu unit tests.
const mooneye_path = "playground/game-boy-test-roms/mooneye-test-suite/";

// TODO: How can I use a directory? All mooneye tests are the same for example.
//  => But this also has exceptions.
//  => For directory also define if it is just this directoy or all subdirectories.
//  TODO: Is there a way to define 
const rom_test_configs: [1]RomTestConfig = .{
    .{ .path = mooneye_path ++ "acceptance/div_timing.gb", 
        .systems = 0, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 100 }, .pass = .fibonacci, .fail_ctx = .{ .text_parsing = .mooneye } },
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
            const passed: bool = test_config.passed(&core);
            const fail_ctx: []const u8 = try test_config.getFailContext(alloc, &core, passed);
            defer alloc.free(fail_ctx);
            std.testing.expectEqual(true, passed) catch |err| {
                std.debug.print("Failed: {s}\n", .{ test_config.path });
                std.debug.print("Context: {s}\n", .{ fail_ctx });
                return err;
            };
        }
    }
}

// TODO: Just some old code keeping for reference for now.
//
// test "blargg" {
//     const testRoms =  [_][]const u8{
//         "test_data/blargg_roms/cpu_instrs/individual/01-special.gb", 
//         // "test_data/blargg_roms/cpu_instrs/individual/02-interrupts.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/03-op sh,hl.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/04-op r,imm.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/05-op rp.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/06-ld r,r.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/07-jr,jp,call.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/08-misc instrs.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/09-op r,r.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/10-bit ops.gb", 
//         "test_data/blargg_roms/cpu_instrs/individual/11-op a,(hl).gb", 
//     }; 
//
//     const alloc = std.testing.allocator;
//
//     for (testRoms, 0..) |testRom, i| {
//         std.debug.print("{d}: Testing: {s}\n", .{i, testRom});
//         var cpu = try _cpu.CPU.init(alloc, testRom);
//         defer cpu.deinit();
//
//         var lastPC: u16 = 0;
//         while (lastPC != cpu.pc) {
//             lastPC = cpu.pc;
//             try cpu.frame();
//         }
//
//         const output: std.ArrayList(u8) = try blargg.parseOutput(&cpu, alloc);
//         defer output.deinit();
//
//         const passed: bool = blargg.hasPassed(&output);
//         if (!passed) {
//             std.debug.print("{s}\n", .{output.items});
//         }
//         try std.testing.expect(passed);
//     }
// }
//
//
//
// const std = @import("std");
//
// const CHAR_TABLE = [96]u8{
//     ' ', '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/', 
//     '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?',
//     '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O',
//     'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_',
//     '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
//     'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~', ' ',
// };
//
// // TODO: These should be imported.
// const TILE_BASE_ADDRESS = 0x8000;
// const TILE_MAP_BASE_ADDRESS = 0x9800;
// const TILE_MAP_SIZE_X = 32;
// const TILE_MAP_SIZE_Y = 32;
// const TILE_SIZE_BYTE = 16;
//
// const WHITE_CHAR_BASE_ADDRESS = 0x8200;
// const BLACK_CHAR_BASE_ADDRESS = 0x8A00;
//
// pub fn parseOutput(memory: *const []8, alloc: std.mem.Allocator) !std.ArrayList(u8) {
//     std.debug.assert(memory.len == 0x10000);
//
//     var string = std.ArrayList(u8).init(alloc);
//     errdefer string.deinit();
//
//     var y: u16 = 0;
//     while (y < TILE_MAP_SIZE_Y) : (y += 1) {
//         var lineIsEmpty = true;
//         var line = try std.BoundedArray(u8, TILE_MAP_SIZE_X + 1).init(0);
//
//         var x: u16 = 0;
//         while (x < TILE_MAP_SIZE_X) : (x += 1) {
//             const tileMapAddress: u16 = TILE_MAP_BASE_ADDRESS + x + (y * TILE_MAP_SIZE_Y);
//             const tileAddressOffset: u16 align(1) = memory.*[tileMapAddress];
//             const tileAddress: u16 = TILE_BASE_ADDRESS + (tileAddressOffset * TILE_SIZE_BYTE);
//
//             const charBaseAddress: u16 = if (tileAddress >= BLACK_CHAR_BASE_ADDRESS) BLACK_CHAR_BASE_ADDRESS else WHITE_CHAR_BASE_ADDRESS;
//             const relativeIndex: u16 = (tileAddress - charBaseAddress) / TILE_SIZE_BYTE;
//
//             const char: u8 = CHAR_TABLE[relativeIndex];
//             if(lineIsEmpty and char != ' ') lineIsEmpty = false;
//             try line.append(char);
//         }
//         
//         if(lineIsEmpty) {
//             continue;
//         }
//
//         try line.append('\n');
//         for (line.slice()) |char| {
//             try string.append(char);
//         }
//     }
//
//     return string;
// }
//
// pub fn hasPassed(output: *const std.ArrayList(u8)) bool {
//     return std.mem.count(u8, output.*.items, "Passed") > 0;
// }
