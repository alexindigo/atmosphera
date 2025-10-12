#version 450
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 targetColor;
    float colorizeMode; // 0.0 = dock mode (grayscale), 1.0 = tray mode (intensity)
} ubuf;

void main() {
    vec4 tex = texture(source, qt_TexCoord0);
    
    float intensity;
    
    if (ubuf.colorizeMode < 0.5) {
        // Dock mode: Convert to grayscale using proper luminance weights
        intensity = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
    } else {
        // Tray mode: Use the maximum RGB channel value as intensity
        intensity = max(max(tex.r, tex.g), tex.b);
        
        // Normalize intensity to make all icons more uniform
        intensity = smoothstep(0.1, 0.9, intensity);
    }
    
    fragColor = vec4(ubuf.targetColor.rgb * intensity, tex.a) * ubuf.qt_Opacity;
}
