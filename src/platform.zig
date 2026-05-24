const std = @import("std");
const build_options = @import("build_options");
const assert = std.debug.assert;
const sokol = @import("sokol");

const def = @import("defines.zig");
const Config = @import("config.zig");
const Fifo = @import("util/fifo.zig");
const Imgui = @import("imgui.zig");
const shader = @import("shaders/gb.glsl.zig");
const shaderTypes = @import("shaders/shader_types.zig");

const Self = @This();

const fps_buffer_size = 30;

// ui
imgui: Imgui = .{},

// time
core_delta_buffer: Fifo.RingbufferFifo(f64, fps_buffer_size) = .{},
platform_delta_buffer: Fifo.RingbufferFifo(f64, fps_buffer_size) = .{},
user_delta_buffer: Fifo.RingbufferFifo(f64, fps_buffer_size) = .{},

// gfx
bind: sokol.gfx.Bindings = .{},
pip: sokol.gfx.Pipeline = .{},
pass_action: sokol.gfx.PassAction = .{},
colorids: sokol.gfx.Image = .{},
palette: sokol.gfx.Image = .{},
sampler: sokol.gfx.Sampler = .{},

// audio
volume: f32 = 0.15,
is_stereo: bool = true,

// input
input_state: def.InputState = .{},
keybinds: def.Keybinds = .{},


pub fn init(self: *Self, io: std.Io, config: Config, imgui_cb: *const fn ([]u8) void) void {
    // ui
    self.imgui.init(io, config, imgui_cb);

    // time
    sokol.time.setup();

    // gfx
    const gfx_config = config.graphics;
    sokol.gfx.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });

    sokol.imgui.setup(.{
        .logger = .{ .func = sokol.log.func },
    });

    // textures
    self.colorids = sokol.gfx.makeImage(.{
        .width = def.overscan_width,
        .height = def.resolution_height,
        .pixel_format = .R8,
        .usage = .{ .stream_update = true },
    });
    self.sampler = sokol.gfx.makeSampler(.{
        .min_filter = .NEAREST,
        .mag_filter = .NEAREST,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
    });
    self.palette = sokol.gfx.makeImage(.{
        .width = def.color_depth,
        .height = 1,
        .pixel_format = .RGBA8,
        .data =   init: {
            var data: sokol.gfx.ImageData = .{};
            data.mip_levels[0] = sokol.gfx.asRange(&[_]u32{
                shaderTypes.shaderRgbaU32(gfx_config.palette.color_0[0], gfx_config.palette.color_0[1], gfx_config.palette.color_0[2], 255),
                shaderTypes.shaderRgbaU32(gfx_config.palette.color_1[0], gfx_config.palette.color_1[1], gfx_config.palette.color_1[2], 255),
                shaderTypes.shaderRgbaU32(gfx_config.palette.color_2[0], gfx_config.palette.color_2[1], gfx_config.palette.color_2[2], 255),
                shaderTypes.shaderRgbaU32(gfx_config.palette.color_3[0], gfx_config.palette.color_3[1], gfx_config.palette.color_3[2], 255),
            });
            break :init data;
        },
    });

    // bindind & pipeline
    const overscan_offset: f32 = @as(f32, @floatFromInt(def.tile_width)) / @as(f32, @floatFromInt(def.overscan_width));
    self.bind.vertex_buffers[0] = sokol.gfx.makeBuffer(.{
        .data = sokol.gfx.asRange(&[_]f32{
            // vec2 pos, vec2 uv
            0.0, 0.0, overscan_offset,  1.0, // bottom-left
            1.0, 0.0, 1.0,              1.0, // bottom-right
            0.0, 1.0, overscan_offset,  0.0, // top-left
            1.0, 1.0, 1.0,              0.0, // top-right
        })
    });
    self.bind.views[shader.VIEW_color_texture] = sokol.gfx.makeView(.{
        .texture = .{
            .image = self.colorids,
        }
    });
    self.bind.views[shader.VIEW_palette_texture] = sokol.gfx.makeView(.{
        .texture = .{
            .image = self.palette,
        }
    });
    self.bind.samplers[shader.SMP_texture_sampler] = self.sampler;

    self.pip = sokol.gfx.makePipeline(.{
        .shader = sokol.gfx.makeShader(shader.gbShaderDesc(sokol.gfx.queryBackend())),
        .layout = init: {
            var layout = sokol.gfx.VertexLayoutState{};
            layout.attrs[shader.ATTR_gb_pos_in].format = .FLOAT2;
            layout.attrs[shader.ATTR_gb_uv_in].format = .FLOAT2;
            break :init layout;
        },
        .primitive_type = .TRIANGLE_STRIP,
    });

    self.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };

    // audio
    self.volume = if (build_options.enable_audio) config.audio.volume else 0.0;
    self.is_stereo = config.audio.stereo_audio;
    sokol.audio.setup(.{
        .logger = .{ .func = sokol.log.func },
        .num_channels = if(self.is_stereo) 2 else 1,
        .sample_rate = def.sample_rate,
    });

    // input
    self.keybinds = config.keybinds;
}

pub fn deinit(self: *Self, io: std.Io, alloc: std.mem.Allocator, config: *Config) void {
    self.imgui.deinit(io, alloc, config);

    sokol.imgui.shutdown();
    sokol.gfx.shutdown();
    sokol.audio.shutdown();
}

