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
    ub_shader_init: shader.Init = undefined,
    imgui_state: Imgui.State = .{},

    use_neo: bool = false,
    bind_neo: sokol.gfx.Bindings = .{},
    pip_neo: sokol.gfx.Pipeline = .{},
    colorids_neo: sokol.gfx.Image = .{},
    palette_neo: sokol.gfx.Image = .{},
    sampler_neo: sokol.gfx.Sampler = .{},
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
            shaderTypes.shaderRgbaVec4(224, 248, 208, 255),
            shaderTypes.shaderRgbaVec4(136, 192, 112, 255),
            shaderTypes.shaderRgbaVec4(52,  104,  86,  255),
            shaderTypes.shaderRgbaVec4(8,  24,  32,  255),
        },
        .resolution = shaderTypes.Vec2{ 
            .x = @floatFromInt(def.window_width), 
            .y = @floatFromInt(def.window_height) 
        },
    };

    // audio
    sokol.audio.setup(.{
        .logger = .{ .func = sokol.log.func },
        .num_channels = def.num_channels,
        .sample_rate = def.sample_rate,
    });

    // gfx_neo
    state.use_neo = true;

    state.colorids_neo = sokol.gfx.makeImage(.{
        .width = def.overscan_width,
        .height = def.resolution_height,
        .pixel_format = .R8,
        .usage = .STREAM,
    });
    state.sampler_neo = sokol.gfx.makeSampler(.{
        .min_filter = .NEAREST,
        .mag_filter = .NEAREST,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
    });
    state.palette_neo = sokol.gfx.makeImage(.{
        .width = def.color_depth,
        .height = 1,
        .pixel_format = .RGBA8,
        .data =   init: {
            var data: sokol.gfx.ImageData = .{};
            data.subimage[0][0] = sokol.gfx.asRange(&[_]u32{
                shaderTypes.shaderRgbaU32(224, 248, 208, 255),
                shaderTypes.shaderRgbaU32(136, 192, 112, 255),
                shaderTypes.shaderRgbaU32(52,  104,  86,  255),
                shaderTypes.shaderRgbaU32(8,  24,  32,  255),
            });
            break :init data;
        },
    });

    const overscan_offset: f32 = @as(f32, @floatFromInt(def.tile_width)) / @as(f32, @floatFromInt(def.overscan_width));
    state.bind_neo.vertex_buffers[0] = sokol.gfx.makeBuffer(.{
        .data = sokol.gfx.asRange(&[_]f32{
            // vec2 pos, vec2 uv
            0.0, 0.0, overscan_offset,  1.0, // bottom-left
            1.0, 0.0, 1.0,              1.0, // bottom-right
            0.0, 1.0, overscan_offset,  0.0, // top-left
            1.0, 1.0, 1.0,              0.0, // top-right
        })
    });
    
    state.bind_neo.images[shader.IMG_color_texture] = state.colorids_neo;
    state.bind_neo.images[shader.IMG_palette_texture] = state.palette_neo;
    state.bind_neo.samplers[shader.SMP_texture_sampler] = state.sampler_neo;

    state.pip_neo = sokol.gfx.makePipeline(.{
        .shader = sokol.gfx.makeShader(shader.gbNeoShaderDesc(sokol.gfx.queryBackend())),
        .layout = init: {
            var layout = sokol.gfx.VertexLayoutState{};
            layout.attrs[shader.ATTR_gb_neo_pos_in].format = .FLOAT2;
            layout.attrs[shader.ATTR_gb_neo_uv_in].format = .FLOAT2;
            break :init layout;
        },
        .primitive_type = .TRIANGLE_STRIP,
    });
}

pub fn deinit() void {
    sokol.imgui.shutdown();
    sokol.gfx.shutdown();
    sokol.audio.shutdown();
}

fn createTestImage() [def.overscan_width * def.resolution_height]u8 {
    @setEvalBranchQuota(def.overscan_width * def.resolution_height * 2);
    var result: [def.overscan_width * def.resolution_height]u8 = undefined;
    for(0..def.overscan_width) |x| {
        for(0..def.resolution_height) |y| {
            result[x + def.overscan_width * y] = @intCast(y);
        }
    }
    return result;
}

fn convertImage(color2bpp: [def.num_2bpp]u8) [def.overscan_width * def.resolution_height]u8 {
    const num_tiles = def.resolution_tile_width * def.resolution_height;
    var result: [def.overscan_width * def.resolution_height]u8 = undefined;
    for(0..num_tiles) |i2bpp| {
        const first_bitplane_idx: usize = i2bpp * 2;
        var first_bitplane: u8 = color2bpp[first_bitplane_idx]; 
        var second_bitplane: u8 = color2bpp[first_bitplane_idx + 1]; 

        for(0..8) |iBit| {
            first_bitplane, const first_bit: u2 = @shlWithOverflow(first_bitplane, 1);
            second_bitplane, const second_bit: u2 = @shlWithOverflow(second_bitplane, 1);
            const color_id: u2 = first_bit + (second_bit << 1); // LSB first 
            const result_index: usize = i2bpp * 8 + iBit;
            const result_u8 = @as(u8, color_id) * (256 / 4);
            result[result_index] = result_u8;
        }
    }
    return result;
}

pub fn frame(state: *State, color2bpp: [def.num_2bpp]u8, _: [def.num_gb_samples]f32) void {
    // TODO: To avoid popping we might need to dynamically adjust the number of samples we write.
    //_ = sokol.audio.push(&samples[0], samples.len);

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

    sokol.gfx.beginPass(.{ .action = state.pass_action, .swapchain = sokol.glue.swapchain() });
    if(state.use_neo) {
        const test_image = convertImage(color2bpp);
        var img_data = sokol.gfx.ImageData{};
        img_data.subimage[0][0] = sokol.gfx.asRange(&test_image);
        sokol.gfx.updateImage(state.colorids_neo, img_data);

        sokol.gfx.applyPipeline(state.pip_neo);
        // TODO: Update the texture with the color2bpp data!
        sokol.gfx.applyBindings(state.bind_neo);
        sokol.gfx.draw(0, 4, 1);
    } else {
        sokol.gfx.applyPipeline(state.pip);
        sokol.gfx.applyBindings(state.bind);
        sokol.gfx.applyUniforms(shader.UB_init, sokol.gfx.asRange(&state.ub_shader_init));
        sokol.gfx.applyUniforms(shader.UB_update, sokol.gfx.asRange(&.{ 
            .color_2bpp = shaderTypes.shader2BPPCompress(color2bpp), 
        }));
        sokol.gfx.draw(0, 6, 1);
    }

    sokol.imgui.render();
    sokol.gfx.endPass();
    sokol.gfx.commit();
}

pub export fn event(ev: ?*const sokol.app.Event, state_opaque: ?*anyopaque) void {
    const state: ?*State = @alignCast(@ptrCast(state_opaque));
    if(ev) |e| {
        _ = sokol.imgui.handleEvent(e.*);
        if(e.type == .KEY_DOWN) {
            if(e.key_code == .Q and (e.modifiers & sokol.app.modifier_ctrl != 0)) {
                sokol.app.requestQuit();
            } else if (e.key_code == .GRAVE_ACCENT) {
                assert(state != null);
                state.?.imgui_state.imgui_visible = !state.?.imgui_state.imgui_visible;
            }
        }
    }
}

pub fn run(
    init_cb: ?*const fn () callconv(.C) void, 
    frame_cb: ?*const fn () callconv(.C) void,
    deinit_cb: ?*const fn () callconv(.C) void,
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
