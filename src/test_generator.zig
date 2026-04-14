const std = @import("std");
// TODO: Changes to the test_category seem to retrigger a build for the generator?
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
const unit_tests: [5]UnitTestConfig = .{
    //.{ .file = "apu", .category = .apu , .test_functions = &.{ "runApuChannelTests" } },
    //.{ .file = "apu_sampling", .category = .apu, .test_functions = &.{ "runApuSampingTests", "runApuOutputTest" } },
    .{ .file = "cart", .category = .cart , .test_functions = &.{ "runCartTests" } },
    .{ .file = "halt", .category = .cpu , .test_functions = &.{ "runHaltTests" } },
    .{ .file = "interrupt", .category = .cpu , .test_functions = &.{ "runInterruptTests" } },
    .{ .file = "memory", .category = .memory , .test_functions = &.{ "runDMATest", "runRequestTest" } },
    .{ .file = "mmio", .category = .mmio , .test_functions = &.{ "runDividerTests", "runInputTests", "runTimerTest" } },
    //.{ .file = "ppu", .category = .ppu , .test_functions = &.{ "runInterruptTests" } },
    //.{ .file = "singlestep_test", .category = .instruction , .test_functions = &.{ "runSingleStepTests" } },
};

// rom tests
const RomTestConfig = struct {
    path: []const u8,
    file_filter: []const []const u8 = &.{},
    force_boot_rom: bool = false,
    category: test_options.@"build.TestCategory",
    // TODO: Use the contents of the filename to determine for which model this config would be and set emulation.model.
    // Use this later to filter out tests that do not work on a specific model.
    // This might need different "detection" methods (as people use different naming schemes).
    // Add a new enum: model_detection for the detection method.
    model: def.GBModel,
    exit: rom_runner.ExitCondition,
    timeout: rom_runner.Timeout,
    pass: rom_runner.Pass,
    context: rom_runner.Context,
};

