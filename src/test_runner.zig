const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const panic = std.debug.panic;

pub const std_options: std.Options = .{ .logFn = log };
var log_err_count: usize = 0;
const use_threads: bool = true;

const GBModel = enum {
    all, dmg,
};

const CliArgs = struct {
    print_help: bool = false,
    is_server: bool = false,
    seed: u32 = 0,
    break_on_fail: bool = false,
    only_categories: [][]const u8 = undefined,
    exclude_tests: [][]const u8 = undefined,
    filter_tests: [][]const u8 = undefined,
    model: GBModel = .dmg,

    fn parse(alloc: std.mem.Allocator, args: std.process.Args) CliArgs {
        var result: CliArgs = .{};

        const arg_slice = args.toSlice(alloc) catch |err| panic("unable to parse command line args: {t}", .{err});
        for (arg_slice[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--help")) {
                std.debug.print("No one can help you here heheheh!\n", .{});
            } else if (std.mem.eql(u8, arg, "--listen=-")) {
                result.is_server = true;
            } else if (std.mem.startsWith(u8, arg, "--seed=")) {
                result.seed = std.fmt.parseUnsigned(u32, arg["--seed=".len..], 0) catch @panic("unable to parse --seed argument");
            } else if (std.mem.startsWith(u8, arg, "--break_on_fail")) {
                result.break_on_fail = true;
            } else if (std.mem.startsWith(u8, arg, "--only_categories=")) {
                // TODO: Implement (comma seperated list).
            } else if (std.mem.startsWith(u8, arg, "--exclude_tests=")) {
                // TODO: Implement (comma seperated list).
            } else if (std.mem.startsWith(u8, arg, "--filter_tests=")) {
                // TODO: Implement (comma seperated list).
            } else if (std.mem.startsWith(u8, arg, "--model=")) {
                const value: []const u8 = arg["--model=".len..];
                result.model = std.meta.stringToEnum(GBModel, value) orelse @panic("unable to parse --model argument");
            } else if (std.mem.startsWith(u8, arg, "--cache-dir")) {
                // Fuzzing not supported!
            } else {
                panic("unrecognized command line argument: {s}", .{arg});
            }
        }
        return result;
    }
};

pub fn main(init: std.process.Init) void {
    @disableInstrumentation();
    panicUnsupported();

    var threaded: std.Io.Threaded = .init(init.gpa, .{});
    defer threaded.deinit();
    const runner_io = if (use_threads) threaded.io() else std.Io.Threaded.global_single_threaded.io();

    const args: CliArgs = .parse(init.gpa, init.minimal.args);
    std.testing.random_seed = args.seed;

    if (args.is_server) {
        return mainServer(runner_io, init) catch |err| panic("internal test runner failure: {t}", .{err});
    } else {
        return mainTerminal(runner_io, init);
    }
}

pub fn log(comptime message_level: std.log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype) void {
    @disableInstrumentation();
    if (@intFromEnum(message_level) <= @intFromEnum(std.log.Level.err)) {
        log_err_count +|= 1;
    }
    if (@intFromEnum(message_level) <= @intFromEnum(std.testing.log_level)) {
        std.debug.print(std.fmt.comptimePrint("[{t}] ({t}): {s}\n", .{ scope, message_level, format }), args);
    }
}

fn panicUnsupported() void {
    if(builtin.fuzz) {
        @panic("Fuzzing is not supported");
    // 'simple' test runner is used for work-in-progress backends that we don't need to support.
    } else if (builtin.zig_backend == .stage2_aarch64 or builtin.zig_backend == .stage2_powerpc or builtin.zig_backend == .stage2_riscv64) {
        @panic(std.fmt.comptimePrint("The backend requires a 'simple' test runner that we don't support: {t}", .{ builtin.zig_backend }));
    } else if (builtin.cpu.arch.isSpirV()) {
        @panic("No test-runner for SPIR-V");
    }
}

fn runSingleTest(root_node: std.Progress.Node, test_fn: std.builtin.TestFn) anyerror!void {
    // TODO: Missing Leak detection per test! Implement a "Leak" error for a single test?
    const test_node = root_node.start(test_fn.name, 0);
    defer test_node.end();
    return test_fn.func();
}

