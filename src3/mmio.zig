const std = @import("std");

const def = @import("defines.zig");
const mem_map = @import("mem_map.zig");

const Self = @This();

// timer
const timer_mask_table = [4]u10{ 1024 / 2, 16 / 2, 64 / 2, 256 / 2 };
pub const TimerControl = packed struct(u8) {
    clock: u2 = 0,
    enable: bool = false,
    _: u5 = 0,
};

// serial
pub const SerialControl = packed struct(u8) {
    is_master_clock: bool = true,
    use_high_speed: bool = false,
    _: u5 = 0,
    transfer_enable: bool = false,
};


// joypad
dpad: u4 = 0xF,
buttons: u4 = 0xF,

joypad: u8 = 0xFF,

// timer
// TODO: Try to simplify this.
timer_last_bit: bool = false,
overflow_detected: bool = false,
overflow_tick: u2 = 0,
system_counter: u16 = 0,

divider: u8 = 0,
timer: u8 = 0,
timer_control: TimerControl = .{},
timer_mod: u8 = 0,

// serial
serial_data: u8 = 0xFF,
serial_control: SerialControl = .{},


pub fn init(self: *Self) void {
    self.* = .{};
}

pub fn cycle(self: *Self) struct{ bool, bool } {
    const irq_serial: bool = cycleSerial(self);
    const irq_timer: bool = cycleTimer(self);
    return .{ irq_serial, irq_timer };
}

fn cycleSerial(_: *Self) bool {
    const irq_serial: bool = false;
    return irq_serial;
}

fn cycleTimer(self: *Self) bool {
    var irq_timer: bool = false;

    self.system_counter +%= 1;
    self.divider = @truncate(self.system_counter >> 8);

    const mask = timer_mask_table[self.timer_control.clock];
    const bit: bool = ((self.system_counter & mask) == mask) and self.timer_control.enable;
    // Can happen when timer_last_bit is true and timer_control.enable was set to false this frame (intended GB behavior). 
    const timer_falling_edge: bool = !bit and self.timer_last_bit;
    self.timer, var overflow = @addWithOverflow(self.timer, @intFromBool(timer_falling_edge));
    // TODO: Branchless?
    if(overflow == 1 and self.overflow_detected == false) {
        self.overflow_detected = true;
        self.overflow_tick = 3;
    } else if(self.overflow_detected) {
        // TODO: The timing is exactly 4 cycles. Is this connected to reason for t-cycles and m-cycles?
        // The reason it is delayed is because the cpu can only read it 4 cycles later?
        self.overflow_tick, overflow = @subWithOverflow(self.overflow_tick, 1);
        if(overflow == 1) {
            self.overflow_detected = false;
            irq_timer = true;
            self.timer = self.timer_mod;
        }
    }

    self.timer_last_bit = bit;
    return irq_timer;
}

pub fn request(self: *Self, req: *def.Request) void {
    switch (req.address) {
        mem_map.joypad => {
            req.applyAllowedRW(&self.joypad, 0xCF, 0x30);
            if(req.isWrite()) {
                self.joypad = createJoypad(self);
            }
        },
        mem_map.serial_control => {
            // Note: masks changes on gbc to 0x83
            req.applyAllowedRW(&self.serial_control, 0x81, 0x81);
        },
        mem_map.serial_data => {
            req.apply(&self.serial_data);
        },
        mem_map.divider => {
            req.apply(&self.divider);
            if(req.isWrite()) {
                self.system_counter = 0;
                self.divider = 0;
            }
        },
        mem_map.timer => {
            if(req.isWrite() and self.overflow_tick > 0) {
                self.overflow_detected = false;
            }
            req.apply(&self.timer);
        },
        mem_map.timer_control => {
            req.applyAllowedRW(&self.timer_control, 0x07, 0x07);
        },
        mem_map.timer_mod => {
            req.apply(&self.timer_mod);
        },
        else => {},
    }
}

fn createJoypad(self: *Self) u8 {
    const select_dpad: bool = (self.joypad & 0x10) != 0x10;
    const select_buttons: bool = (self.joypad & 0x20) != 0x20;
    const nibble: u4 = 
    if(select_dpad and select_buttons) self.dpad & self.buttons 
        else if (select_dpad) self.dpad 
            else if (select_buttons) self.buttons
                else 0x0F;

    return (self.joypad & 0xF0) | nibble; 
} 

pub fn updateInputState(self: *Self, input_state: *const def.InputState) bool {
    const last_dpad: u4 = self.dpad;
    const last_buttons: u4 = self.buttons;

    // TODO: Could we implement this better to make this more mathematical with the input self we have?
    self.dpad = 0xF; 
    // disable physically impossible inputs: Left and Right, Up and Down
    self.dpad &= ~(@as(u4, @intFromBool(input_state.right_pressed and !input_state.left_pressed)) << 0);
    self.dpad &= ~(@as(u4, @intFromBool(input_state.left_pressed and !input_state.right_pressed)) << 1);
    self.dpad &= ~(@as(u4, @intFromBool(input_state.up_pressed and !input_state.down_pressed)) << 2);
    self.dpad &= ~(@as(u4, @intFromBool(input_state.down_pressed and !input_state.up_pressed)) << 3);
    
    self.buttons = 0xF;
    self.buttons &= ~(@as(u4, @intFromBool(input_state.a_pressed)) << 0);
    self.buttons &= ~(@as(u4, @intFromBool(input_state.b_pressed)) << 1);
    self.buttons &= ~(@as(u4, @intFromBool(input_state.select_pressed)) << 2);
    self.buttons &= ~(@as(u4, @intFromBool(input_state.start_pressed)) << 3);

    // Interrupts
    return self.dpad < last_dpad or self.buttons < last_buttons;
}
