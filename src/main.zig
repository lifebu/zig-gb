const std = @import("std");
// TODO: This is strange!
const _cpu = @import("cpu.zig");
// TODO: This is strange!
const _ppu = @import("ppu.zig");
const blargg = @import("blargg_parser.zig");

const sf = struct {
    usingnamespace @import("sfml");
    usingnamespace sf.graphics;
};

const InputState = struct{
    dpad: u4 = 0xF, // 1 means not pressd for gameboy.
    buttons: u4 = 0xF,
};

fn getInputStateBytes() InputState {
    var input = InputState{};

    input.dpad &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.right))) << 0); // Right
    input.dpad &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.left))) << 1); // Left
    input.dpad &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.up))) << 2); // Up
    input.dpad &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.down))) << 3); // Down
    
    input.buttons &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.A))) << 0); // A
    input.buttons &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.D))) << 1); // B
    input.buttons &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.S))) << 2); // Select
    input.buttons &= ~(@as(u4, @intFromBool(sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.W))) << 3); // Start

    return input;
}

pub fn main() !void {
    const WINDOW_WIDTH = 160 * 4;
    const WINDOW_HEIGHT = 144 * 4;

    var window = try sf.RenderWindow.create(.{ .x = WINDOW_WIDTH, .y = WINDOW_HEIGHT}, 32, "Zig GB Emulator", 
        sf.window.Style.titlebar | sf.window.Style.resize | sf.window.Style.close, null);
    defer window.destroy();

    // Position window in the middle of the screen.
    const resolution: sf.c.sfVideoMode = sf.c.sfVideoMode_getDesktopMode();
    window.setPosition(.{ .x = @intCast(resolution.width / 2 - WINDOW_WIDTH / 2), .y = @intCast(resolution.height / 2 - WINDOW_HEIGHT / 2) });
    window.setFramerateLimit(60);

    // textures
    const BACKGROUND = "data/background.png";
    var cpuTexture: sf.Texture = try sf.Texture.createFromFile(BACKGROUND);
    defer cpuTexture.destroy();

    var gpuTexture: sf.Texture = try sf.Texture.createFromFile(BACKGROUND);
    defer gpuTexture.destroy();
    gpuTexture.setSmooth(false);

    var gpuSprite: sf.Sprite = try sf.Sprite.createFromTexture(gpuTexture);
    defer gpuSprite.destroy();

    const windowX: f32 = @floatFromInt(window.getSize().x);
    const windowY: f32 = @floatFromInt(window.getSize().x);

    const localBounds: sf.FloatRect = gpuSprite.getLocalBounds();
    const xScale: f32 = windowX / localBounds.width;
    const yScale: f32 = windowY / localBounds.height;
    const minScale: f32 = @min(xScale, yScale);
    gpuSprite.setScale(.{ .x = minScale, .y = minScale });

    const globalBounds = gpuSprite.getGlobalBounds();
    const missingX: f32 = windowX - globalBounds.width;
    gpuSprite.setPosition(.{ .x = missingX / 2.0, .y = 0.0 });

    // emulator
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = allocator.allocator();
    defer _ = allocator.deinit();

    var cpu = try _cpu.CPU.init(alloc, "test_data/blargg_roms/cpu_instrs/individual/11-op a,(hl).gb");
    defer cpu.deinit();

    var ppu = _ppu.PPU{};

    var pixels = try alloc.alloc(sf.Color, WINDOW_WIDTH * WINDOW_HEIGHT);
    defer alloc.free(pixels);

    @memset(pixels, sf.Color.Magenta);

    while (window.isOpen()) {
        while (window.pollEvent()) |event| {
            if (event == .closed) {
                window.close();
            }
            else if (sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.Q) and 
                     sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.l_control)) {
                window.close();
            }
        }

        // updating input bytes
        const inputState: InputState = getInputStateBytes();
        const joyp: *u8 = &cpu.memory[0xFF00];

        // TODO: This could probably be implemented better!
        const selectDpad: bool = (joyp.* & 0x10) != 0x10;
        const selectButtons: bool = (joyp.* & 0x20) != 0x20;
        if(selectDpad and selectButtons)  { joyp.* = (joyp.* & 0xF0) | (inputState.dpad & inputState.buttons); }
        else if(selectDpad) { joyp.* = (joyp.* & 0xF0) & inputState.dpad; }
        else if(selectButtons) { joyp.* = (joyp.* & 0xF0) & inputState.buttons; }
        else { joyp.* = (joyp.* & 0xF0) & 0x0F; }

        try ppu.updatePixels(&cpu.memory, &pixels);
        try cpuTexture.updateFromPixels(pixels, null);
        try cpu.frame();

        window.clear(sf.Color.Black);
        gpuTexture.updateFromTexture(cpuTexture, null);
        window.draw(gpuSprite, null);
        window.display();
    }
}

// TODO: Move testcode to another zig file.
const CPUState = struct {
    pc: u16 = 0,
    sp: u16 = 0,
    a: u8 = 0,
    b: u8 = 0,
    c: u8 = 0,
    d: u8 = 0,
    e: u8 = 0,
    f: u8 = 0,
    h: u8 = 0,
    l: u8 = 0,
    ime: u1 = 0,
    ie: u1 = 0,
    ram: [][]u16,
};

const TestType = struct {
    name: []u8,
    initial: CPUState,
    final: CPUState,
    // ignoring cycles field in json.
};

