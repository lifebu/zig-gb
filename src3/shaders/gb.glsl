@header const shaderTypes = @import("shader_types.zig")
@ctype vec2 shaderTypes.Vec2
@ctype vec4 shaderTypes.Vec4
@ctype ivec4 shaderTypes.IVec4

@vs vs
layout(location = 0) in vec4 position;

void main()
{
    gl_Position = position;
}
@end

@fs fs

const int RESOLUTION_WIDTH = 160;
const int RESOLUTION_HEIGHT = 144;

const int TILE_WIDTH = 8;
const int RESOLUTION_TILE_WIDTH = RESOLUTION_WIDTH / TILE_WIDTH;

const int BYTE_PER_LINE = 2;
const int NUM_BYTES = RESOLUTION_TILE_WIDTH * BYTE_PER_LINE * RESOLUTION_HEIGHT;
const int NUM_IVEC4 = NUM_BYTES / 4;

layout(binding = 0) uniform init {
    vec4 hw_colors[4];
    vec2 resolution;
};
// TODO: I would like to move the code to use a texture with R8UI pixelformat (8-bit single channel unsigned integer). 
// I get a compile error, when I try to use a utexture1D with a usampler1D :(
// Also the shader compiler creates an "INVALID" texture type!
// The only think I can do then is to create a 2d texture? 
// And using the colorIds directly (which would be better) also does not work. It seems that I have a hardlimit on 4096 uniform elements.
// where the update array bellow is 1440 elements. So the vector I put in here can only b:wae 4096 - 5 (hw_color and resolution) = 4091
// I would only be able to do this with packing 4 colorIds (u8) into the same i32. Because: 160*144 = 23.040 / 4 (IVec4) = 5760 / 4 (u8 in i32) = 1440
// Texture path: use a 2D texture with R8UI pixelformat.
// BUT THIS ALSO DOES NOT WORK BECAUSE OF OLD HLSL VERSIONS!
// Would be nice to use R8UI, 
// For this i should be able to use sokol.gfx.updateImage(), sokol.gfx.bind.images, sokol.gfx.sg_make_image(), sokol.bind.samplers like in this example:
// https://github.com/floooh/sokol-samples/blob/master/sapp/texcube-sapp.c
// And according to https://www.khronos.org/opengl/wiki/Texture and https://www.khronos.org/opengl/wiki/Image_Format i should be able to create a R8UI texture.
// https://github.com/floooh/chipz/blob/main/src/host/gfx.zig#L332
// https://github.com/floooh/chipz/blob/main/src/host/shaders.glsl
// https://github.com/floooh/chipz/blob/main/src/common/glue.zig
    // They use a stream image with .R8 2D texture, with nearest neighbor sampling and much better shaders!
layout(binding = 1) uniform update {
    ivec4 color_2bpp[NUM_IVEC4];
};

layout(location = 0) out vec4 frag_color;

void main()
{
    vec2 screen_pos = gl_FragCoord.xy / resolution;
    screen_pos.y = 1.0 - screen_pos.y;
    
    ivec2 pixel_pos = ivec2( floor(screen_pos.x * RESOLUTION_WIDTH), floor(screen_pos.y * RESOLUTION_HEIGHT)); 
    ivec2 tile_row_pos = ivec2( pixel_pos.x / TILE_WIDTH,  pixel_pos.y); 
    int tile_row_idx = tile_row_pos.x + RESOLUTION_TILE_WIDTH * tile_row_pos.y;

    int packed_idx = tile_row_idx / 2;
    ivec4 color_packed = color_2bpp[packed_idx];
    
    int first_plane_idx = (tile_row_idx % 2) * 2;
    int first_bitplane = color_packed[first_plane_idx]; 
    int second_bitplane = color_packed[first_plane_idx + 1]; 

    int tile_pixel_x = int(pixel_pos.x) % TILE_WIDTH;
    int pixel_offset = TILE_WIDTH - tile_pixel_x - 1;

    int pixel_mask = 1 << pixel_offset;
    int first_bit = (first_bitplane & pixel_mask) >> pixel_offset;
    int second_bit = (second_bitplane & pixel_mask) >> pixel_offset;
    int color_id = first_bit + (second_bit << 1); // LSB first

    frag_color = hw_colors[color_id]; 
}
@end

@program gb vs fs
