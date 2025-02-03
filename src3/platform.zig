const std = @import("std");
const sokol = @import("sokol");
const imgui = @import("cimgui");

const def = @import("defines.zig");
const shader = @import("shaders/gb.glsl.zig");
const shaderTypes = @import("shaders/shader_types.zig");

pub const State = struct {
    bind: sokol.gfx.Bindings = .{},
    pip: sokol.gfx.Pipeline = .{},
    pass_action: sokol.gfx.PassAction = .{},
    ub_shader_init: shader.Init = undefined,
};

pub fn init(state: *State) void {
    // gfx
    sokol.gfx.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });

    sokol.imgui.setup(.{
        .logger = .{ .func = sokol.log.func },
    });

    state.bind.vertex_buffers[0] = sokol.gfx.makeBuffer(.{
        .data = sokol.gfx.asRange(&[_]f32{
            // positions
            -1.0, 1.0,  0.5, // top-left
            1.0,  1.0,  0.5, // top-right
            1.0,  -1.0, 0.5, // bottom-right
            -1.0, -1.0, 0.5, // bottom-left
        }),
    });
    state.bind.index_buffer = sokol.gfx.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sokol.gfx.asRange(&[_]u16{ 0, 1, 2, 0, 2, 3 }),
    });

    state.pip = sokol.gfx.makePipeline(.{
        .shader = sokol.gfx.makeShader(shader.gbShaderDesc(sokol.gfx.queryBackend())),
        .layout = init: {
            var l = sokol.gfx.VertexLayoutState{};
            l.attrs[shader.ATTR_gb_position].format = .FLOAT3;
            break :init l;
        },
        .index_type = .UINT16,
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };

    // shader
    state.ub_shader_init = .{
        .hw_colors = [4]shaderTypes.Vec4{
            shaderTypes.shaderRGBA(232, 232, 232, 255),
            shaderTypes.shaderRGBA(160, 160, 160, 255),
            shaderTypes.shaderRGBA(88,  88,  88,  255),
            shaderTypes.shaderRGBA(16,  16,  16,  255),
        },
        .resolution = shaderTypes.Vec2{ 
            .x = @floatFromInt(def.WINDOW_WIDTH), 
            .y = @floatFromInt(def.WINDOW_HEIGHT) 
        },
    };

    // audio
    sokol.audio.setup(.{
        .logger = .{ .func = sokol.log.func },
        .num_channels = def.NUM_CHANNELS,
        .sample_rate = def.SAMPLE_RATE,
    });
}

pub fn frame(state: *State, color2bpp: [def.NUM_2BPP]u8, _: [def.NUM_GB_SAMPLES]f32) void {
    // TODO: To avoid popping we might need to dynamically adjust the number of samples we write.
    //_ = sokol.audio.push(&samples[0], samples.len);

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
    sokol.gfx.applyUniforms(shader.UB_init, sokol.gfx.asRange(&state.ub_shader_init));
    sokol.gfx.applyUniforms(shader.UB_update, sokol.gfx.asRange(&.{ 
        .color_2bpp = shaderTypes.shader2BPPCompress(color2bpp), 
    }));

    sokol.gfx.draw(0, 6, 1);
    sokol.imgui.render();
    sokol.gfx.endPass();
    sokol.gfx.commit();
}

pub fn cleanup() void {
    sokol.imgui.shutdown();
    sokol.gfx.shutdown();
    sokol.audio.shutdown();
}

pub export fn event(ev: ?*const sokol.app.Event) void {
    if(ev) |e| {
        _ = sokol.imgui.handleEvent(e.*);
        if(e.type == .KEY_DOWN) {
            if(e.key_code == .ESCAPE) {
                sokol.app.requestQuit();
            }
        }
    }
}

pub fn run(
    init_cb: ?*const fn () callconv(.C) void, 
    frame_cb: ?*const fn () callconv(.C) void,
    cleanup_cb: ?*const fn () callconv(.C) void) void {
    sokol.app.run(.{
        .init_cb = init_cb,
        .frame_cb = frame_cb,
        .cleanup_cb = cleanup_cb,
        .event_cb = event,
        .width = def.WINDOW_WIDTH,
        .height = def.WINDOW_HEIGHT,
        .icon = .{ .sokol_default = true },
        .window_title = "Zig GB Emulator",
        .logger = .{ .func = sokol.log.func },
    });
}
