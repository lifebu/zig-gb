#version 330

const int BYTE_PER_LINE = 2;
const int TILE_WIDTH = 8;
const int RESOLUTION_WIDTH = 160;
const int RESOLUTION_TILE_WIDTH = RESOLUTION_WIDTH / TILE_WIDTH;
const int RESOLUTION_HEIGHT = 144;

uniform vec2 u_Resolution;
// 2bpp
// TODO: Can we change this to use unsigned integer? Had trouble getting that to run.
const int NUM_BYTES = RESOLUTION_TILE_WIDTH * BYTE_PER_LINE * RESOLUTION_HEIGHT;
uniform int u_ColorIds[NUM_BYTES];
uniform vec4 u_HwColors[4];


void main() {
    vec2 screenPos = gl_FragCoord.xy / u_Resolution;
    // convert from openGL bottom-left to top-left 0,85
    screenPos.y = 1.0 - screenPos.y;
    // gl_FragColor = vec4(screenPos.x, screenPos.x, screenPos.x, 1.0);
    
    vec2 pixelPos = vec2( screenPos.x * RESOLUTION_WIDTH,  screenPos.y * RESOLUTION_HEIGHT); 
    vec2 pixelLinePos = vec2( pixelPos.x / TILE_WIDTH,  pixelPos.y); 
    // This can access out of the color index, do we need modulo?
    // TODO: This actually access outside of the array! 
    // int colorIdx = int(pixelLinePos.x * BYTE_PER_LINE) + int((pixelLinePos.y) * RESOLUTION_TILE_WIDTH * BYTE_PER_LINE);
    int colorIdx = 36;
    // gl_FragColor = vec4(float(colorIdx) / len, float(colorIdx) / len, float(colorIdx) / len, 1.0);

    int firstBitplane = u_ColorIds[colorIdx];
    int secondBitplane = u_ColorIds[colorIdx + 1];
    int tilePixelX = int(pixelPos.x) % TILE_WIDTH;
    int pixelOffset = TILE_WIDTH - tilePixelX - 1;
    // gl_FragColor = vec4(pixelOffset / 8.0, pixelOffset / 8.0, pixelOffset / 8.0, 1.0);

    int pixelMask = 1 << pixelOffset;
    int firstBit = (firstBitplane & pixelMask) >> pixelOffset;
    int secondBit = (secondBitplane & pixelMask) >> pixelOffset;
    int colorID = firstBit + (secondBit << 1); // LSB first

    gl_FragColor = u_HwColors[colorID]; 
}
