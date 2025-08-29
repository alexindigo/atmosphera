#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source1;
layout(binding = 2) uniform sampler2D source2;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float fade;
};

void main() {
    vec4 color1 = texture(source1, qt_TexCoord0);
    vec4 color2 = texture(source2, qt_TexCoord0);
    
    // Smooth cross-fade using smoothstep for better visual quality
    float smoothFade = smoothstep(0.0, 1.0, fade);
    
    // Mix the two textures based on fade value
    fragColor = mix(color1, color2, smoothFade) * qt_Opacity;
}