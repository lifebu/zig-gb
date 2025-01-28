
pub const Vec2 = extern struct {
    x: f32,
    y: f32,
};

// TODO: Rename this to just Vec4 and change fromU8 function to fromColor and it exists outside of struct!
pub const Color = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub fn fromU8(r: u8, g: u8, b: u8, a: u8) Color {
        return Color{ 
            .r = @as(f32, @floatFromInt(r)) / 255.0,
            .g = @as(f32, @floatFromInt(g)) / 255.0,
            .b = @as(f32, @floatFromInt(b)) / 255.0,
            .a = @as(f32, @floatFromInt(a)) / 255.0,
        };
    }
};

// TODO: We should try to more compactly use the i32 one i32 can have 2 tiles of 2bpp.
// TODO: Rename this to just iVec4. 
pub const Color2bpp = extern struct {
    first_bitplane1: i32,
    first_bitplane2: i32,
    second_bitplane1: i32,
    second_bitplane2: i32,
};

// TODO: Maybe rename this to compress color for shader?
pub fn Color2bppToShader(_: []u8) []Color2bpp {

}
