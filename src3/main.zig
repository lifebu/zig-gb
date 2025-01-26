const std = @import("std");
const sokol = @import("sokol");
const imgui = @import("cimgui");

const RESOLUTION_WIDTH = 160;
const RESOLUTION_HEIGHT = 144;
const SCALING = 5;

const NUM_SAMPLES = 32;

const state = struct {
    var bind: sokol.gfx.Bindings = .{};
    var pip: sokol.gfx.Pipeline = .{};
    var pass_action: sokol.gfx.PassAction = .{};
    var samples: [NUM_SAMPLES]f32 = [_]f32{ 0.0 } ** NUM_SAMPLES;
    var sample_pos: usize = 0;
    var even_odd: i32 = 0;
};

export fn init() void {
    // gfx
    sokol.gfx.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });

    sokol.imgui.setup(.{
        .logger = .{ .func = sokol.log.func },
    });

    // We only support opengl, which is forced by the build script.
    std.debug.assert(sokol.gfx.queryBackend() == .GLCORE);

    state.bind.vertex_buffers[0] = sokol.gfx.makeBuffer(.{
        .data = sokol.gfx.asRange(&[_]f32{
            // positions      colors
            -1.0, 1.0,  0.5, 1.0, 0.0, 0.0, 1.0, // top-left
            1.0,  1.0,  0.5, 0.0, 1.0, 0.0, 1.0, // top-right
            1.0,  -1.0, 0.5, 0.0, 0.0, 1.0, 1.0, // bottom-right
            -1.0, -1.0, 0.5, 1.0, 1.0, 0.0, 1.0, // bottom-left
        }),
    });
    state.bind.index_buffer = sokol.gfx.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sokol.gfx.asRange(&[_]u16{ 0, 1, 2, 0, 2, 3 }),
    });

    const attrib_position = 0;
    const attrib_color0 = 1;
    const vertex_source = 
        \\#version 410
        \\
        \\layout(location = 0) in vec4 position;
        \\layout(location = 0) out vec4 color;
        \\layout(location = 1) in vec4 color0;
        \\
        \\void main()
        \\{
        \\    gl_Position = position;
        \\    color = color0;
        \\}
    ;
    const fragment_source =
        \\#version 410
        \\
        \\layout(location = 0) out vec4 frag_color;
        \\layout(location = 0) in vec4 color;
        \\
        \\void main()
        \\{
        \\    frag_color = color;
        \\}
    ;

    var shader_desc: sokol.gfx.ShaderDesc = .{ 
        .label = "gb",
        .vertex_func = .{ .source = vertex_source, .entry = "main" },
        .fragment_func = .{ .source = fragment_source, .entry = "main" },
    };
    shader_desc.attrs[attrib_position].glsl_name = "position";
    shader_desc.attrs[attrib_color0].glsl_name = "color0";

    state.pip = sokol.gfx.makePipeline(.{
        .shader = sokol.gfx.makeShader(shader_desc),
        .layout = init: {
            var l = sokol.gfx.VertexLayoutState{};
            l.attrs[attrib_position].format = .FLOAT3;
            l.attrs[attrib_color0].format = .FLOAT4;
            break :init l;
        },
        .index_type = .UINT16,
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };

    // audio
    sokol.audio.setup(.{
        .logger = .{ .func = sokol.log.func },
        // .num_channels = 2,
        // .sample_rate = 48_000
    });
}

export fn frame() void {
    // audio
    for(0..@intCast(sokol.audio.expect())) |_| {
        if (state.sample_pos == NUM_SAMPLES) {
            state.sample_pos = 0;
            _ = sokol.audio.push(&state.samples[0], NUM_SAMPLES);
        }
        const amplitude = 0.001;
        state.samples[state.sample_pos] = if(0 != (state.even_odd & 0x20)) amplitude else -amplitude;
        state.sample_pos += 1;
        state.even_odd += 1;
    } 

    // ui
    sokol.imgui.newFrame(.{
        .width = sokol.app.width(),
        .height = sokol.app.height(),
        .delta_time = sokol.app.frameDuration(),
        .dpi_scale = sokol.app.dpiScale(),
    });

    // Imgui
    imgui.igSetNextWindowPos(.{ .x = 10, .y = 10 }, imgui.ImGuiCond_Once);
    imgui.igSetNextWindowSize(.{ .x = 400, .y = 100 }, imgui.ImGuiCond_Once);
    _ = imgui.igBegin("Hello Dear ImGui!", 0, imgui.ImGuiWindowFlags_None);
    _ = imgui.igColorEdit3("Background", &state.pass_action.colors[0].clear_value.r, imgui.ImGuiColorEditFlags_None);
    imgui.igEnd();
    // Imgui

    // graphics
    var window_title: [64]u8 = undefined;
    const delta_ms: f64 = sokol.app.frameDuration();
    const new_title = std.fmt.bufPrintZ(&window_title, "Zig GB Emulator. FPS: {d:.2}", .{1.0 / delta_ms}) catch unreachable;
    sokol.app.setWindowTitle(new_title);

    sokol.gfx.beginPass(.{ .swapchain = sokol.glue.swapchain() });
    sokol.gfx.applyPipeline(state.pip);
    sokol.gfx.applyBindings(state.bind);
    sokol.gfx.draw(0, 6, 1);
    sokol.imgui.render();
    sokol.gfx.endPass();
    sokol.gfx.commit();
}

export fn cleanup() void {
    sokol.imgui.shutdown();
    sokol.gfx.shutdown();
    sokol.audio.shutdown();
}

export fn event(ev: ?*const sokol.app.Event) void {
    if(ev) |e| {
        _ = sokol.imgui.handleEvent(e.*);
        if(e.type == .KEY_DOWN) {
            if(e.key_code == .ESCAPE) {
                sokol.app.requestQuit();
            }
        }
    }
}

pub fn main() void {
    sokol.app.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = RESOLUTION_WIDTH * SCALING,
        .height = RESOLUTION_HEIGHT * SCALING,
        .icon = .{ .sokol_default = true },
        .window_title = "Zig GB Emulator",
        .logger = .{ .func = sokol.log.func },
    });
}