pub fn frame(self: *Self, io: std.Io, alloc: std.mem.Allocator, colorids: [def.overscan_resolution]u8, samples_opt: ?*def.SampleFifo, core_delta_sample: ?u64, platform_delta_sample: ?u64) void {
    // ui
    sokol.imgui.newFrame(.{
        .width = sokol.app.width(),
        .height = sokol.app.height(),
        .delta_time = sokol.app.frameDuration(),
        .dpi_scale = sokol.app.dpiScale(),
    });
    self.imgui.render(io, alloc);

    // time
    const platform_delta: f64 = if(platform_delta_sample) |value| sokol.time.sec(value) else 0.0166666;
    self.platform_delta_buffer.writeItemOverrideWhenFull(platform_delta);
    const smooth_platform_delta: f64 = self.platform_delta_buffer.average();

    const core_delta: f64 = if(core_delta_sample) |value| sokol.time.sec(value) else 0.0166666;
    self.core_delta_buffer.writeItemOverrideWhenFull(core_delta);
    const smooth_core_delta: f64 = self.core_delta_buffer.average();

    const user_delta: f64 = sokol.app.frameDuration();
    self.user_delta_buffer.writeItemOverrideWhenFull(user_delta);
    const smooth_user_delta: f64 = self.user_delta_buffer.average();

    // graphics
    var window_title: [128]u8 = undefined;
    const new_title = std.fmt.bufPrintZ(&window_title, "Zig GB Emulator. (u/c): {d:0>6.2}/{d:0>6.2} FPS. (u/c/p): {d:0>6.2}/{d:0>6.2}/{d:0>6.2} ms", .{
        1.0 / smooth_user_delta, 1.0 / smooth_core_delta,
        smooth_user_delta * 1000.0, smooth_core_delta * 1000.0, smooth_platform_delta * 1000.0,
    }) catch unreachable;
    sokol.app.setWindowTitle(new_title);

    var img_data = sokol.gfx.ImageData{};
    img_data.mip_levels[0] = sokol.gfx.asRange(&colorids);
    sokol.gfx.updateImage(self.colorids, img_data);

    sokol.gfx.beginPass(.{ .action = self.pass_action, .swapchain = sokol.glue.swapchain() });
    sokol.gfx.applyPipeline(self.pip);
    sokol.gfx.applyBindings(self.bind);
    sokol.gfx.draw(0, 4, 1);

    sokol.imgui.render();
    sokol.gfx.endPass();
    sokol.gfx.commit();

    // audio
    if(samples_opt) |samples| while(samples.readItem()) |sample| {
        self.pushSample(sample);
    };
}

pub fn pushSample(self: *Self, sample: def.Sample) void {
    // TODO: use sokol.audio.expect() to know if we starved and if we will waste samples here.
    const sample_left: f32 = sample.left * self.volume;
    const sample_right: f32 = sample.right * self.volume;
    if(self.is_stereo) {
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

pub export fn event(ev_opt: ?*const sokol.app.Event, self_opaque: ?*anyopaque) void {
    const self_opt: ?*Self = @alignCast(@ptrCast(self_opaque));
    const self: *Self = self_opt orelse return;
    const ev: *const sokol.app.Event = ev_opt orelse return;
    _ = sokol.imgui.handleEvent(ev.*);

    const escape: bool = (ev.key_code == .ESCAPE or ev.key_code == .CAPS_LOCK) and ev.type == .KEY_DOWN;
    const mouse_right: bool = ev.mouse_button == .RIGHT and ev.type == .MOUSE_DOWN;

    if(ev.key_code == self.keybinds.key_up) {
        self.input_state.up_pressed = ev.type == .KEY_DOWN;
    }
    else if(ev.key_code == self.keybinds.key_down) {
        self.input_state.down_pressed = ev.type == .KEY_DOWN;
    }
    else if(ev.key_code == self.keybinds.key_left) {
        self.input_state.left_pressed = ev.type == .KEY_DOWN;
    }
    else if(ev.key_code == self.keybinds.key_right) {
        self.input_state.right_pressed = ev.type == .KEY_DOWN;
    }
    else if(ev.key_code == self.keybinds.key_start) {
        self.input_state.start_pressed = ev.type == .KEY_DOWN;
    }
    else if(ev.key_code == self.keybinds.key_select) {
        self.input_state.select_pressed = ev.type == .KEY_DOWN;
    }
    else if(ev.key_code == self.keybinds.key_a) {
        self.input_state.a_pressed = ev.type == .KEY_DOWN;
    }
    else if(ev.key_code == self.keybinds.key_b) {
        self.input_state.b_pressed = ev.type == .KEY_DOWN;
    }
    else if(ev.key_code == .Q and (ev.modifiers & sokol.app.modifier_ctrl != 0)) {
        sokol.app.requestQuit();
    }
    else if(escape or mouse_right) {
        self.imgui.imgui_visible = !self.imgui.imgui_visible;
    }
}

pub fn run(self: *Self, init_cb: ?*const fn () callconv(.c) void, 
            frame_cb: ?*const fn () callconv(.c) void,
            deinit_cb: ?*const fn () callconv(.c) void) void {

    sokol.app.run(.{
        .init_cb = init_cb,
        .frame_cb = frame_cb,
        .cleanup_cb = deinit_cb,
        .event_userdata_cb = event,
        .user_data = self, 
        .width = def.window_width,
        .height = def.window_height,
        .icon = .{ .sokol_default = true },
        .window_title = "Zig GB Emulator",
        .logger = .{ .func = sokol.log.func },
    });
}
