const std = @import("std");
const assert = std.debug.assert;

const MemMap = @import("mem_map.zig");
const MMU = @import("mmu.zig");
const SoundStreamBuffer = @import("util/SoundStreamBuffer.zig");

const Self = @This();

const WAVE_DUTY_TABLE = [4][8]u1 {
    [_]u1{ 0, 0, 0, 0, 0, 0, 0, 1},
    [_]u1{ 0, 0, 0, 0, 0, 0, 1, 1},
    [_]u1{ 0, 0, 0, 0, 1, 1, 1, 1},
    [_]u1{ 1, 1, 1, 1, 1, 1, 0, 0},
};

const AudioControl = packed struct(u8) {
    ch1_enabled: bool,
    ch2_enabled: bool,
    ch3_enabled: bool,
    ch4_enabled: bool,
    _: u3,
    audio_enabled: bool,
};


pub fn step(_: *Self, mmu: *MMU, _: *SoundStreamBuffer) void {
    const memory: *[]u8 = mmu.getRaw();
    // TODO: Can this be done without ptr?
    const audio_control: *align(1) AudioControl = @ptrCast(&memory.*[MemMap.LCD_CONTROL]);

    if(!audio_control.audio_enabled) {
        return;
    }

    
}
