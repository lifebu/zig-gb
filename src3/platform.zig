const std = @import("std");
const assert = std.debug.assert;
const sokol = @import("sokol");

const def = @import("defines.zig");
const Imgui = @import("imgui.zig");
const shader = @import("shaders/gb.glsl.zig");
const shaderTypes = @import("shaders/shader_types.zig");

pub const State = struct {
    bind: sokol.gfx.Bindings = .{},
    pip: sokol.gfx.Pipeline = .{},
    pass_action: sokol.gfx.PassAction = .{},
    colorids: sokol.gfx.Image = .{},
    palette: sokol.gfx.Image = .{},
    sampler: sokol.gfx.Sampler = .{},

    imgui_state: Imgui.State = .{},

    input_state: def.InputState = .{},
};

pub fn init(state: *State, imgui_cb: *const fn ([]u8) void) void {
    Imgui.init(&state.imgui_state, imgui_cb);

    // gfx
    sokol.gfx.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });

    sokol.imgui.setup(.{
        .logger = .{ .func = sokol.log.func },
    });

    // textures
    state.colorids = sokol.gfx.makeImage(.{
        .width = def.overscan_width,
        .height = def.resolution_height,
        .pixel_format = .R8,
        .usage = .{ .stream_update = true },
    });
    state.sampler = sokol.gfx.makeSampler(.{
        .min_filter = .NEAREST,
        .mag_filter = .NEAREST,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
    });
    state.palette = sokol.gfx.makeImage(.{
        .width = def.color_depth,
        .height = 1,
        .pixel_format = .RGBA8,
        .data =   init: {
            var data: sokol.gfx.ImageData = .{};
            data.mip_levels[0] = sokol.gfx.asRange(&[_]u32{
                shaderTypes.shaderRgbaU32(224, 248, 208, 255),
                shaderTypes.shaderRgbaU32(136, 192, 112, 255),
                shaderTypes.shaderRgbaU32(52,  104,  86,  255),
                shaderTypes.shaderRgbaU32(8,  24,  32,  255),
            });
            break :init data;
        },
    });

    // bindind & pipeline
    const overscan_offset: f32 = @as(f32, @floatFromInt(def.tile_width)) / @as(f32, @floatFromInt(def.overscan_width));
    state.bind.vertex_buffers[0] = sokol.gfx.makeBuffer(.{
        .data = sokol.gfx.asRange(&[_]f32{
            // vec2 pos, vec2 uv
            0.0, 0.0, overscan_offset,  1.0, // bottom-left
            1.0, 0.0, 1.0,              1.0, // bottom-right
            0.0, 1.0, overscan_offset,  0.0, // top-left
            1.0, 1.0, 1.0,              0.0, // top-right
        })
    });
    state.bind.views[shader.VIEW_color_texture] = sokol.gfx.makeView(.{
        .texture = .{
            .image = state.colorids,
        }
    });
    state.bind.views[shader.VIEW_palette_texture] = sokol.gfx.makeView(.{
        .texture = .{
            .image = state.palette,
        }
    });
    state.bind.samplers[shader.SMP_texture_sampler] = state.sampler;

    state.pip = sokol.gfx.makePipeline(.{
        .shader = sokol.gfx.makeShader(shader.gbShaderDesc(sokol.gfx.queryBackend())),
        .layout = init: {
            var layout = sokol.gfx.VertexLayoutState{};
            layout.attrs[shader.ATTR_gb_pos_in].format = .FLOAT2;
            layout.attrs[shader.ATTR_gb_uv_in].format = .FLOAT2;
            break :init layout;
        },
        .primitive_type = .TRIANGLE_STRIP,
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };

    // audio
    sokol.audio.setup(.{
        .logger = .{ .func = sokol.log.func },
        .num_channels = def.samples_per_frame,
        .sample_rate = def.sample_rate,
    });
}

pub fn deinit() void {
    sokol.imgui.shutdown();
    sokol.gfx.shutdown();
    sokol.audio.shutdown();
}

