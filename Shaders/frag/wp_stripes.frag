// ===== wp_stripes.frag =====
#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source1;  // Current wallpaper
layout(binding = 2) uniform sampler2D source2;  // Next wallpaper

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;      // Transition progress (0.0 to 1.0)
    float stripeCount;   // Number of stripes (default 12.0)
    float angle;         // Angle of stripes in degrees (default 30.0)
    float smoothness;    // Edge smoothness (0.0 to 1.0, 0=sharp, 1=very smooth)
    float aspectRatio;   // Width / Height of the screen
} ubuf;

void main() {
    vec2 uv = qt_TexCoord0;
    vec4 color1 = texture(source1, uv);  // Current (old) wallpaper
    vec4 color2 = texture(source2, uv);  // Next (new) wallpaper
    
    // Map smoothness from 0.0-1.0 to 0.001-0.1 range
    // Using a non-linear mapping for better control at low values
    float mappedSmoothness = mix(0.001, 0.1, ubuf.smoothness * ubuf.smoothness);
    
    // Use values directly without forcing defaults
    float stripes = (ubuf.stripeCount > 0.0) ? ubuf.stripeCount : 12.0;
    float angleRad = radians(ubuf.angle);
    float edgeSmooth = mappedSmoothness;
    
    // Create a coordinate system for stripes based on angle
    // At 0°: vertical stripes (divide by x)
    // At 45°: diagonal stripes
    // At 90°: horizontal stripes (divide by y)
    
    // Transform coordinates based on angle
    float cosA = cos(angleRad);
    float sinA = sin(angleRad);
    
    // Project the UV position onto the stripe direction
    // This gives us the position along the stripe direction
    float stripeCoord = uv.x * cosA + uv.y * sinA;
    
    // Perpendicular coordinate (for edge movement)
    float perpCoord = -uv.x * sinA + uv.y * cosA;
    
    // Calculate the range of perpCoord based on angle
    // This determines how far edges need to travel to fully cover the screen
    float minPerp = min(min(0.0 * -sinA + 0.0 * cosA, 1.0 * -sinA + 0.0 * cosA),
                       min(0.0 * -sinA + 1.0 * cosA, 1.0 * -sinA + 1.0 * cosA));
    float maxPerp = max(max(0.0 * -sinA + 0.0 * cosA, 1.0 * -sinA + 0.0 * cosA),
                       max(0.0 * -sinA + 1.0 * cosA, 1.0 * -sinA + 1.0 * cosA));
    
    // Determine which stripe we're in
    float stripePos = stripeCoord * stripes;
    int stripeIndex = int(floor(stripePos));
    
    // Determine if this is an odd or even stripe
    bool isOddStripe = (stripeIndex % 2) == 1;
    
    // Calculate the progress for this specific stripe with wave delay
    // Use absolute stripe position for consistent delay across all stripes
    float normalizedStripePos = clamp(stripePos / stripes, 0.0, 1.0);
    
    // Reduced delay factor and better scaling to match other shaders' timing
    float maxDelay = 0.15;  // Maximum delay for the last stripe
    float stripeDelay = normalizedStripePos * maxDelay;
    
    // Ensure all stripes complete when progress reaches 1.0
    // without making the overall animation appear faster
    float stripeProgress = clamp((ubuf.progress - stripeDelay) / (1.0 - maxDelay), 0.0, 1.0);
    
    // Apply smooth easing
    stripeProgress = smoothstep(0.0, 1.0, stripeProgress);
    
    // Use the perpendicular coordinate for edge comparison
    float yPos = perpCoord;
    
    // Calculate edge position for this stripe
    // Use the actual perpendicular coordinate range for this angle
    float perpRange = maxPerp - minPerp;
    float margin = edgeSmooth * 2.0;  // Simplified margin calculation
    float edgePosition;
    if (isOddStripe) {
        // Odd stripes: edge moves from max to min
        edgePosition = maxPerp + margin - stripeProgress * (perpRange + margin * 2.0);
    } else {
        // Even stripes: edge moves from min to max
        edgePosition = minPerp - margin + stripeProgress * (perpRange + margin * 2.0);
    }
    
    // Determine which wallpaper to show based on rotated position
    float mask;
    if (isOddStripe) {
        // Odd stripes reveal new wallpaper from bottom
        mask = smoothstep(edgePosition - edgeSmooth, edgePosition + edgeSmooth, yPos);
    } else {
        // Even stripes reveal new wallpaper from top
        mask = 1.0 - smoothstep(edgePosition - edgeSmooth, edgePosition + edgeSmooth, yPos);
    }
    
    // Mix the wallpapers
    fragColor = mix(color1, color2, mask);
    
    // Force exact values at start and end to prevent any bleed-through
    if (ubuf.progress <= 0.0) {
        fragColor = color1;  // Only show old wallpaper at start
    } else if (ubuf.progress >= 1.0) {
        fragColor = color2;  // Only show new wallpaper at end
    } else {
        // Add manga-style edge shadow only during transition
        float edgeDist = abs(yPos - edgePosition);
        float shadowStrength = 1.0 - smoothstep(0.0, edgeSmooth * 2.5, edgeDist);
        shadowStrength *= 0.2 * (1.0 - abs(stripeProgress - 0.5) * 2.0);
        fragColor.rgb *= (1.0 - shadowStrength);
        
        // Add slight vignette during transition for dramatic effect  
        float vignette = 1.0 - ubuf.progress * 0.1 * (1.0 - abs(stripeProgress - 0.5) * 2.0);
        fragColor.rgb *= vignette;
    }
    
    fragColor *= ubuf.qt_Opacity;
}