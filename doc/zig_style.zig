// Zig Style Guide for zig-gb

// File Names:
// A file that only has one type: TypeName.zig
// All other files: file_name.zig

// File Organization:
// Imports: std -> external libs -> internal modules -> build options
// Self = @This()
// Constants -> Types -> Fields
// Functions: init -> deinit -> core -> helper (alphabetical)

// Naming:
// CONSTANTS = snake_case, 
// Types = PascalCase, 
// functions = camelCase, 
// functions returning types = PascalCase
// fields = snake_case
// Abbreviations: capital only first letter (Xml, Ui, Apu)

const std = @import("std");
const sokol = @import("sokol");
const APU = @import("apu.zig");
const build_options = @import("build_options");

const Self = @This();

const const_name: u16 = 42;
const primitive_type_alias = f32;
const string_alias = []u8;

const StructName = struct { 
    field: i32 
};
const EnumName = enum { 
    ok, 
    not_ok 
};
const PackedStruct = packed struct(u8) { 
    lo: u4, 
    hi: u4 
};

field_name: i32 = 0,

pub fn init(self: *Self, io: std.Io, alloc: std.mem.Allocator) void {
    self.* = .{};
}

pub fn deinit(_: *Self, io: std.Io, alloc: std.mem.Allocator) void {}

pub fn publicFunction(self: *Self) void {}

fn aHelperFunction(self: *Self) void {}

fn bHelperFunction(self: *Self) void {}

fn FunctionThatReturnsType(comptime T: type, comptime n: usize) type {
    return struct {
        field_name: [n]T,
        fn methodName() void {}
    };
}