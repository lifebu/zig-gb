@header const shaderTypes = @import("shader_types.zig")
@ctype vec2 shaderTypes.Vec2
@ctype vec4 shaderTypes.Vec4
@ctype ivec4 shaderTypes.IVec4

@vs vs
layout(location = 0) in vec4 position;
layout(location = 0) out vec4 color;
layout(location = 1) in vec4 color0;

void main()
{
    gl_Position = position;
    color = color0;
}
@end

@fs fs

const int BYTE_PER_LINE = 2;
const int TILE_WIDTH = 8;
const int RESOLUTION_WIDTH = 160;
const int RESOLUTION_TILE_WIDTH = RESOLUTION_WIDTH / TILE_WIDTH;
const int RESOLUTION_HEIGHT = 144;

const int NUM_BYTES = RESOLUTION_TILE_WIDTH * BYTE_PER_LINE * RESOLUTION_HEIGHT;
const int NUM_IVEC4 = NUM_BYTES / 4;

layout(binding = 0) uniform init {
    vec4 hw_colors[4];
    vec2 resolution;
};
layout(binding = 1) uniform update {
    ivec4 color_2bpp[NUM_IVEC4];
};

layout(location = 0) out vec4 frag_color;
layout(location = 0) in vec4 color;

void main()
{
    frag_color = color * color_2bpp[0].x * resolution.x;
    vec2 screen_pos = gl_FragCoord.xy / resolution;
    // convert from openGL bottom-left to top-left 0,85
    screen_pos.y = 1.0 - screen_pos.y;
    frag_color = vec4(screen_pos.y, screen_pos.y, screen_pos.y, 1.0);
    
    // vec2 pixel_pos = vec2( screen_pos.x * RESOLUTION_WIDTH,  screen_pos.y * RESOLUTION_HEIGHT); 
    // vec2 pixelLinePos = vec2( pixel_pos.x / TILE_WIDTH,  pixel_pos.y); 
    // // This can access out of the color index, do we need modulo?
    // // TODO: This actually access outside of the array! 
    // int color_idx = int(pixelLinePos.x * BYTE_PER_LINE) + int((pixelLinePos.y) * RESOLUTION_TILE_WIDTH * BYTE_PER_LINE);
    // // frag_color = vec4(float(color_idx) / len, float(color_idx) / len, float(color_idx) / len, 1.0);
    //
    // int first_bitplane = color_2bpp[color_idx];
    // int second_bitplane = color_2bpp[color_idx];
    // int tile_pixel_x = int(pixel_pos.x) % TILE_WIDTH;
    // int pixel_offset = TILE_WIDTH - tile_pixel_x - 1;
    // // frag_color = vec4(pixel_offset / 8.0, pixel_offset / 8.0, pixel_offset / 8.0, 1.0);
    //
    // int pixel_mask = 1 << pixel_offset;
    // int first_bit = (first_bitplane & pixel_mask) >> pixel_offset;
    // int second_bit = (second_bitplane & pixel_mask) >> pixel_offset;
    // int color_id = first_bit + (second_bit << 1); // LSB first
    //
    // frag_color = hw_colors[color_id]; 
}
@end

@program gb vs fs