fn testOutput(cpu: *const _cpu.CPU, testCase: *const TestType) !void {
    try std.testing.expectEqual(cpu.pc, testCase.final.pc);
    try std.testing.expectEqual(cpu.sp, testCase.final.sp);
    try std.testing.expectEqual(cpu.registers.r8.A, testCase.final.a);
    try std.testing.expectEqual(cpu.registers.r8.F.F, testCase.final.f);
    try std.testing.expectEqual(cpu.registers.r8.B, testCase.final.b);
    try std.testing.expectEqual(cpu.registers.r8.C, testCase.final.c);
    try std.testing.expectEqual(cpu.registers.r8.D, testCase.final.d);
    try std.testing.expectEqual(cpu.registers.r8.E, testCase.final.e);
    try std.testing.expectEqual(cpu.registers.r8.H, testCase.final.h);
    try std.testing.expectEqual(cpu.registers.r8.L, testCase.final.l);
    for (testCase.final.ram) |ramPair| {
        std.debug.assert(ramPair.len == 2);
        const address: u16 = ramPair[0];
        const value: u8 = @intCast(ramPair[1]);
        try std.testing.expectEqual(cpu.memory[address], value);
    }
}

fn printTestCase(cpuState: *const CPUState) void {
    std.debug.print("A: {X:0>2} F: {s} {s} {s} {s} ", .{ cpuState.a, 
        if ((cpuState.f & 0x80) == 0x80) "Z" else "_",
        if ((cpuState.f & 0x40) == 0x40) "N" else "_",
        if ((cpuState.f & 0x20) == 0x20) "H" else "_",
        if ((cpuState.f & 0x10) == 0x10) "C" else "_",
    });
    std.debug.print("B: {X:0>2} C: {X:0>2} ", .{ cpuState.b, cpuState.c });
    std.debug.print("D: {X:0>2} E: {X:0>2} ", .{ cpuState.d, cpuState.e });
    std.debug.print("H: {X:0>2} L: {X:0>2} ", .{ cpuState.h, cpuState.l });
    std.debug.print("SP: {X:0>4} PC: {X:0>4}\n", .{ cpuState.sp, cpuState.pc });
    for (cpuState.ram) |ramPair| {
        std.debug.assert(ramPair.len == 2);
        const address: u16 = ramPair[0];
        const value: u8 = @intCast(ramPair[1]);
        std.debug.print("Addr: {X:0>4} val: {X:0>2} ", .{ address, value });

    }
    std.debug.print("\n", .{});
}

test "SingleStepTests" {
    const alloc = std.testing.allocator;

    var testDir: std.fs.Dir = try std.fs.cwd().openDir("test_data/SingleStepTests/v1/", .{ .iterate = true });
    defer testDir.close();

    var iter: std.fs.Dir.Iterator = testDir.iterate();
    var idx: u32 = 1;
    while(try iter.next()) |dirEntry| {
        std.debug.assert(dirEntry.kind == .file);
        std.debug.print("{d}: Testing: {s}\n", .{idx, dirEntry.name});
        idx += 1;

        const testFile: []u8 = try testDir.readFileAlloc(alloc, dirEntry.name, 1 * 1024 * 1024);
        defer alloc.free(testFile);

        const json = try std.json.parseFromSlice([]TestType, alloc, testFile, .{ .ignore_unknown_fields = true });
        defer json.deinit();

        var cpu = try _cpu.CPU.init(alloc, null);
        defer cpu.deinit();

        const testConfig: []TestType = json.value;
        for(testConfig) |testCase| {

            cpu.pc = testCase.initial.pc;
            cpu.sp = testCase.initial.sp;
            cpu.registers.r8.A = testCase.initial.a;
            cpu.registers.r8.F.F = testCase.initial.f;
            cpu.registers.r8.B = testCase.initial.b;
            cpu.registers.r8.C = testCase.initial.c;
            cpu.registers.r8.D = testCase.initial.d;
            cpu.registers.r8.E = testCase.initial.e;
            cpu.registers.r8.H = testCase.initial.h;
            cpu.registers.r8.L = testCase.initial.l;
            for (testCase.initial.ram) |ramPair| {
                std.debug.assert(ramPair.len == 2);
                const address: u16 = ramPair[0];
                const value: u8 = @intCast(ramPair[1]);
                cpu.memory[address] = value;
            }

            try cpu.step();

            testOutput(&cpu, &testCase) catch |err| {
                std.debug.print("Test Failed: {s}\n", .{ testCase.name});
                std.debug.print("Initial\n", .{});
                printTestCase(&testCase.initial);
                std.debug.print("Expected\n", .{});
                printTestCase(&testCase.final);
                std.debug.print("\n", .{});

                std.debug.print("Got\n", .{});
                std.debug.print("A: {X:0>2} F: {s} {s} {s} {s} ", .{ cpu.registers.r8.A, 
                    if (cpu.registers.r8.F.Flags.zero) "Z" else "_",
                    if (cpu.registers.r8.F.Flags.nBCD) "N" else "_",
                    if (cpu.registers.r8.F.Flags.halfBCD) "H" else "_",
                    if (cpu.registers.r8.F.Flags.carry) "C" else "_",
                });
                std.debug.print("B: {X:0>2} C: {X:0>2} ", .{ cpu.registers.r8.B, cpu.registers.r8.C });
                std.debug.print("D: {X:0>2} E: {X:0>2} ", .{ cpu.registers.r8.D, cpu.registers.r8.E });
                std.debug.print("H: {X:0>2} L: {X:0>2} ", .{ cpu.registers.r8.H, cpu.registers.r8.L });
                std.debug.print("SP: {X:0>4} PC: {X:0>4}\n", .{ cpu.sp, cpu.pc });
                for (testCase.final.ram) |ramPair| {
                    std.debug.assert(ramPair.len == 2);
                    const address: u16 = ramPair[0];
                    const value: u8 = cpu.memory[address];
                    std.debug.print("Addr: {X:0>4} val: {X:0>2} ", .{ address, value });

                }
                std.debug.print("\n", .{});

                return err;
            };
        }
    }
}

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
