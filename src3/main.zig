const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");
const Platform = @import("platform.zig");

const Mode = enum(u2) {
    h_blank,
    v_blank,
    oam_scan,
    draw,

    pub fn advance(self: *Mode, lcd_y: u8) void {
        self.* = switch (self.*) {
            .h_blank => if(lcd_y < def.RESOLUTION_HEIGHT - 1) .oam_scan else .v_blank,
            .oam_scan => .draw,
            .draw => .h_blank,
            .v_blank => .oam_scan,
        };
    }
};

const BackgroundFifoPixel = packed struct(u5) {
    palleteID: u3 = 0,
    colorID: u2 = 0,
};

const ObjectFifoPixel = packed struct(u12) {
    obj_prio: u6 = 0, // CGB: OAM index, DMG: Unused
    palleteID: u3 = 0,
    colorID: u2 = 0, 
    bg_prio: u1 = 0,
};

pub fn PixelFifo(comptime T: type) type {
   return struct {
        const Self = @This();

        const FIFO_LENGTH = def.TILE_WIDTH * 2;
        pixels: [FIFO_LENGTH]T = undefined,
        write_idx: usize = 0,
        read_idx: usize = 0,

        pub fn pop(self: *Self) T {
            std.debug.assert(self.read_idx != self.write_idx);

            const value = self.pixels[self.read_idx];
            self.read_idx = (self.read_idx + 1) % FIFO_LENGTH;
            return value;
        }

        pub fn tryPush8(self: *Self, pixels: [def.TILE_WIDTH]T) bool {
            const offset = FIFO_LENGTH * @as(usize, @intFromBool(self.write_idx < self.read_idx));
            const length = self.write_idx + offset - self.read_idx;
            if(length + pixels.len > FIFO_LENGTH) {
                return false;
            }

            inline for(0..pixels.len) |i| {
                self.pixels[self.write_idx] = pixels[i];
                self.write_idx = (self.write_idx + 1) % FIFO_LENGTH;
            }
            return true;
        }
    };
}

const LcdControl = packed struct {
    bg_window_enable: bool = false,
    obj_enable: bool = false,
    obj_size: enum(u1) {
        single_height,
        double_height,
    } = .single_height,
    bg_map_area: enum(u1) {
        first_map,
        second_map,
    } = .first_map,
    bg_window_tile_data: enum(u1) {
        second_tile_data,
        first_tile_data,
    } = .second_tile_data,
    window_enable: bool = false,
    window_map_area: enum(u1) {
        first_map,
        second_map,
    } = .first_map,
    lcd_enable: bool = false,

    pub fn fromMem(memory: [def.ADDR_SPACE]u8) LcdControl {
        return @bitCast(memory[mem_map.LCD_CONTROL]);
    } 
};

const OBJ_SIZE_BYTE = 4;
const OBJ_PER_LINE = 10;

const Object = packed struct {
    y_position: u8,
    x_position: u8,
    tile_index: u8,
    flags: packed struct {
        cgb_palette: u3,
        vram_bank: u1,
        dmg_palette: enum(u1) {
            OBP0,
            OBP1,
        },
        x_flip: bool,
        y_flip: bool,
        priority: enum(u1) {
            OBJ_OVER_BG,
            OBJ_UNDER_BG,
        },
    },

    pub fn fromOAM(memory: [def.ADDR_SPACE]u8, obj_idx: u6) *align(1) const Object {
        const address: u16 = mem_map.OAM_LOW + (@as(u16, obj_idx) * OBJ_SIZE_BYTE);
        return @ptrCast(&memory[address]);
    }

    pub fn print(self: Object, obj_idx: u6) void {
        std.debug.print("Object ({any}): ({any}, {any}): tile: {any}, prio: {s}, y_flip: {any}, x_flip: {any}, dmg_palette: {s}, vram_bank: {any}, cgb_palette: {any}\n", .{ 
            obj_idx, self.x_position, self.y_position, self.tile_index, 
            std.enums.tagName(@TypeOf(self.flags.priority), self.flags.priority).?, 
            self.flags.y_flip, self.flags.x_flip, 
            std.enums.tagName(@TypeOf(self.flags.dmg_palette), self.flags.dmg_palette).?, self.flags.vram_bank, self.flags.cgb_palette 
        });
    }
};

const MicroOp = enum {
    nop,
    advance_mode,
    oam_check,
    inc_lcd_y,
    clear_fifo,
    push_pixel,
    fetch_tile,
    fetch_data_low,
    fetch_data_high,
    fetch_construct,
    fetch_push,
};

const CYCLES_PER_LINE = 456;

