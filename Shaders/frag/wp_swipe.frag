#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source1;  // Current wallpaper
layout(binding = 2) uniform sampler2D source2;  // Next wallpaper

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;      // Transition progress (0.0 to 1.0)
    float direction;     // 0=left, 1=right, 2=up, 3=down
    float smoothness;    // Edge smoothness (0.01 to 0.5, default 0.05)
} ubuf;

void main() {
    vec2 uv = qt_TexCoord0;
    vec4 color1 = texture(source1, uv);  // Current (old) wallpaper
    vec4 color2 = texture(source2, uv);  // Next (new) wallpaper
    
    float edge = 0.0;
    float factor = 0.0;
    
    // Extend the progress range to account for smoothness
    // This ensures the transition completes fully at the edges
    float extendedProgress = ubuf.progress * (1.0 + 2.0 * ubuf.smoothness) - ubuf.smoothness;
    
    // Calculate edge position based on direction
    // As progress goes from 0 to 1, we reveal source2 (new wallpaper)
    if (ubuf.direction < 0.5) {
        // Swipe from right to left (new image enters from right)
        edge = 1.0 - extendedProgress;
        factor = smoothstep(edge - ubuf.smoothness, edge + ubuf.smoothness, uv.x);
        fragColor = mix(color1, color2, factor);
    } 
    else if (ubuf.direction < 1.5) {
        // Swipe from left to right (new image enters from left)
        edge = extendedProgress;
        factor = smoothstep(edge - ubuf.smoothness, edge + ubuf.smoothness, uv.x);
        fragColor = mix(color2, color1, factor);
    }
    else if (ubuf.direction < 2.5) {
        // Swipe from bottom to top (new image enters from bottom)
        edge = 1.0 - extendedProgress;
        factor = smoothstep(edge - ubuf.smoothness, edge + ubuf.smoothness, uv.y);
        fragColor = mix(color1, color2, factor);
    }
    else {
        // Swipe from top to bottom (new image enters from top)
        edge = extendedProgress;
        factor = smoothstep(edge - ubuf.smoothness, edge + ubuf.smoothness, uv.y);
        fragColor = mix(color2, color1, factor);
    }
    
    fragColor *= ubuf.qt_Opacity;
}