#version 330

const int BYTE_PER_LINE = 2;
const int LINE_WIDTH = 8;
const int RESOLUTION_WIDTH = 160;
const int RESOLUTION_LINE_WIDTH = RESOLUTION_WIDTH / LINE_WIDTH;
const int RESOLUTION_HEIGHT = 144;

uniform vec2 u_Resolution;
// 2bpp
uniform int u_ColorIds[RESOLUTION_LINE_WIDTH * BYTE_PER_LINE * RESOLUTION_HEIGHT];
uniform vec4 u_HwColors[4];


void main() {
    vec2 screenPos = gl_FragCoord.xy / u_Resolution;
    // convert from openGL bottom-left to top-left
    screenPos.y = 1.0 - screenPos.y;
    vec2 pixelPos = vec2( screenPos.x * RESOLUTION_WIDTH,  screenPos.y * RESOLUTION_HEIGHT); 
    vec2 pixelLinePos = vec2( pixelPos.x / LINE_WIDTH,  pixelPos.y); 
    int colorIdx = (int(pixelLinePos.x) * BYTE_PER_LINE) + (int(pixelLinePos.y) * RESOLUTION_WIDTH * BYTE_PER_LINE);

    int firstBitplane = u_ColorIds[colorIdx];
    int secondBitplane = u_ColorIds[colorIdx + 1];
    int pixelOffset = int(pixelPos.x) % LINE_WIDTH;

    int pixelMask = 1 << pixelOffset;
    int firstBit = (firstBitplane & pixelMask) >> pixelOffset;
    int secondBit = (secondBitplane & pixelMask) >> pixelOffset;
    int colorID = firstBit + (secondBit << 1); // LSB first

    gl_FragColor = u_HwColors[colorID];
}

