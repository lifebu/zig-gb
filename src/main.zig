const std = @import("std");
// TODO: This is strange!
const _cpu = @import("cpu.zig");
// TODO: This is strange!
const _ppu = @import("ppu.zig");

const sf = struct {
    usingnamespace @import("sfml");
    usingnamespace sf.graphics;
};

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

    var cpu = try _cpu.CPU.init(alloc, "playground/Tetris.dump");
    //var cpu = try _cpu.CPU.init(alloc, "playground/test_roms/cpu_instrs/individual/09-op r,r.gb");
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

        try ppu.updatePixels(&cpu.memory, &pixels);
        try cpuTexture.updateFromPixels(pixels, null);
        try cpu.frame();

        window.clear(sf.Color.Black);
        gpuTexture.updateFromTexture(cpuTexture, null);
        window.draw(gpuSprite, null);
        window.display();
    }
}
