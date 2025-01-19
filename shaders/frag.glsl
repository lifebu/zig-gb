#version 330

uniform vec2 u_resolution;
uniform vec4 u_lut[4];

void main() {
    vec2 st = gl_FragCoord.xy / u_resolution;
    int index = 0;
    if(st.x >= 0.5) {
        index += 1;
    }
    if(st.y >= 0.5) {
        index += 2;
    }
    gl_FragColor = u_lut[index];
}

