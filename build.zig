const std = @import("std");
const builtin = @import("builtin");

pub const CPUModel = enum { instruction, cycle };
pub const PPUModel = enum { void, frame, cycle };
pub const APUModel = enum { void, cycle };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // flags
    // llvm backend required for vscode debug symbols and performance is bad with self-hosted backend.
    const enable_llvm = b.option(bool, "enable-llvm", "Enable llvm backed to allow debug symbols in vscode") orelse true;
    const cpu_model = b.option(CPUModel, "cpu_model", "Use a specific ppu model.") orelse CPUModel.cycle;
    const ppu_model = b.option(PPUModel, "ppu_model", "Use a specific ppu model.") orelse PPUModel.cycle;
    const apu_model = b.option(APUModel, "apu_model", "Use a specific apu model.") orelse APUModel.cycle;

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

    // exe options
    const options = b.addOptions();
    options.addOption(CPUModel, "cpu_model", cpu_model);
    options.addOption(PPUModel, "ppu_model", ppu_model);
    options.addOption(APUModel, "apu_model", apu_model);
    exe.root_module.addOptions("build_options", options);

    // sokol
    const sokol = b.dependency("sokol", .{ .target = target, .optimize = optimize, .with_sokol_imgui = true });
    exe.root_module.addImport("sokol", sokol.module("sokol"));

    // cimgui
    const cimgui = b.dependency("cimgui", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("cimgui", cimgui.module("cimgui"));
    sokol.artifact("sokol_clib").addIncludePath(cimgui.path("src"));

    // shader
    buildShader(b);

    // run
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // tests
    // TODO: Put this in it's own build script?
    // TODO: Think about a better test setup using modules.
    const exe_unit_tests = b.addTest(.{
        .name = "test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = if(builtin.os.tag == .windows) true else enable_llvm,
    });
    exe_unit_tests.root_module.addImport("sokol", sokol.module("sokol"));
    exe_unit_tests.root_module.addImport("cimgui", cimgui.module("cimgui"));
    b.installArtifact(exe_unit_tests);

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn buildShader(b: *std.Build) void {
    const tool_dir = "tools/sokol-shdc/";
    const shaders_in ="src/shaders/";
    const shaders_out = "src/shaders/";
    const shaders = .{
        "gb.glsl",
    };
    
    const sdhc_platform: ?[:0]const u8 = comptime switch(builtin.os.tag) {
        .windows => "win32/sokol-shdc.exe",
        .linux => if (builtin.cpu.arch.isX86()) "linux/sokol-shdc" else "linux_arm64/sokol-shdc",
        .macos => if (builtin.cpu.arch.isX86()) "osx/sokol-shdc" else "osx_arm64/sokol-shdc",
        else => null,
    };
    if(sdhc_platform == null) {
        std.log.warn("unsupported host platform, skipping shader compiler step", .{});
        return;
    }

    const sdhc_path = tool_dir ++ sdhc_platform.?;
    const sdhc_step = b.step("shaders", "Compile shaders using sokol-shdc");
    const shader_lang = "glsl430:metal_macos:hlsl5:glsl300es";
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
