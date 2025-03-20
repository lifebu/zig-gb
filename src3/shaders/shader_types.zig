// TODO: Divide the code into modules with different source folders. So I don't have to use relative paths (see floooh/chipz)
const def = @import("../defines.zig");

pub const Vec2 = extern struct {
    x: f32,
    y: f32,
};

pub const Vec4 = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
};

pub const IVec4 = extern struct {
    x: i32,
    y: i32,
    z: i32,
    w: i32,
};

pub fn shaderRgbaU32(r: u8, g: u8, b: u8, a: u8) u32 {
    const r32: u32 = @as(u32, r);
    const g32: u32 = @as(u32, g) << 8;
    const b32: u32 = @as(u32, b) << 16;
    const a32: u32 = @as(u32, a) << 24;
    return r32 | g32 | b32 | a32;
}