pub fn frame(state: *State, colorids: [def.overscan_resolution]u8) void {
    // ui
    sokol.imgui.newFrame(.{
        .width = sokol.app.width(),
        .height = sokol.app.height(),
        .delta_time = sokol.app.frameDuration(),
        .dpi_scale = sokol.app.dpiScale(),
    });
    Imgui.render(&state.imgui_state);

    // graphics
    var window_title: [64]u8 = undefined;
    const delta_ms: f64 = sokol.app.frameDuration();
    const new_title = std.fmt.bufPrintZ(&window_title, "Zig GB Emulator. FPS: {d:.2}", .{1.0 / delta_ms}) catch unreachable;
    sokol.app.setWindowTitle(new_title);

    var img_data = sokol.gfx.ImageData{};
    img_data.mip_levels[0] = sokol.gfx.asRange(&colorids);
    sokol.gfx.updateImage(state.colorids, img_data);

    sokol.gfx.beginPass(.{ .action = state.pass_action, .swapchain = sokol.glue.swapchain() });
    sokol.gfx.applyPipeline(state.pip);
    sokol.gfx.applyBindings(state.bind);
    sokol.gfx.draw(0, 4, 1);

    sokol.imgui.render();
    sokol.gfx.endPass();
    sokol.gfx.commit();
}

pub fn pushSample(_: *State, sample: def.Sample) void {
    // TODO: use sokol.audio.expect() to know if we starved and if we will waste samples here.
    const sample_left: f32 = sample.left * def.default_platform_volume;
    const sample_right: f32 = sample.right * def.default_platform_volume;
    if(def.is_stereo) {
        const sample_arr: [2]f32 = .{ sample_left, sample_right };
        const samples_used: i32 = sokol.audio.push(&sample_arr[0], 1);
        if(samples_used == 0) {} // TODO: Samples wasted? Error?
    } else {
        const mono: f32 = (sample_left + sample_right) / 2.0;
        const sample_arr: [1]f32 = .{ mono };
        const samples_used: i32 = sokol.audio.push(&sample_arr[0], sample_arr.len);
        if(samples_used == 0) {} // TODO: Samples wasted? Error?
    }
}

pub export fn event(ev: ?*const sokol.app.Event, state_opaque: ?*anyopaque) void {
    const state: ?*State = @alignCast(@ptrCast(state_opaque));
    assert(state != null);
    if(ev) |e| {
        _ = sokol.imgui.handleEvent(e.*);
        switch(e.key_code) {
            // TODO: Rebindindable keys
            .LEFT => {
                state.?.input_state.left_pressed = e.type == .KEY_DOWN;
            },
            .RIGHT => {
                state.?.input_state.right_pressed = e.type == .KEY_DOWN;
            },
            .UP => {
                state.?.input_state.up_pressed = e.type == .KEY_DOWN;
            },
            .DOWN => {
                state.?.input_state.down_pressed = e.type == .KEY_DOWN;
            },
            .W => {
                state.?.input_state.start_pressed = e.type == .KEY_DOWN;
            },
            .A => {
                state.?.input_state.a_pressed = e.type == .KEY_DOWN;
            },
            .S => {
                state.?.input_state.select_pressed = e.type == .KEY_DOWN;
            },
            .D => {
                state.?.input_state.b_pressed = e.type == .KEY_DOWN;
            },
            .Q => {
                if(e.modifiers & sokol.app.modifier_ctrl != 0) {
                    sokol.app.requestQuit();
                }
            },
            .GRAVE_ACCENT => {
                state.?.imgui_state.imgui_visible = !state.?.imgui_state.imgui_visible;
            },
            else => {},
        }
    }
}

pub fn run(
    init_cb: ?*const fn () callconv(.c) void, 
    frame_cb: ?*const fn () callconv(.c) void,
    deinit_cb: ?*const fn () callconv(.c) void,
    state: *State) void {

    sokol.app.run(.{
        .init_cb = init_cb,
        .frame_cb = frame_cb,
        .cleanup_cb = deinit_cb,
        .event_userdata_cb = event,
        .user_data = state, 
        .width = def.window_width,
        .height = def.window_height,
        .icon = .{ .sokol_default = true },
        .window_title = "Zig GB Emulator",
        .logger = .{ .func = sokol.log.func },
    });
}
