const std = @import("std");

// TODO: Use modules for the tests to not use relative paths like this!
const def = @import("../defines.zig");
const CPU = @import("../cpu.zig");

const cpu_helper = @import("util/cpu_helper.zig");

pub fn runRegisterTests() !void {
    const r8_rfids = [_]CPU.RegisterFileID{ .a, .f, .dbus, .ir, .sph, .spl, .pch, .pcl, .w, .z, .h, .l, .d, .e, .b, .c };
    const r8_initials = [_]u8{ 0x10, 0x0F, 0x0E, 0x0D, 0x0C, 0x0B, 0x0A, 0x09, 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01 };
    for(r8_rfids, r8_initials) |rfid, initial| {
        var registers: CPU.RegisterFile = @bitCast(@as(u144, 0x1211_100F_0E0D_0C0B_0A09_0807_0605_0403_0201));
        var value: *u8 = registers.getU8(rfid);
        try std.testing.expectEqual(initial, value.*);
        value.* = 0xFF;
        try std.testing.expectEqual(0xFF, value.*);
        value = registers.getU8(rfid);
        try std.testing.expectEqual(0xFF, value.*);
    }

    const r16_rfids = [_]CPU.RegisterFileID{ .f, .ir, .spl, .pcl, .z, .l, .e, .c };
    const r16_rfid_pairs = [_][2]CPU.RegisterFileID{ .{.a, .f }, .{.dbus, .ir }, .{.sph, .spl }, .{.pch, .pcl }, .{.w, .z }, .{.h, .l }, .{.d, .e }, .{.b, .c } };
    const r16_initials = [_]u16{ 0x100F, 0x0E0D, 0x0C0B, 0x0A09, 0x0807, 0x0605, 0x0403, 0x0201 };
    for(r16_rfids, r16_rfid_pairs, r16_initials) |rfid, rfid_pair, initial| {
        var registers: CPU.RegisterFile = @bitCast(@as(u144, 0x1211_100F_0E0D_0C0B_0A09_0807_0605_0403_0201));
        var value: *u16 = registers.getU16(rfid);
        try std.testing.expectEqual(initial, value.*);
        value.* = 0xEEFF;
        try std.testing.expectEqual(0xEEFF, value.*);
        value = registers.getU16(rfid);
        try std.testing.expectEqual(0xEEFF, value.*);

        const r8_expected = [_]u8{ 0xEE, 0xFF };
        for(rfid_pair, r8_expected) |low_high, expected| {
            const r8_value: *u8 = registers.getU8(low_high);
            try std.testing.expectEqual(expected, r8_value.*);
        }
    }

    const zero_pseudo = CPU.PseudoFlagRegister{ .const_zero = 0, .const_one = 0, .temp_msb = 0, .temp_lsb = 0 };
    const ffids = [_]CPU.FlagFileID{ .const_zero, .const_one, .temp_msb, .temp_lsb, .zero, .n_bcd, .half_bcd, .carry };
    const ffid_registers = [_]CPU.RegisterFile{ 
        CPU.RegisterFile{ .r8 = .{ .p = .{ .const_zero = 1, .const_one = 0, .temp_msb = 0, .temp_lsb = 0, }}}, 
        CPU.RegisterFile{ .r8 = .{ .p = .{ .const_zero = 0, .const_one = 1, .temp_msb = 0, .temp_lsb = 0, }}}, 
        CPU.RegisterFile{ .r8 = .{ .p = .{ .const_zero = 0, .const_one = 0, .temp_msb = 1, .temp_lsb = 0, }}}, 
        CPU.RegisterFile{ .r8 = .{ .p = .{ .const_zero = 0, .const_one = 0, .temp_msb = 0, .temp_lsb = 1, }}}, 
        CPU.RegisterFile{ .r8 = .{ .f = .{ .zero = 1, .n_bcd = 0, .half_bcd = 0, .carry = 0 }, .p = zero_pseudo }}, 
        CPU.RegisterFile{ .r8 = .{ .f = .{ .zero = 0, .n_bcd = 1, .half_bcd = 0, .carry = 0 }, .p = zero_pseudo }}, 
        CPU.RegisterFile{ .r8 = .{ .f = .{ .zero = 0, .n_bcd = 0, .half_bcd = 1, .carry = 0 }, .p = zero_pseudo }}, 
        CPU.RegisterFile{ .r8 = .{ .f = .{ .zero = 0, .n_bcd = 0, .half_bcd = 0, .carry = 1 }, .p = zero_pseudo }}, 
    };
    for(ffids, ffid_registers) |ffid, registers| {
        const flag: u1 = registers.getFlag(ffid);
        try std.testing.expectEqual(1, flag);
    }
}
