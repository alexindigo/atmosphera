#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source1;  // Current wallpaper
layout(binding = 2) uniform sampler2D source2;  // Next wallpaper

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;      // Transition progress (0.0 to 1.0)
    float centerX;       // X coordinate of disc center (0.0 to 1.0)
    float centerY;       // Y coordinate of disc center (0.0 to 1.0)
    float smoothness;    // Edge smoothness (0.01 to 0.5, default 0.05)
    float aspectRatio;   // Width / Height of the screen
} ubuf;

void main() {
    vec2 uv = qt_TexCoord0;
    vec4 color1 = texture(source1, uv);  // Current (old) wallpaper
    vec4 color2 = texture(source2, uv);  // Next (new) wallpaper
    
    // Adjust UV coordinates to compensate for aspect ratio
    // This makes distances circular instead of elliptical
    vec2 adjustedUV = vec2(uv.x * ubuf.aspectRatio, uv.y);
    vec2 adjustedCenter = vec2(ubuf.centerX * ubuf.aspectRatio, ubuf.centerY);
    
    // Calculate distance in aspect-corrected space
    float dist = distance(adjustedUV, adjustedCenter);
    
    // Calculate the maximum possible distance (corner to corner)
    // This ensures the disc can cover the entire screen
    float maxDistX = max(ubuf.centerX * ubuf.aspectRatio, 
                         (1.0 - ubuf.centerX) * ubuf.aspectRatio);
    float maxDistY = max(ubuf.centerY, 1.0 - ubuf.centerY);
    float maxDist = length(vec2(maxDistX, maxDistY));
    
    // Scale progress to cover the maximum distance
    // Add extra range for smoothness to ensure complete coverage
    // Adjust smoothness for aspect ratio to maintain consistent visual appearance
    float adjustedSmoothness = ubuf.smoothness * max(1.0, ubuf.aspectRatio);
    float radius = ubuf.progress * (maxDist + adjustedSmoothness);
    
    // Use smoothstep for a smooth edge transition
    float factor = smoothstep(radius - adjustedSmoothness, radius + adjustedSmoothness, dist);
    
    // Mix the textures (factor = 0 inside disc, 1 outside)
    fragColor = mix(color2, color1, factor);
    
    fragColor *= ubuf.qt_Opacity;
}