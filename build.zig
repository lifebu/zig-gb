const std = @import("std");
const builtin = @import("builtin");

// exe
pub const CPUModel = enum { instruction, cycle };
pub const PPUModel = enum { void, frame, cycle };
pub const APUModel = enum { void, cycle };

// text
pub const TestCategory = enum { all, cart, instr, cpu, memory, mmio, ppu, apu };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // exe flags
    // llvm backend required for vscode debug symbols and performance is bad with self-hosted backend.
    const enable_llvm = b.option(bool, "enable_llvm", "Enable llvm backed to allow debug symbols in vscode") orelse true;
    const enable_audio = b.option(bool, "enable_audio", "Enables the audio output") orelse (optimize != .Debug);
    const cpu_model = b.option(CPUModel, "cpu_model", "Use a specific ppu model.") orelse CPUModel.cycle;
    const ppu_model = b.option(PPUModel, "ppu_model", "Use a specific ppu model.") orelse PPUModel.cycle;
    const apu_model = b.option(APUModel, "apu_model", "Use a specific apu model.") orelse APUModel.cycle;
    const tracy_enabled = b.option(bool, "tracy", "Build with Tracy support.") orelse true;

    // test flags
    const test_category = b.option(TestCategory, "test_category", "Filters all tests to a specific subsystem.") orelse TestCategory.all;
    const test_filter = b.option([]const u8, "test_filter", "Only do a test with this name");
    const test_exclude = b.option([]const u8, "test_exclude", "Exclude these tests from the current run (comma seperated list).");

    // exe
    const exe = b.addExecutable(.{
        .name = "zig-gb",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = if(builtin.os.tag == .windows) true else enable_llvm,
    });
    b.installArtifact(exe);

    const exe_options = b.addOptions();
    exe_options.addOption(CPUModel, "cpu_model", cpu_model);
    exe_options.addOption(PPUModel, "ppu_model", ppu_model);
    exe_options.addOption(APUModel, "apu_model", apu_model);
    exe_options.addOption(bool, "tracy_enabled", tracy_enabled);
    exe_options.addOption(bool, "enable_audio", enable_audio);
    exe.root_module.addOptions("build_options", exe_options);

    const sokol = b.dependency("sokol", .{ .target = target, .optimize = optimize, .with_sokol_imgui = true });
    exe.root_module.addImport("sokol", sokol.module("sokol"));
    addSokolShaderCompiler(b);

    const cimgui = b.dependency("cimgui", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("cimgui", cimgui.module("cimgui"));
    sokol.artifact("sokol_clib").addIncludePath(cimgui.path("src"));

    const tracy = b.dependency("tracy", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("tracy", tracy.module("tracy"));
    const tracy_impl_enabled: *std.Build.Module = tracy.module("tracy_impl_enabled");
    const tracy_impl_disabled: *std.Build.Module = tracy.module("tracy_impl_disabled");
    exe.root_module.addImport("tracy_impl", if(tracy_enabled) tracy_impl_enabled else tracy_impl_disabled);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_exe.step);



    // tests
    // TODO: Think about a better test setup using modules.
    const tests = b.addTest(.{
        .name = "test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = if(builtin.os.tag == .windows) true else enable_llvm,
    });
    b.installArtifact(tests);

    const test_options = b.addOptions();
    test_options.addOption(TestCategory, "test_category", test_category);
    test_options.addOption(?[]const u8, "test_filter", test_filter);
    test_options.addOption(?[]const u8, "test_exclude", test_exclude);
    tests.root_module.addOptions("test_options", test_options);

    tests.root_module.addImport("sokol", sokol.module("sokol"));
    tests.root_module.addImport("cimgui", cimgui.module("cimgui"));
    tests.root_module.addImport("tracy", tracy.module("tracy"));
    tests.root_module.addImport("tracy_impl", tracy_impl_disabled);

    const run_tests = b.addRunArtifact(tests);
    const tests_step = b.step("test", "Run unit tests");
    tests_step.dependOn(&run_tests.step);
}

fn addSokolShaderCompiler(b: *std.Build) void {
    const tool_dir = "tools/sokol-shdc/";
    const shaders_in ="src/shaders/";
    const shaders_out = "src/shaders/";

    const shader_lang = "glsl430:metal_macos:hlsl5:glsl300es";
    const shaders = .{ "gb.glsl" };
    
    const shdc_platform: [:0]const u8 = comptime switch(builtin.os.tag) {
        .windows => "win32/sokol-shdc.exe",
        .linux => if (builtin.cpu.arch.isX86()) "linux/sokol-shdc" else "linux_arm64/sokol-shdc",
        .macos => if (builtin.cpu.arch.isX86()) "osx/sokol-shdc" else "osx_arm64/sokol-shdc",
        else => {
            std.log.warn("shader compiler is unsupported on host platform {}.", .{ @tagName(builtin.os.tag) });
            return;
        },
    };

    const sdhc_path = tool_dir ++ shdc_platform;
    const sdhc_step = b.step("shaders", "Compile shaders using sokol-shdc");
    inline for (shaders) |shader| {
        const cmd = b.addSystemCommand(&.{ sdhc_path, 
            "-i", shaders_in ++ shader, 
            "-o", shaders_out ++ shader ++ ".zig",
            "-l", shader_lang,
            "-f", "sokol_zig", "--reflection",
        });
        sdhc_step.dependOn(&cmd.step);
    }
}
