const std = @import("std");
const test_options = @import("test_options");

const Config = @import("config.zig");
const def = @import("defines.zig");
const rom_runner = @import("tests/util/rom_runner.zig");

// unit tests
const UnitTestConfig = struct {
    file: []const u8 = undefined,
    category: test_options.@"build.TestCategory" = .all,
    test_functions: []const []const u8 = undefined,
};

const unit_test_folder = "src/tests/";
const unit_tests: [7]UnitTestConfig = .{
    //.{ .file = "apu", .category = .apu , .test_functions = &.{ "ApuChannel" } },
    //.{ .file = "apu_sampling", .category = .apu, .test_functions = &.{ "ApuSampling", "ApuOutput" } },
    .{ .file = "cart", .category = .cart , .test_functions = &.{ "Cart" } },
    .{ .file = "cpu", .category = .cpu , .test_functions = &.{ "Register" } },
    .{ .file = "halt", .category = .cpu , .test_functions = &.{ "Halt" } },
    .{ .file = "interrupt", .category = .cpu , .test_functions = &.{ "Interrupt" } },
    .{ .file = "memory", .category = .memory , .test_functions = &.{ "DMA", "Request" } },
    .{ .file = "mmio", .category = .mmio , .test_functions = &.{ "Divider", "Input", "Timer" } },
    //.{ .file = "ppu", .category = .ppu , .test_functions = &.{ "Interrupt" } },
    .{ .file = "singlestep", .category = .instr, .test_functions = &.{ "SingleStep" } },
};

// rom tests
const RomTestSuite = enum {
    age, blargg, bully, dmg_acid, mbc3_tester, mooneye, scribbltests,
};
const RomTestConfig = struct {
    suite: RomTestSuite,
    sub_path: []const u8,
    file_filter: []const []const u8 = &.{},
    force_boot_rom: bool = false,
    category: test_options.@"build.TestCategory",
    model: def.GBModel,
    exit: rom_runner.ExitCondition,
    timeout: rom_runner.Timeout,
    pass: rom_runner.Pass,
    context: rom_runner.Context,

    fn getSuitePath(self: *const RomTestConfig) []const u8 {
        return switch (self.suite) {
            .age => "test_data/roms/age-test-roms/",
            .blargg => "test_data/roms/blargg/",
            .bully => "test_data/roms/bully/",
            .dmg_acid => "test_data/roms/dmg-acid2/",
            .mbc3_tester => "test_data/roms/mbc3-tester/",
            .mooneye => "test_data/roms/mooneye-test-suite/",
            .scribbltests => "test_data/roms/scribbltests/",
        };
    } 
};