fn mainTerminal(runner_io: std.Io, init: std.process.Init) void {
    @disableInstrumentation();

    var start: std.Io.Timestamp = .now(init.io, .awake);
    const alloc = init.gpa;

    std.testing.log_level = .warn;
    std.testing.environ = init.minimal.environ;
    std.testing.allocator_instance = .{};
    defer _ = std.testing.allocator_instance.deinit();

    std.testing.io_instance = .init(std.testing.allocator, .{
        .argv0 = .init(init.minimal.args),
        .environ = init.minimal.environ,
    });
    defer std.testing.io_instance.deinit();

    var ok_count: usize = 0;
    var skip_count: usize = 0;
    var fail_count: usize = 0;
    const root_node: std.Progress.Node = std.Progress.start(runner_io, .{
        .root_name = "Test",
        .estimated_total_items = builtin.test_functions.len,
    });

    // TODO: Select should be better for this? 
    const futures = alloc.alloc(std.Io.Future(anyerror!void), builtin.test_functions.len) catch unreachable;
    defer alloc.free(futures);

    const leaks: usize = 0;
    for (builtin.test_functions, 0..) |test_fn, i| {
        const future = runner_io.async(runSingleTest, .{ root_node, test_fn });
        futures[i] = future;
    }
    defer for(futures) |*future| if (future.cancel(runner_io)) |_| {} else |_| {};

    for(futures, builtin.test_functions, 0..) |*future, test_fn, i| {
        if (future.await(runner_io)) |_| {
            ok_count += 1;
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip_count += 1;
                std.debug.print("{d}/{d} {s}...SKIP\n", .{ i + 1, builtin.test_functions.len, test_fn.name });
            },
            else => {
                fail_count += 1;
                std.debug.print("{d}/{d} {s}...FAIL ({t})\n", .{ i + 1, builtin.test_functions.len, test_fn.name, err });
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpErrorReturnTrace(trace);
                }
            },
        }
    }
    root_node.end();

    var exit_code: u8 = 0;
    if (ok_count == builtin.test_functions.len) {
        std.debug.print("All {d} tests passed.\n", .{ok_count});
    } else {
        std.debug.print("{d} passed; {d} skipped; {d} failed.\n", .{ ok_count, skip_count, fail_count });
    }
    if (log_err_count != 0) {
        std.debug.print("{d} errors were logged.\n", .{log_err_count});
    }
    if (leaks != 0) {
        std.debug.print("{d} tests leaked memory.\n", .{leaks});
    }
    if (leaks != 0 or log_err_count != 0 or fail_count != 0) {
        exit_code = 1;
    }

    const elapsed: std.Io.Duration = start.untilNow(init.io, .awake);
    std.debug.print("Tests: Total time: {f}\n", .{ elapsed });
    std.process.exit(exit_code);
}

// Basically copy-paste from zigs default test_runner. 
// Server mode is not really something I support actively. Only a fallback solution.
fn mainServer(runner_io: std.Io, init: std.process.Init) !void {
    @disableInstrumentation();

    var stdin_buffer: [4096]u8 = undefined;
    var stdout_buffer: [4096]u8 = undefined;
    var stdin_reader: std.Io.File.Reader = .initStreaming(.stdin(), runner_io, &stdin_buffer);
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), runner_io, &stdout_buffer);
    var server = try std.zig.Server.init(.{
        .in = &stdin_reader.interface,
        .out = &stdout_writer.interface,
        .zig_version = builtin.zig_version_string,
    });

    while (true) {
        const header = try server.receiveMessage();
        switch (header.tag) {
            .exit => {
                return std.process.exit(0);
            },
            .query_test_metadata => {
                std.testing.allocator_instance = .{};
                defer if (std.testing.allocator_instance.deinit() == .leak) {
                    @panic("internal test runner memory leak");
                };

                var string_bytes: std.ArrayList(u8) = .empty;
                defer string_bytes.deinit(std.testing.allocator);
                try string_bytes.append(std.testing.allocator, 0); // Reserve 0 for null.

                const test_fns = builtin.test_functions;
                const names = try std.testing.allocator.alloc(u32, test_fns.len);
                defer std.testing.allocator.free(names);
                const expected_panic_msgs = try std.testing.allocator.alloc(u32, test_fns.len);
                defer std.testing.allocator.free(expected_panic_msgs);

                for (test_fns, names, expected_panic_msgs) |test_fn, *name, *expected_panic_msg| {
                    name.* = @intCast(string_bytes.items.len);
                    try string_bytes.ensureUnusedCapacity(std.testing.allocator, test_fn.name.len + 1);
                    string_bytes.appendSliceAssumeCapacity(test_fn.name);
                    string_bytes.appendAssumeCapacity(0);
                    expected_panic_msg.* = 0;
                }

                try server.serveTestMetadata(.{
                    .names = names,
                    .expected_panic_msgs = expected_panic_msgs,
                    .string_bytes = string_bytes.items,
                });
            },

            .run_test => {
                std.testing.environ = init.minimal.environ;
                std.testing.allocator_instance = .{};
                std.testing.io_instance = .init(std.testing.allocator, .{
                    .argv0 = .init(init.minimal.args),
                    .environ = init.minimal.environ,
                });
                log_err_count = 0;
                const index = try server.receiveBody_u32();
                const test_fn = builtin.test_functions[index];

                // let the build server know we're starting the test now
                try server.serveStringMessage(.test_started, &.{});

                const TestResults = std.zig.Server.Message.TestResults;
                const status: TestResults.Status = if (test_fn.func()) |v| s: {
                    v;
                    break :s .pass;
                } else |err| switch (err) {
                    error.SkipZigTest => .skip,
                    else => s: {
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpErrorReturnTrace(trace);
                        }
                        break :s .fail;
                    },
                };
                std.testing.io_instance.deinit();
                const leak_count = std.testing.allocator_instance.detectLeaks();
                std.testing.allocator_instance.deinitWithoutLeakChecks();
                try server.serveTestResults(.{
                    .index = index,
                    .flags = .{
                        .status = status,
                        .fuzz = false,
                        .log_err_count = std.math.lossyCast(
                            @FieldType(TestResults.Flags, "log_err_count"),
                            log_err_count,
                        ),
                        .leak_count = std.math.lossyCast(
                            @FieldType(TestResults.Flags, "leak_count"),
                            leak_count,
                        ),
                    },
                });
            },
            .start_fuzzing => {
                @panic("Fuzzing is not supported");
            },
            else => {
                std.debug.print("unsupported message: {x}\n", .{@intFromEnum(header.tag)});
                std.process.exit(1);
            },
        }
    }
}
