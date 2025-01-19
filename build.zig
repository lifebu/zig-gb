const std = @import("std");
const sfml = @import("sfml");

pub fn build(b: *std.Build) void {
    const src_folder = "src2/";

    // exe
    // TODO: Try to disable AVX-512, because Valgrind does not support it. Otherwise I need to run build with zig build -Dcpu=x86_64
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-gb",
        .root_source_file = b.path(src_folder ++ "main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    // TODO: This entire build process is bad, this requires that the user first installs csfml (libcsfml) on their system.
    // sfml
    const sfmlDep = b.dependency("sfml", .{}).module("sfml");
    exe.root_module.addImport("sfml", sfmlDep);

    sfmlDep.addIncludePath(b.path("csfml/include"));
    exe.addLibraryPath(b.path("csfml/lib/msvc"));
    sfml.link(exe);

    // zigglgen (opengl zig)
    const gl_bindings = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"4.1",
        .profile = .core,
        .extensions = &.{ .ARB_clip_control, .NV_scissor_exclusive },
    });
    exe.root_module.addImport("gl", gl_bindings);

    // run
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // tests
    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path(src_folder ++ "test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