const rom_tests: [18]RomTestConfig = .{
    // TODO: Add Age tests for halt => requires new type of text parsing
    // .{ .suite = .age, .sub_path = age_path ++ "halt/",
    //     .category = .cpu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .age } },

    .{ .suite = .blargg, .sub_path = "dmg_sound/rom_singles/",
        .category = .apu, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 360 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    .{ .suite = .blargg, .sub_path = "cpu_instrs/individual/",
        .category = .instr, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 1160 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    .{ .suite = .blargg, .sub_path = "halt_bug.gb",
        .category = .cpu, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 200 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    .{ .suite = .blargg, .sub_path = "instr_timing/instr_timing.gb",
        .category = .instr, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 140 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    .{ .suite = .blargg, .sub_path = "mem_timing/individual/",
        .category = .memory, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 140 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    .{ .suite = .blargg, .sub_path = "mem_timing-2/rom_singles/",
        .category = .memory, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 140 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    // Note: OAM Bug currently not implemented.
    // .{ .suite = .blargg, .sub_path = blargg_path ++ "oam_bug/rom_singles/",
    //     .category = .ppu, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 360 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },

    // TODO: This does not work in the text? there is now output on the vram?
    // .{ .suite = .bully, .sub_path = bully_path ++ "bully.gb",
    //     .category = .memory, .model = .dmg, .exit = .timeout, .timeout = .{ .frame = 120 }, .pass = .{ .text = "All tests OK!" }, .context = .{ .text_parsing = .bully } },

    .{ .suite = .mbc3_tester, .sub_path = "mbc3-tester.gb",
        .category = .cart, .model = .dmg, .exit = .timeout, .timeout = .{ .frame = 120 }, .pass = .mbc3, .context = .{ .text_parsing = .mbc3 } },

    .{ .suite = .mooneye, .sub_path = "acceptance/bits/", 
        .file_filter = &.{ "-GS.gb" },
        .category = .memory, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    .{ .suite = .mooneye, .sub_path = "acceptance/boot/", .force_boot_rom = true,
        .file_filter = &.{ "-dmg0.gb", "-S.gb", "-mgb.gb", "-sgb.gb", "-sgb2.gb" },
        .category = .memory, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 120 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // TODO: halt_ime1_timing2-GS.gb does not work without the boot rom, why?
    .{ .suite = .mooneye, .sub_path = "acceptance/halt/", .force_boot_rom = true,
        .category = .cpu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 120 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    .{ .suite = .mooneye, .sub_path = "acceptance/instr/daa.gb",
        .category = .instr, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    .{ .suite = .mooneye, .sub_path = "acceptance/instr_timing/",
        .category = .instr, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    .{ .suite = .mooneye, .sub_path = "acceptance/interrupts/",
        .category = .cpu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    .{ .suite = .mooneye, .sub_path = "acceptance/oam_dma/",
        .category = .memory, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    .{ .suite = .mooneye, .sub_path = "acceptance/ppu/",
        .category = .ppu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // Note: Serial is currently not supported.
    // .{ .suite = .mooneye, .sub_path = mooneye_path ++ "acceptance/serial/boot_sclk_align-dmgABCmgb.gb",
    //     .category = .ppu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    .{ .suite = .mooneye, .sub_path = "acceptance/timer/",
        .category = .mmio, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // Note: We don't support mbc1 roms with more than 512kByte (alternative wiring).
    .{ .suite = .mooneye, .sub_path = "emulator-only/mbc1/", 
        .file_filter = &.{ "multicart_rom_8Mb", "rom_1Mb", "rom_2Mb", "rom_4Mb", "rom_8Mb", "rom_16Mb"},
        .category = .cart, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // Note: MBC2 is currently not supported
    // .{ .suite = .mooneye, .sub_path = mooneye_path ++ "emulator-only/mbc2/",
    //     .category = .cart, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    .{ .suite = .mooneye, .sub_path = "emulator-only/mbc5/",
        .category = .cart, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },

    // TODO: Add support for same-suite tests, one test is for ei-di and halt delays.
};

const output_file_path = "src/test.zig";
const output_start = 
    \\/////////////////////////////////////////////////
    \\/// AUTO GENERATED FILE. DO NOT EDIT MANUALLY
    \\/// GENERATED BY 'zig build test'
    \\/////////////////////////////////////////////////
    \\
    \\const std = @import("std");
    \\const test_options = @import("test_options");
    \\const category = test_options.test_category;
    \\
    \\const Config = @import("config.zig");
    \\const rom_test = @import("tests/util/rom_runner.zig");
    \\
    \\
    \\
;
const output_unit_import = 
    \\const {0s}_test = @import("tests/{0s}.test.zig");
    \\
;
const output_unit_test =
    \\test "{0s}_{1s}_{2s}" {{
    \\    if (category != .all and category != .{1s}) {{
    \\        return error.SkipZigTest;
    \\    }}
    \\    try {3s}_test.run{2s}Tests();
    \\}}
    \\
    \\
;
const output_rom_test_start =
    \\test "{0s}_{1s}_{2s}_{3s}" {{
    \\    if (category != .all and category != .{1s}) {{
    \\        return error.SkipZigTest;
    \\    }}
    \\    if (rom_test.isFiltered("{4s}")) {{
    \\        return error.SkipZigTest;
    \\    }}
    \\
    \\
;
const output_rom_exit =
    \\    const exit: rom_test.ExitCondition = .{0s};
    \\
;
const output_rom_timeout =
    \\    const timeout: rom_test.Timeout = .{{ .{0s} = {1} }};
    \\
;
const output_rom_pass_void =
    \\    const pass: rom_test.Pass = .{0s};
    \\
;
const output_rom_pass_text =
    \\    const pass: rom_test.Pass = .{{ .{0s} = "{1s}" }};
    \\
;
const output_rom_context_void =
    \\    const context: rom_test.Context = .{0s};
    \\
;
const output_rom_context_text_parsing =
    \\    const context: rom_test.Context = .{{ .{0s} = .{1s} }};
    \\
;
const output_rom_core =
    \\    const core_config: Config = rom_test.genCoreConfig(.{0s}, {1any}, "{2s}");
    \\
;
const output_rom_test_end =
    \\    try rom_test.run(.{{ .exit = exit, .timeout = timeout, .pass = pass, .context = context, .core_config = core_config }});
    \\}}
    \\
    \\
;

pub fn main(pinit: std.process.Init) !void {
    var start: std.Io.Timestamp = .now(pinit.io, .awake);

    var buffer: [85_000]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try writer.writeAll(output_start);
    try writeUnitTests(&writer);
    try writeRomTests(pinit.io, &writer);

    const result: []u8 = writer.buffered();
    std.Io.Dir.cwd().writeFile(pinit.io, .{ .data = result, .sub_path = output_file_path }) catch unreachable;

    const elapsed: std.Io.Duration = start.untilNow(pinit.io, .awake);
    //const elapsed_us: f32 =  @floatFromInt(elapsed.toMicroseconds());
    const mem_used: f32 = @floatFromInt(result.len);
    const mem_total: f32 = @floatFromInt(buffer.len);

    std.log.info("Generator: Total time: {f}", .{ elapsed });
    std.log.info("Generator: Memory usage: {B} ({d:.2}%)", .{ result.len, (mem_used / mem_total) * 100.0 });
}

fn writeUnitTests(writer: *std.Io.Writer) !void {
    for(unit_tests) |unit_test| {
        try writer.print(output_unit_import, .{ unit_test.file });
        for(unit_test.test_functions) |unit_test_function| {
            try writer.print(output_unit_test, .{ "unit", @tagName(unit_test.category), unit_test_function, unit_test.file });
        }
    }
}

fn isFileAllowed(rom_test: RomTestConfig, path: []const u8) bool {
    if( !std.mem.eql(u8, std.fs.path.extension(path), ".gb") and 
        !std.mem.eql(u8, std.fs.path.extension(path), ".gbc")) {
        return false;
    }
    for(rom_test.file_filter) |filter| {
        if(std.mem.containsAtLeast(u8, path, 1, filter)) {
            return false;
        }
    }

    return true;
}

fn writeRomTests(io: std.Io, writer: *std.Io.Writer) !void {
    for(rom_tests) |rom_test| {
        const suite_path: []const u8 = rom_test.getSuitePath();
        var path_buffer: [128]u8 = undefined;
        const relative_path: []const u8 = try std.fmt.bufPrint(&path_buffer, "{s}{s}", .{ suite_path, rom_test.sub_path });

        const path_stat = try std.Io.Dir.cwd().statFile(io, relative_path, .{});
        switch (path_stat.kind) {
            .directory => {
                const dir: std.Io.Dir = try std.Io.Dir.cwd().openDir(io, relative_path, .{ .iterate = true });
                var iter = dir.iterate();
                while (iter.next(io) catch unreachable) |entry| {
                    if (entry.kind != .file or !isFileAllowed(rom_test, entry.name)) {
                        continue;
                    }

                    var full_path_buffer: [128]u8 = undefined;
                    const full_path: []const u8 = try std.fmt.bufPrint(&full_path_buffer, "{s}{s}", .{ relative_path, entry.name });
                    try writeOneRomTest(writer, rom_test, full_path);
                }
            },
            .file => {
                if (!isFileAllowed(rom_test, relative_path)) {
                    @panic("Not allowed rom file is configured in the test generator!");
                }

                try writeOneRomTest(writer, rom_test, relative_path);
            },
            else => @panic("Unknown type of path in test rom config!"),
        }
    }
}

fn writeOneRomTest(writer: *std.Io.Writer, rom_test: RomTestConfig, rom_file: []const u8) !void {
    const file_name: []const u8 = std.fs.path.stem(rom_file);

    try writer.print(output_rom_test_start, .{ @tagName(rom_test.suite), @tagName(rom_test.category), rom_test.sub_path, file_name, file_name });
    try writer.print(output_rom_exit, .{ @tagName(rom_test.exit) });
    switch (rom_test.timeout) {
        .cycle => |value| try writer.print(output_rom_timeout, .{ @tagName(rom_test.timeout), value}),
        .frame => |value| try writer.print(output_rom_timeout, .{ @tagName(rom_test.timeout), value}),
        .sec => |value| try writer.print(output_rom_timeout, .{ @tagName(rom_test.timeout), value}),
    }
    switch (rom_test.pass) {
        .fibonacci, .mbc3 => try writer.print(output_rom_pass_void, .{ @tagName(rom_test.pass) }),
        .memory => unreachable, // Does not seem to be used right now?
        .text => |value| try writer.print(output_rom_pass_text, .{ @tagName(rom_test.pass), value }),
    }
    switch (rom_test.context) {
        .none, => try writer.print(output_rom_context_void, .{ @tagName(rom_test.context) }),
        .memory => unreachable, // Does not seem to be used right now?
        .text_parsing => |value| try writer.print(output_rom_context_text_parsing, .{ @tagName(rom_test.context), @tagName(value) }),
    }
    try writer.print(output_rom_core, .{ @tagName(rom_test.model), rom_test.force_boot_rom, rom_file});
    try writer.print(output_rom_test_end, .{});
}
