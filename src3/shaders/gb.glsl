@header const shaderTypes = @import("shader_types.zig")
@ctype vec2 shaderTypes.Vec2
@ctype vec4 shaderTypes.Color
@ctype ivec4 shaderTypes.Color2bpp

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
    frag_color = color * hw_colors[3] * color_2bpp[0];
}
@end

@program gb vs fs
