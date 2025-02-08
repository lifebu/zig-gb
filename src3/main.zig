const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");
const Platform = @import("platform.zig");

const Mode = enum(u2) {
    h_blank,
    v_blank,
    oam_scan,
    draw,
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

        /// returns true if succeeded.
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

        pub fn clear(self: *Self) void {
            self.read_idx = self.write_idx;
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
    advance_mode_draw,
    advance_mode_hblank,
    advance_mode_oam_scan,
    advance_mode_vblank,
    clear_fifo,
    fetch_construct,
    fetch_data_high,
    fetch_data_low,
    fetch_push,
    fetch_tile,
    inc_lcd_y,
    nop,
    nop_draw,
    oam_check,
    push_pixel,
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
    // TODO: std.BoundedArray allows to pop one element from the back. 
    // TODO: But it would be convenient if we had a BoundedArray as a FIFO (new use case for the pixel fifo type? only requires tryPushSlice() instead of tryPush8().
    // TODO: Have a way to know where a MicroOp came from to debug this! (add a second byte with runtime information and advance pc by two?)
    var uop_buf: [CYCLES_PER_LINE]MicroOp = [1]MicroOp{ .nop } ** CYCLES_PER_LINE;
    var uop_pc: u16 = 0;
    var lcd_y: u8 = 0; 
    var fetcher_tilemap_addr: u16 = 0;
    var fetcher_tile_addr: u16 = 0;
    var fetcher_data_low: u8 = 0;
    var fetcher_data_high: u8 = 0;
    var fetcher_bg_data: [def.TILE_WIDTH]BackgroundFifoPixel = undefined;
    // TODO: This can exist implicitly in the gb memory later.
    var mode: Mode = .oam_scan;
    var oam_scan_idx: u6 = 0;
    // TODO: can also be filled partially, do we use a zig's BoundedArray? write_idx? invalid_oam_index?
    // TODO: What data do we store here, what is easiest for the draw function? a list of indices into OAM? A copy of the object? Pre-digested data?
    // https://www.reddit.com/r/EmuDev/comments/1bpxuwp/gameboy_ppu_mode_2_oam_scan/ => X-Pos (8-bits), Tile-Row 0-15 (4 bits), sprite-num 0-39 (6 bits)
    var oam_line_list: std.BoundedArray(u6, 10) = std.BoundedArray(u6, 10).init(0) catch unreachable;

    var color2bpp: [def.NUM_2BPP]u8 = [40]u8{  
        0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15, 16, 16, 17, 17, 18, 18, 19, 19, 
    } ** 144;
};

const TILE_SIZE_X = 8;
const TILE_SIZE_Y = 8;
const TILE_SIZE_BYTE = 16;

const OAM_SIZE = 40;

const oam_scan_uops = [_]MicroOp{ .oam_check, .nop } ** (OAM_SIZE - 1) 
                      ++ [_]MicroOp{ .oam_check, .advance_mode_draw };
// TODO: Add override uOps in this buffer to enable window and objects!
// TODO: Check again if this buffer actualy makes sense. The fetch_push is tried multiple times until the push succeeds. 
const draw_uops = [_]MicroOp{ .fetch_tile, .nop_draw, .fetch_data_low, .nop_draw, .fetch_data_high, .fetch_construct, .nop_draw, .nop_draw, .fetch_push } ** 19 
               ++ [_]MicroOp{ .advance_mode_hblank };

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

fn tryPushPixel() void {
    // TODO: Use both pixel fifos to try to push a pixel to the screen.
}

export fn frame() void {
    // Note: GB actually runs at 59.73Hz
    const T_CYCLES_IN_60FPS = def.SYSTEM_FREQ / 60; 
    for(0..T_CYCLES_IN_60FPS) |cycle_idx| {
        if(cycle_idx == 0) {}
        // ppu
        const lcd_control = LcdControl.fromMem(state.memory);
        const uop: MicroOp = state.uop_buf[state.uop_pc];
        state.uop_pc += 1;
        switch(uop) {
            .advance_mode_draw => {
                state.mode = .draw;
                std.debug.assert(draw_uops.len == 172);
                std.mem.copyForwards(MicroOp, state.uop_buf[0..draw_uops.len], &draw_uops);
                state.background_fifo.clear();
                state.object_fifo.clear();
                state.fetcher_tilemap_addr = if(lcd_control.bg_map_area == .first_map) mem_map.FIRST_TILE_MAP_ADDRESS else mem_map.SECOND_TILE_MAP_ADDRESS;
                state.uop_pc = 0;
            },
            .fetch_construct => {
                // TODO: this is no longer in 2bp, which I assumed would be best to be pushed to the shader. A better way to do this?
                // TODO: Maybe we split the data in the fetcher_bg_data into 2bpp color and palette_data? 
                for(0..state.fetcher_bg_data.len) |bit_idx| {
                    const bit_offset: u3 = 7 - @as(u3, @intCast(bit_idx));
                    const one: u8 = 1;
                    const mask: u8 = one << bit_offset;
                    const firstBit: u8 = (state.fetcher_data_low & mask) >> bit_offset;
                    const secondBit: u8 = (state.fetcher_data_high & mask) >> bit_offset;
                    const colorID: u2 = @intCast(firstBit + (secondBit << 1)); // LSB first
                    const palleteID: u3 = 0; // Only for objects
                    state.fetcher_bg_data[bit_idx] = .{ .colorID = colorID, .palleteID = palleteID };
                }
                tryPushPixel();
            },
            // TODO: Try to combine fetch_data_high and fetch_data_low 
            .fetch_data_high => {
                state.fetcher_data_high = state.memory[state.fetcher_tile_addr];
                state.fetcher_tile_addr += 1;
                tryPushPixel();
            },
            .fetch_data_low => {
                state.fetcher_data_low = state.memory[state.fetcher_tile_addr];
                state.fetcher_tile_addr += 1;
                tryPushPixel();
            },
            .fetch_push => {
                const succeeded: bool = state.background_fifo.tryPush8(state.fetcher_bg_data);
                if(!succeeded) unreachable;
                // TODO: If we fail to push we need to try again.
                tryPushPixel();
            },
            .fetch_tile => {
                const bgWindowTileBaseAddress: u16 = if(lcd_control.bg_window_tile_data == .second_tile_data) mem_map.SECOND_TILE_ADDRESS else mem_map.FIRST_TILE_ADDRESS;
                const signedAdressing: bool = bgWindowTileBaseAddress == mem_map.SECOND_TILE_ADDRESS;
                var tileAddressOffset: u16 = state.memory[state.fetcher_tilemap_addr];
                // TODO: This feels like something that can be done better.
                if(signedAdressing) {
                    if(tileAddressOffset < 128) {
                        tileAddressOffset += 128;
                    } else {
                        tileAddressOffset -= 128;
                    }
                }

                state.fetcher_tile_addr = bgWindowTileBaseAddress + tileAddressOffset * TILE_SIZE_BYTE;
                state.fetcher_tilemap_addr += 1;
                tryPushPixel();
            },
            .nop => {},
            .nop_draw => {
                tryPushPixel();
            },
            .oam_check => {
                const object = Object.fromOAM(state.memory, state.oam_scan_idx);
                const object_height: u8 = if(lcd_control.obj_size == .double_height) TILE_SIZE_Y * 2 else TILE_SIZE_Y;
                if(state.lcd_y + 16 >= object.y_position and state.lcd_y + 16 < object.y_position + object_height) {
                    // starting from the 11th object, this will throw an error. Fine, we only need the first 10.
                    state.oam_line_list.append(state.oam_scan_idx) catch {};
                }
                state.oam_scan_idx += 1;
            },
            else => { 
                std.debug.print("PPU_MICRO_OP_NOT_IMPLEMENTED: {any}\n", .{uop});
                unreachable; 
            },
        }
    }

    Platform.frame(&state.platform, state.color2bpp, state.gb_sample_buffer);
}

export fn cleanup() void {
    Platform.cleanup();
}

pub fn main() void {
    Platform.run(init, frame, cleanup);
}
