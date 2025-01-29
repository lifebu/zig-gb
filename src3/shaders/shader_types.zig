
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

pub fn shaderRGBA(r: u8, g: u8, b: u8, a: u8) Vec4 {
    return Vec4{ 
        .x = @as(f32, @floatFromInt(r)) / 255.0,
        .y = @as(f32, @floatFromInt(g)) / 255.0,
        .z = @as(f32, @floatFromInt(b)) / 255.0,
        .w = @as(f32, @floatFromInt(a)) / 255.0,
    };
}

// TODO: IVec uses i32 which can store 4 u8s. So we can compress the amount of data send to the GPU further?
// TODO: Use some public defines for this!
const TWOBPP_SIZE = 40 * 144;
const IVEC_SIZE = TWOBPP_SIZE / 4;
pub fn shader2BPPCompress(in: [TWOBPP_SIZE]u8) [IVEC_SIZE]IVec4 {
    var ret_val: [IVEC_SIZE]IVec4 = undefined;
    for(0..IVEC_SIZE) |i| {
        const base_idx = i * 4;
        ret_val[i] = IVec4{ .x = in[base_idx], .y = in[base_idx + 1], .z = in[base_idx + 2], .w = in[base_idx + 3], };
    }
    return ret_val;
}
