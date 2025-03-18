@header const shaderTypes = @import("shader_types.zig")
@ctype vec2 shaderTypes.Vec2
@ctype vec4 shaderTypes.Vec4
@ctype ivec4 shaderTypes.IVec4

@vs vs
layout(location=0) in vec2 pos_in;
layout(location=1) in vec2 uv_in;

out vec2 uv;

void main()
{
    gl_Position = vec4(pos_in*2.0-1.0, 0.5, 1.0);
    uv = uv_in;
}
@end

@fs fs
layout(binding=0) uniform texture2D color_texture;
layout(binding=1) uniform texture2D palette_texture;
layout(binding=0) uniform sampler texture_sampler;

in vec2 uv;
out vec4 frag_color;

void main() {    
    float color_id = texture(sampler2D(color_texture, texture_sampler), uv).x;
    vec3 hw_color = texture(sampler2D(palette_texture, texture_sampler), vec2(color_id, 0)).xyz;
    frag_color = vec4(hw_color, 1.0);
}
@end

@program gb vs fs
