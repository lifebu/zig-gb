const std = @import("std");
const sf = struct {
    usingnamespace @import("sfml");
    usingnamespace sf.graphics;
};

const Conf = @import("conf.zig");
const Def = @import("def.zig");

const MemMap = @import("mem_map.zig");

const Self = @This();

const BACKGROUND = "data/background.png";
const SCALING = 4;
const TARGET_FPS = 60.0;

const NUM_SAMPLES = 512;
const NUM_CHANNELS = 2; //Stereo
const SAMPLE_RATE = 48_000;

alloc: std.mem.Allocator,
conf: Conf,

// Rendering
cpuTexture: sf.Texture = undefined,
currInputState: Def.InputState = .{},
gpuSprite: sf.Sprite = undefined,
gpuTexture: sf.Texture = undefined,
pixels: []sf.Color = undefined,
window: sf.RenderWindow = undefined,
windowFocused: bool = true,

// Timing
clock: sf.system.Clock = undefined,
deltaMS: f32 = 0,
targetDeltaMS: f32 = 0,
fps: f32 = 0,

// Audio
samples: []i16 = undefined,
sound: sf.audio.Sound = undefined,
soundBuffer: sf.audio.SoundBuffer = undefined,

pub fn init(alloc: std.mem.Allocator, conf: *const Conf) !Self {
    var self = Self{ .alloc = alloc, .conf = conf.*};

    const WINDOW_WIDTH = Def.RESOLUTION_WIDTH * SCALING;
    const WINDOW_HEIGHT = Def.RESOLUTION_HEIGHT * SCALING;

    self.window = try sf.RenderWindow.create(.{ .x = WINDOW_WIDTH, .y = WINDOW_HEIGHT}, 32, "Zig GB Emulator.", 
        sf.window.Style.titlebar | sf.window.Style.resize | sf.window.Style.close, null);
    errdefer self.window.destroy();

    // Position window in the middle of the screen.
    const resolution: sf.c.sfVideoMode = sf.c.sfVideoMode_getDesktopMode();
    // We want to have both windows side-by-side in bgb mode.
    const xOffset: u32 = if(conf.bgbMode) WINDOW_WIDTH else WINDOW_WIDTH / 2;
    self.window.setPosition(.{ .x = @intCast(resolution.width / 2 - xOffset), .y = @intCast(resolution.height / 2 - WINDOW_HEIGHT / 2) });
    self.window.setFramerateLimit(TARGET_FPS);

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
    @memset(self.pixels, sf.Color.Black);

    // timing
    self.clock = try sf.system.Clock.create();
    self.targetDeltaMS = (1.0 / TARGET_FPS) * 1_000.0;

    // audio
    self.samples = try alloc.alloc(i16, NUM_SAMPLES * NUM_CHANNELS);
    errdefer alloc.free(self.samples);
    @memset(self.samples, 0);

    self.soundBuffer = try sf.audio.SoundBuffer.createFromSamples(self.samples, NUM_CHANNELS, NUM_SAMPLES);
    errdefer self.soundBuffer.destroy();

    self.sound = try sf.audio.Sound.create();
    errdefer self.sound.destroy();

    self.sound.setVolume(0.0);

    return self;
}

pub fn deinit(self: *Self) void {
    self.window.destroy();
    self.cpuTexture.destroy();
    self.gpuTexture.destroy();
    self.gpuSprite.destroy();
    self.alloc.free(self.pixels);

    self.clock.destroy();

    self.alloc.free(self.samples);
    self.sound.destroy();
    self.soundBuffer.destroy();
}

pub fn update(self: *Self) !bool {
    if (!self.window.isOpen()) {
        return false;
    }

    while (self.window.pollEvent()) |event| {
        if (event == .closed) {
            self.window.close();
        }
        else if (event == .lost_focus and !self.conf.bgbMode) {
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
    self.deltaMS = @as(f32, @floatFromInt(self.clock.restart().asMicroseconds())) / 1_000.0;
    self.fps = 1.0 / (self.deltaMS / 1_000);
    const title = try std.fmt.allocPrintZ(self.alloc, "Zig GB Emulator. FPS: {d:.2}", .{self.fps});
    self.window.setTitle(title);
    self.alloc.free(title);

    if(Def.CLEAR_PIXELS_EACH_FRAME) {
        @memset(self.pixels, sf.Color.Black);
    }

    return true;
} 

// Input
pub fn getInputState(self: *Self) Def.InputState {
    return self.currInputState;
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

// graphics
pub fn getRawPixels(self: *Self) *[]Def.Color {
    return @ptrCast(&self.pixels);
} 

pub fn render(self: *Self) !void {
    try self.cpuTexture.updateFromPixels(self.pixels, null);
    self.window.clear(sf.Color.Black);
    self.gpuTexture.updateFromTexture(self.cpuTexture, null);
    self.window.draw(self.gpuSprite, null);
    self.window.display();
} 

// audio
pub fn getSamples(self: *Self) *[]i16 {
    return &self.samples;
} 

pub fn playAudio(self: *Self) !void {
    const newBuffer: sf.audio.SoundBuffer = try sf.audio.SoundBuffer.createFromSamples(self.samples, NUM_CHANNELS, NUM_SAMPLES);
    self.sound.setBuffer(newBuffer);
    self.sound.setLoop(true);
    self.sound.play();

    self.soundBuffer.destroy();
    // TODO: Is this actually a copy? Would that mean that newBuffer is actually destroyed?
    self.soundBuffer = newBuffer;
} 
