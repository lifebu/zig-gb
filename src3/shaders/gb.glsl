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