const age_path = "test_data/roms/age-test-roms/";
const blargg_path = "test_data/roms/blargg/";
const bully_path = "test_data/roms/bully/";
const dmg_acid_path = "test_data/roms/dmg-acid2/";
const mbc3_tester_path = "test_data/roms/mbc3-tester/";
const mooneye_path = "test_data/roms/mooneye-test-suite/";
const scribbltests = "test_data/roms/scribbltests/";
const rom_tests: [6]RomTestConfig = .{
    // TODO: Add Age tests for halt => requires new type of text parsing
    // .{ .path = age_path ++ "halt/",
    //     .category = .cpu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .age } },

    .{ .path = blargg_path ++ "dmg_sound/rom_singles/",
        .category = .apu, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 360 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    .{ .path = blargg_path ++ "cpu_instrs/individual/",
        .category = .instr, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 1160 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    .{ .path = blargg_path ++ "halt_bug.gb",
        .category = .cpu, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 200 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    .{ .path = blargg_path ++ "instr_timing/instr_timing.gb",
        .category = .instr, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 140 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    .{ .path = blargg_path ++ "mem_timing/individual/",
        .category = .memory, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 140 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    .{ .path = blargg_path ++ "mem_timing-2/rom_singles/",
        .category = .memory, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 140 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },
    // OAM Bug currently not implemented.
    // .{ .path = blargg_path ++ "oam_bug/rom_singles/",
    //     .category = .ppu, .model = .dmg, .exit = .blargg, .timeout = .{ .frame = 360 }, .pass = .{ .text = "Passed" }, .context = .{ .text_parsing = .blargg } },

    // TODO: This does not work in the text? there is now output on the vram?
    // .{ .path = bully_path ++ "bully.gb",
    //     .category = .memory, .model = .dmg, .exit = .timeout, .timeout = .{ .frame = 120 }, .pass = .{ .text = "All tests OK!" }, .context = .{ .text_parsing = .bully } },

    // .{ .path = mbc3_tester_path ++ "mbc3-tester.gb",
    //     .category = .cart, .model = .dmg, .exit = .timeout, .timeout = .{ .frame = 120 }, .pass = .mbc3, .context = .{ .text_parsing = .mbc3 } },

    // .{ .path = mooneye_path ++ "acceptance/bits/", 
    //     .file_filter = &.{ "-GS.gb" },
    //     .category = .memory, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/boot/", .force_boot_rom = true,
    //     .file_filter = &.{ "-dmg0.gb", "-S.gb", "-mgb.gb", "-sgb.gb", "-sgb2.gb" },
    //     .category = .memory, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 120 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // halt_ime1_timing2-GS.gb does not work without the boot rom, why?
    // .{ .path = mooneye_path ++ "acceptance/halt/", .force_boot_rom = true,
    //     .category = .cpu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 120 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/instr/daa.gb",
    //     .category = .instr, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/instr_timing/",
    //     .category = .instr, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/interrupts/",
    //     .category = .cpu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/oam_dma/",
    //     .category = .memory, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/ppu/",
    //     .category = .ppu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // Serial is currently not supported.
    // .{ .path = mooneye_path ++ "acceptance/serial/boot_sclk_align-dmgABCmgb.gb",
    //     .category = .ppu, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "acceptance/timer/",
    //     .category = .mmio, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // We don't support mbc1 roms with more than 512kByte (alternative wiring).
    // .{ .path = mooneye_path ++ "emulator-only/mbc1/", 
    //     .file_filter = &.{ "multicart_rom_8Mb", "rom_1Mb", "rom_2Mb", "rom_4Mb", "rom_8Mb", "rom_16Mb"},
    //     .category = .cart, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 360 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // MBC2 is currently not supported
    // .{ .path = mooneye_path ++ "emulator-only/mbc2/",
    //     .category = .cart, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },
    // .{ .path = mooneye_path ++ "emulator-only/mbc5/",
    //     .category = .cart, .model = .dmg, .exit = .breakpoint, .timeout = .{ .frame = 140 }, .pass = .fibonacci, .context = .{ .text_parsing = .mooneye } },

    // TODO: Add support for same-suite tests, one test is for ei-di and halt delays.
};

// TODO: Use actual name for this later (maybe get this from the build script?)
const output_file_path = "src/test2.zig";
// TODO: Try to combine some of them?
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
;
const output_unit_import = 
    \\const {0s}_test = @import("tests/{0s}.test.zig");
    \\
;
const output_unit_test =
    \\test "{0s}_{1s}" {{
    \\    if (category != .all and category != .{0s}) {{
    \\        return error.SkipZigTest;
    \\    }}
    \\    try {2s}_test.{1s}();
    \\}}
    \\
    \\
;
// TODO: all tests should be named suite_category_test. "unit" is the unit test suite.
const output_rom_test_start =
    \\test "{0s}_{1s}" {{
    \\    if (category != .all and category != .{0s}) {{
    \\        return error.SkipZigTest;
    \\    }}
    \\    if (rom_test.isFiltered("{2s}")) {{
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
    \\    const core_config: Config = rom_test.genCoreConfig(.{0s}, {1s}, "{2s}");
    \\
;
const output_rom_test_end =
    \\    try rom_test.run(.{{ .exit = exit, .timeout = timeout, .pass = pass, .context = context, .core_config = core_config }});
    \\}}
    \\
    \\
;

pub fn main() !void {
    var timer: std.time.Timer = try .start();
    defer {
        const elapsed: f64 = @floatFromInt(timer.read());
        std.log.info("Tests generated in: {d:.2}ms", .{ elapsed / std.time.ns_per_ms });
    }

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const alloc: std.mem.Allocator = gpa.allocator();

    var writer: std.io.Writer.Allocating = .init(alloc);
    defer writer.deinit();

    try writer.writer.writeAll(output_start);
    try writeUnitTests(&writer.writer);
    try writeRomTests(&writer.writer, alloc);

    var result: std.ArrayList(u8) = writer.toArrayList();
    defer result.deinit(alloc);
    std.fs.cwd().writeFile(.{ .data = result.items, .sub_path = output_file_path }) catch unreachable;
}

fn writeUnitTests(writer: *std.io.Writer) !void {
    for(unit_tests) |unit_test| {
        try writer.print(output_unit_import, .{ unit_test.file });
        for(unit_test.test_functions) |unit_test_function| {
            try writer.print(output_unit_test, .{ @tagName(unit_test.category), unit_test_function, unit_test.file });
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

fn findRomFilesInPath(rom_test: RomTestConfig, alloc: std.mem.Allocator) ![][]const u8 {
    // TODO: Here I seem to make a lot of unecessary allocations?
    var result: std.ArrayList([]const u8) = .empty;
    defer result.deinit(alloc);

    const path_stat = try std.fs.cwd().statFile(rom_test.path);
    switch(path_stat.kind) {
        .directory => {
            const dir: std.fs.Dir = try std.fs.cwd().openDir(rom_test.path, .{ .iterate = true });
            var iter = dir.iterate();
            while(iter.next() catch unreachable) |entry| {
                if(entry.kind != .file or !isFileAllowed(rom_test, entry.name)) {
                    continue;
                }

                const full_path: []const u8 = try std.fmt.allocPrint(alloc, "{s}{s}", .{ rom_test.path, entry.name });
                try result.append(alloc, full_path);
            }
        },
        .file => {
            if(!isFileAllowed(rom_test, rom_test.path)) {
                @panic("Not allowed rom file is configured in the test generator!");
            }

            const full_path: []const u8 = try alloc.dupe(u8, rom_test.path);
            try result.append(alloc, full_path);
        },
        else => @panic("Unknown type of path in test rom config!"),
    }
    return try result.toOwnedSlice(alloc);
}


fn writeRomTests(writer: *std.io.Writer, alloc: std.mem.Allocator) !void {
    for(rom_tests) |rom_test| {
        const rom_files: [][]const u8 = try findRomFilesInPath(rom_test, alloc);
        defer {
            for(rom_files) |rom_file| { alloc.free(rom_file); }
            alloc.free(rom_files);
        }

        for(rom_files) |rom_file| {
            try writer.print(output_rom_test_start, .{ @tagName(rom_test.category), rom_file, rom_file });
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
            const bool_value: []const u8 = if(rom_test.force_boot_rom) "true" else "false";
            try writer.print(output_rom_core, .{ @tagName(rom_test.model), bool_value, rom_file});
            try writer.print(output_rom_test_end, .{});
        }
    }
}
