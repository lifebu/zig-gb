const std = @import("std");

const APU = @import("../apu.zig");
const Def = @import("../def.zig");
const MMU = @import("../mmu.zig");
const MMIO = @import("../mmio.zig");
const PPU = @import("../ppu.zig");

const TestType = struct {
    name: []u8,
    image: []u8,
    memory: []u8,
};

const BASE_TEST_DIR = "test_data/ppu_static/";
const TEST_FILE = BASE_TEST_DIR ++ "tests.json";

pub fn runStaticTest() !void {
    const alloc = std.testing.allocator;

    const testFile: []u8 = try std.fs.cwd().readFileAlloc(alloc, TEST_FILE, std.math.maxInt(u32));
    defer alloc.free(testFile);

    // TODO: Tests are empty for now.
    if(true) {
        return;
    }
    
    const json = try std.json.parseFromSlice([]TestType, alloc, testFile, .{ .ignore_unknown_fields = true });
    defer json.deinit();

    var mmio = MMIO{};

    // TODO: Need a way to fill the mmu with a test memory dump.
    var apu = APU{};
    var mmu = try MMU.init(alloc, &apu, &mmio, null);
    defer mmu.deinit();
    mmu.disableChecks = true;

    const testConfig: []TestType = json.value;
    for(testConfig) |testCase| {
        _ = testCase.memory;
        // TODO: Need a way to load a bmp file (sfml: sf::Image)
        _ = testCase.image;
        var pixels = try alloc.alloc(Def.Color, Def.RESOLUTION_WIDTH * Def.RESOLUTION_HEIGHT);
        defer alloc.free(pixels);
        @memset(pixels, Def.Color{ .r = 0, .g = 0, .b = 0, .a = 255 });

        var ppu = PPU{};

        // TODO: How to know when the PPU just reached the end of the frame? 
        ppu.step(&mmu, &pixels);
    }

    var testDir: std.fs.Dir = try std.fs.cwd().openDir("test_data/ppu_static/", .{ .iterate = true });
    defer testDir.close();
}
