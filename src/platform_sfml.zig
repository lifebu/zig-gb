const std = @import("std");
const sf = struct {
    usingnamespace @import("sfml");
    usingnamespace sf.graphics;
};

const Def = @import("def.zig");

const MemMap = @import("mem_map.zig");

const Self = @This();

const BACKGROUND = "data/background.png";
const SCALING = 4;

alloc: std.mem.Allocator,
window: sf.RenderWindow = undefined,
windowFocused: bool = false,
cpuTexture: sf.Texture = undefined,
gpuTexture: sf.Texture = undefined,
gpuSprite: sf.Sprite = undefined,
pixels: []sf.Color = undefined,
currInputState: Def.InputState = .{},

pub fn init(alloc: std.mem.Allocator) !Self {
    var self = Self{ .alloc = alloc};

    const WINDOW_WIDTH = Def.RESOLUTION_WIDTH * SCALING;
    const WINDOW_HEIGHT = Def.RESOLUTION_HEIGHT * SCALING;

    self.window = try sf.RenderWindow.create(.{ .x = WINDOW_WIDTH, .y = WINDOW_HEIGHT}, 32, "Zig GB Emulator", 
        sf.window.Style.titlebar | sf.window.Style.resize | sf.window.Style.close, null);
    errdefer self.window.destroy();

    // Position window in the middle of the screen.
    const resolution: sf.c.sfVideoMode = sf.c.sfVideoMode_getDesktopMode();
    self.window.setPosition(.{ .x = @intCast(resolution.width / 2 - WINDOW_WIDTH / 2), .y = @intCast(resolution.height / 2 - WINDOW_HEIGHT / 2) });
    self.window.setFramerateLimit(60);

    // textures
    self.cpuTexture = try sf.Texture.createFromFile(BACKGROUND);
    errdefer self.cpuTexture.destroy();

    self.gpuTexture = try sf.Texture.createFromFile(BACKGROUND);
    errdefer self.gpuTexture.destroy();
    self.gpuTexture.setSmooth(false);

    self.gpuSprite = try sf.Sprite.createFromTexture(self.gpuTexture);
    errdefer self.gpuSprite.destroy();

    const windowX: f32 = @floatFromInt(self.window.getSize().x);
    const windowY: f32 = @floatFromInt(self.window.getSize().x);

    const localBounds: sf.FloatRect = self.gpuSprite.getLocalBounds();
    const xScale: f32 = windowX / localBounds.width;
    const yScale: f32 = windowY / localBounds.height;
    const minScale: f32 = @min(xScale, yScale);
    self.gpuSprite.setScale(.{ .x = minScale, .y = minScale });

    const globalBounds = self.gpuSprite.getGlobalBounds();
    const missingX: f32 = windowX - globalBounds.width;
    self.gpuSprite.setPosition(.{ .x = missingX / 2.0, .y = 0.0 });

    self.pixels = try alloc.alloc(sf.Color, WINDOW_WIDTH * WINDOW_HEIGHT);
    errdefer alloc.free(self.pixels);
    @memset(self.pixels, sf.Color.Magenta);

    return self;
}

pub fn deinit(self: *Self) void {
    self.window.destroy();
    self.cpuTexture.destroy();
    self.gpuTexture.destroy();
    self.gpuSprite.destroy();
    self.alloc.free(self.pixels);
}

pub fn update(self: *Self) bool {
    if (!self.window.isOpen()) {
        return false;
    }

    while (self.window.pollEvent()) |event| {
        if (event == .closed) {
            self.window.close();
        }
        else if (event == .lost_focus) {
            self.windowFocused = false;
        }
        else if (event == .gained_focus) {
            self.windowFocused = true;
        }
        else if (sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.Q) and 
                 sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.l_control)) {
            self.window.close();
        }
    }

    self.updateInputState();

    return true;
} 

pub fn getRawPixels(self: *Self) *[]Def.Color {
    return @ptrCast(&self.pixels);
} 

fn updateInputState(self: *Self) void {
    self.currInputState = 
        if(!self.windowFocused) Def.InputState{} 
        else Def.InputState {
            .isRightPressed = sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.right),
            .isLeftPressed = sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.left),
            .isUpPressed = sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.up),
            .isDownPressed = sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.down),
            .isAPressed = sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.A),
            .isBPressed = sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.D),
            .isSelectPressed = sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.S),
            .isStartPressed = sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.W),
        };
}

pub fn getInputState(self: *Self) Def.InputState {
    return self.currInputState;
} 

pub fn render(self: *Self) !void {
    try self.cpuTexture.updateFromPixels(self.pixels, null);
    self.window.clear(sf.Color.Black);
    self.gpuTexture.updateFromTexture(self.cpuTexture, null);
    self.window.draw(self.gpuSprite, null);
    self.window.display();
} 
