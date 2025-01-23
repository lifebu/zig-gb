const std = @import("std");
const sf = struct {
    usingnamespace @import("sfml");
};
const gl = @import("gl");

const RESOLUTION_WIDTH = 160;
const RESOLUTION_HEIGHT = 144;
const SCALING = 7;

const HARDWARE_COLORS = [4]sf.graphics.Color{ 
    sf.graphics.Color{ .r = 244, .g = 248, .b = 208, .a = 255 },  // white
    sf.graphics.Color{ .r = 136, .g = 192, .b = 112, .a = 255 },   // lgrey
    sf.graphics.Color{ .r = 52,  .g = 104, .b = 86, .a = 255 },    // dgray
    sf.graphics.Color{ .r = 8,   .g = 24,  .b = 32, .a = 255 },     // black
};

pub fn main() !void {
    var window_title: [64]u8 = undefined;

    const WINDOW_WIDTH = RESOLUTION_WIDTH * SCALING;
    const WINDOW_HEIGHT = RESOLUTION_HEIGHT * SCALING;
    var window = try sf.graphics.RenderWindow.create(.{ .x = WINDOW_WIDTH, .y = WINDOW_HEIGHT}, 32, "Zig GB Emulator.", 
        sf.window.Style.titlebar | sf.window.Style.resize | sf.window.Style.close, null);
    defer window.destroy();

    window.setFramerateLimit(60);

    // initialize openGL
    if(sf.c.sfRenderWindow_setActive(window._ptr, @intFromBool(true)) == @intFromBool(false)) unreachable;
    var glProc: gl.ProcTable = undefined;
    if(!glProc.init(sf.c.sfContext_getFunction)) unreachable;
    gl.makeProcTableCurrent(&glProc);
    defer gl.makeProcTableCurrent(null);

    var clock: sf.system.Clock = try sf.system.Clock.create();
    defer clock.destroy();

    var shader: sf.graphics.Shader = try sf.graphics.Shader.createFromFile(null, null, "shaders/frag.glsl");
    defer shader.destroy();

    const windowX: f32 = @floatFromInt(window.getSize().x);
    const windowY: f32 = @floatFromInt(window.getSize().y);
    shader.setUniform("u_Resolution", sf.system.Vector2f{ .x = windowX, .y = windowY });

    const colors = [_]sf.graphics.glsl.FVec4{
        HARDWARE_COLORS[0].toFVec4(),
        HARDWARE_COLORS[1].toFVec4(),
        HARDWARE_COLORS[2].toFVec4(),
        HARDWARE_COLORS[3].toFVec4(),
    };
    sf.c.sfShader_setVec4UniformArray(shader._ptr, "u_HwColors", @as(*const sf.c.sfGlslVec4, @ptrCast(&colors)), colors.len);


    // TODO: Get more proper error handling for this to find the issues.
    // https://www.khronos.org/opengl/wiki/OpenGL_Error
    // Define an error callback to get the messages!

    sf.c.sfShader_bind(shader._ptr);
    const shader_prog: c_uint = sf.c.sfShader_getNativeHandle(shader._ptr);
    if(shader_prog == 0) { std.debug.print("{d} is not a valid shader!\n", .{ shader_prog }); }

    const data_loc = gl.GetUniformLocation(shader_prog, "u_ColorIds");
    var data = [_]gl.int{ 
        // 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 16, 16, 17, 17, 18, 18, 19, 19, 
           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  255,  255, 
    } ** 144;
    data[0] = 0;
    const lenCast: gl.sizei = data.len;
    const dataCast: [*]const gl.int = &data;
    gl.Uniform1iv(data_loc, lenCast, dataCast);
    std.debug.print("SetUniform: GLError: {x}\n", .{gl.GetError() });

    var quad: sf.graphics.VertexArray = try sf.graphics.VertexArray.create();
    quad.setPrimitiveType(.triangle_strip);
    quad.append(sf.graphics.Vertex{ .position = sf.system.Vector2f{ .x = 0.0, .y = 0.0 }});
    quad.append(sf.graphics.Vertex{ .position = sf.system.Vector2f{ .x = windowX, .y = 0.0 }});
    quad.append(sf.graphics.Vertex{ .position = sf.system.Vector2f{ .x = 0.0, .y = windowY }});
    quad.append(sf.graphics.Vertex{ .position = sf.system.Vector2f{ .x = windowX, .y = windowY }});

    while(window.isOpen()) {
        while (window.pollEvent()) |event| {
            if (event == .closed) {
                window.close();
            } else if (sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.Q) and 
                       sf.window.keyboard.isKeyPressed(sf.window.keyboard.KeyCode.l_control)) {
                window.close();
            }
        }

        const deltaMS: f32 = @as(f32, @floatFromInt(clock.restart().asMicroseconds())) / 1_000.0;
        window.setTitle(try std.fmt.bufPrintZ(&window_title, "Zig GB Emulator. FPS: {d:.2}", .{1.0 / (deltaMS / 1_000)}));

        // Mixed gl and sfml operation!
        gl.ClearColor(1.0, 0.9, 0.5, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT);
        window.draw(quad, sf.graphics.RenderStates{ .shader = shader });
        window.display();
    }
}