const state = struct {
    var platform: Platform.State = .{};

    // MMU
    var memory: [def.ADDR_SPACE]u8 = [1]u8{0} ** def.ADDR_SPACE;

    // APU
    var gb_sample_buffer: [def.NUM_GB_SAMPLES]f32 = [1]f32{ 0.0 } ** def.NUM_GB_SAMPLES;

    // PPU
    var background_fifo: PixelFifo(BackgroundFifoPixel) = .{}; 
    var object_fifo: PixelFifo(ObjectFifoPixel) = .{};
    // TODO: std.BoundedArray? Because we sometimes only want to use part of the buffer and loop!
    // TODO: Have a way to know where a MicroOp came from to debug this!
    var uop_buf: [CYCLES_PER_LINE]MicroOp = [1]MicroOp{ .nop } ** CYCLES_PER_LINE;
    var uop_pc: u16 = 0;
    var lcd_y: u8 = 0; 
    var mode: Mode = .oam_scan;
    var oam_scan_idx: u6 = 0;
    // TODO: can also be filled partially, do we use a zig's BoundedArray? write_idx? invalid_oam_index?
    // TODO: What data do we store here, what is easiest for the draw function? a list of indices into OAM? A copy of the object? Pre-digested data?
    var oam_line_list: std.BoundedArray(u6, 10) = std.BoundedArray(u6, 10).init(0) catch unreachable;

    var color2bpp: [def.NUM_2BPP]u8 = [40]u8{  
        0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 16, 16, 17, 17, 18, 18, 19, 19, 
    } ** 144;
};

const TILE_SIZE_X = 8;
const TILE_SIZE_Y = 8;

const OAM_SIZE = 40;
const oam_scan_uops = [_]MicroOp{ .oam_check, .nop } ** (OAM_SIZE - 1) ++ [_]MicroOp{ .oam_check, .advance_mode };
const draw_uops = [_]MicroOp{ .nop };

export fn init() void {
    Platform.init(&state.platform);

    // TODO: sokol requires that we have no error's in it's callback. How do we still allow errors to be thrown gracefully?
    // platform function that calls: sokol.app.requestQuit()? Logs in imgui + render a unrecoverable error image in screen?
    // TODO: Some initialization function when we change state!
    state.oam_line_list.resize(0) catch unreachable;
    state.oam_scan_idx = 0;
    state.uop_pc = 0;
    state.mode = .oam_scan;
    state.lcd_y = 0;
    std.mem.copyForwards(MicroOp, state.uop_buf[0..oam_scan_uops.len], &oam_scan_uops);

    // Some test memory dump.
    const result = std.fs.cwd().readFile("playground/castlevania.dump", &state.memory) catch unreachable;
    std.debug.assert(result.len == state.memory.len);
}

export fn frame() void {
    // Note: GB actually runs at 59.73Hz
    const T_CYCLES_IN_60FPS = def.SYSTEM_FREQ / 60; 
    for(0..T_CYCLES_IN_60FPS) |i| {
        if(i == 0) {}
        // ppu
        const lcd_control = LcdControl.fromMem(state.memory);
        const uop: MicroOp = state.uop_buf[state.uop_pc];
        switch(uop) {
            .nop => {},
            .oam_check => {
                const object = Object.fromOAM(state.memory, state.oam_scan_idx);
                const object_height: u8 = if(lcd_control.obj_size == .double_height) TILE_SIZE_Y * 2 else TILE_SIZE_Y;
                if(state.lcd_y + 16 >= object.y_position and state.lcd_y + 16 < object.y_position + object_height) {
                    // error => object is ignored, because we already found our 10 objects per line. 
                    state.oam_line_list.append(state.oam_scan_idx) catch {};
                }
                state.oam_scan_idx += 1;
            },
            .advance_mode => {
                state.mode.advance(state.lcd_y);
                // TODO: Load the next microcode.
                // TODO: Split advance_mode into the 4 modes, that also loads the microcode and sets's up the state data.
                switch(state.mode) {
                    .h_blank => {

                    },
                    .v_blank => {

                    },
                    .oam_scan => {

                    },
                    .draw => {

                    },
                }
            },
            else => { 
                std.debug.print("PPU_MICRO_OP_NOT_IMPLEMENTED: {any}\n", .{uop});
                unreachable; 
            },
        }
        state.uop_pc += 1;
    }

    Platform.frame(&state.platform, state.color2bpp, state.gb_sample_buffer);
}

export fn cleanup() void {
    Platform.cleanup();
}

pub fn main() void {
    Platform.run(init, frame, cleanup);
}
