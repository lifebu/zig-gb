const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

// TODO: Maybe rename this into the memory pins of the CPU?
const MemoryRequest = struct {
    read: ?u16 = null,
    write: ?u16 = null,
    data: *u8 = undefined,

    const Self = @This();
    pub fn print(self: *Self) []u8 {
        var buf: [3]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{s}{s}{s}", .{ 
            if(self.read == null) "-" else "R", 
            if(self.write == null) "-" else "W", 
            if(self.read == null and self.write == null) "-" else "M" 
        }) catch unreachable;
        return &buf;
    }
    pub fn getAddress(self: *Self) u16 {
        return if(self.read != null) self.read.? 
            else if(self.write != null) self.write.? 
            else 0;
    }
};

pub const State = struct {
    memory: [def.addr_space]u8 = [1]u8{0} ** def.addr_space,
    request: MemoryRequest = .{},
};

pub fn init(_: *State) void {
}

pub fn cycle(state: *State) void {
    if(state.request.read) |address| {
        state.request.data.* = state.memory[address];
        state.request.read = null;
    }
    if(state.request.write) |address| {
        state.memory[address] = state.request.data.*;
        state.request.write = null;
    }
}

pub const FileType = enum{
    gameboy,
    dump,
    unknown
};

pub fn getFileType(path: []const u8) FileType {
    // TODO: This should be handled in the cli itself. But this is easier for now :)
    var file_extension: []const u8 = undefined;
    var iter = std.mem.splitScalar(u8, path, '.');
    while(iter.peek() != null) {
        file_extension = iter.next().?;
    }

    if (std.mem.eql(u8, file_extension, "dump")) {
        return .dump;
    } else if (std.mem.eql(u8, file_extension, "gb")) {
        return .gameboy;
    }
    return .unknown;
}

pub fn loadDump(state: *State, path: []const u8, file_type: FileType) void {
    switch(file_type) {
        .gameboy => {
            const file = std.fs.openFileAbsolute(path, .{}) catch unreachable;
            const len = file.readAll(state.memory[mem_map.rom_low..mem_map.rom_high]) catch unreachable;
            std.debug.assert(len == mem_map.rom_high - mem_map.rom_low);
            initMemoryAfterDmgRom(state);
        },
        .dump => {
            const file = std.fs.openFileAbsolute(path, .{}) catch unreachable;
            const len = file.readAll(&state.memory) catch unreachable;
            std.debug.assert(len == state.memory.len);
        },
        .unknown => {
        }
    }
}

fn initMemoryAfterDmgRom(state: *State) void {
    // TODO: emulate boot rom, define initial state for each boot rom or use open source boot rom.
    // Initialize memory state after dmg boot rom has run:
    //
    // state after DMG Boot rom has run.
    // https://gbdev.io/pandocs/Power_Up_Sequence.html#hardware-registers
    state.memory[mem_map.joypad] = 0xCF;
    state.memory[mem_map.serial_data] = 0xFF; // TODO: Stubbing serial communication, should be 0x00.
    state.memory[mem_map.serial_control] = 0x7E;
    state.memory[mem_map.divider] = 0xAB;
    state.memory[mem_map.timer] = 0x00;
    state.memory[mem_map.timer_mod] = 0x00;
    state.memory[mem_map.timer_control] = 0xF8;
    state.memory[mem_map.interrupt_flag] = 0xE1;
    state.memory[mem_map.ch1_sweep] = 0x80;
    state.memory[mem_map.ch1_length] = 0xBF;
    state.memory[mem_map.ch1_volume] = 0xF3;
    state.memory[mem_map.ch1_low_period] = 0xFF;
    state.memory[mem_map.ch1_high_period] = 0xBF;
    state.memory[mem_map.ch2_length] = 0x20; // TODO: Should be 0x3F, workaround for audio bug.
    state.memory[mem_map.ch2_volume] = 0x00;
    state.memory[mem_map.ch2_low_period] = 0x00; // TODO: Should be 0xFF, workaround for audio bug.
    state.memory[mem_map.ch2_high_period] = 0xB0; // TODO: Should be 0xBF, workaround for audio bug.
    state.memory[mem_map.ch3_dac] = 0x7F;
    state.memory[mem_map.ch3_length] = 0xFF;
    state.memory[mem_map.ch3_volume] = 0x9F;
    state.memory[mem_map.ch3_low_period] = 0xFF;
    state.memory[mem_map.ch3_high_period] = 0xBF;
    state.memory[mem_map.ch4_length] = 0xFF;
    state.memory[mem_map.ch4_volume] = 0x00;
    state.memory[mem_map.ch4_freq] = 0x00;
    state.memory[mem_map.ch4_control] = 0xBF;
    state.memory[mem_map.master_volume] = 0x77;
    state.memory[mem_map.sound_panning] = 0xF3;
    state.memory[mem_map.sound_control] = 0xF1;
    state.memory[mem_map.lcd_control] = 0x91;
    state.memory[mem_map.lcd_stat] = 0x80; // TODO: Should be 85, using 80 for now so that my ppu fake timings work
    state.memory[mem_map.scroll_y] = 0x00;
    state.memory[mem_map.scroll_x] = 0x00;
    state.memory[mem_map.lcd_y] = 0x00;
    state.memory[mem_map.lcd_y_compare] = 0x00;
    state.memory[mem_map.dma] = 0xFF;
    state.memory[mem_map.bg_palette] = 0xFC;
    state.memory[mem_map.obj_palette_0] = 0xFF;
    state.memory[mem_map.obj_palette_1] = 0xFF;
    state.memory[mem_map.window_y] = 0x00;
    state.memory[mem_map.window_x] = 0x00;
    state.memory[mem_map.interrupt_enable] = 0x00;
}
