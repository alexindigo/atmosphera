#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // Custom properties with non-conflicting names
    float itemWidth;
    float itemHeight;
    float sourceWidth;
    float sourceHeight;
    float cornerRadius;
    float imageOpacity;
    int fillMode;
} ubuf;

// Function to calculate the signed distance from a point to a rounded box
float roundedBoxSDF(vec2 centerPos, vec2 boxSize, float radius) {
    vec2 d = abs(centerPos) - boxSize + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

void main() {
    // Get size from uniforms
    vec2 itemSize = vec2(ubuf.itemWidth, ubuf.itemHeight);
    vec2 sourceSize = vec2(ubuf.sourceWidth, ubuf.sourceHeight);
    float cornerRadius = ubuf.cornerRadius;
    float itemOpacity = ubuf.imageOpacity;
    int fillMode = ubuf.fillMode;

    // Work in pixel space for accurate rounded rectangle calculation
    vec2 pixelPos = qt_TexCoord0 * itemSize;

    // Calculate distance to rounded rectangle edge (in pixels)
    vec2 centerOffset = pixelPos - itemSize * 0.5;
    float distance = roundedBoxSDF(centerOffset, itemSize * 0.5, cornerRadius);

    // Create smooth alpha mask for edge with anti-aliasing
    float alpha = 1.0 - smoothstep(-0.5, 0.5, distance);

    // Calculate UV coordinates based on fill mode
    vec2 imageUV = qt_TexCoord0;

    // fillMode constants from Qt:
    // Image.Stretch = 0
    // Image.PreserveAspectFit = 1
    // Image.PreserveAspectCrop = 2
    // Image.Tile = 3
    // Image.TileVertically = 4
    // Image.TileHorizontally = 5
    // Image.Pad = 6

    if (fillMode == 2) { // PreserveAspectCrop
        // Calculate aspect ratios
        float itemAspect = itemSize.x / itemSize.y;
        float sourceAspect = sourceSize.x / sourceSize.y;

        // Calculate the scale needed to cover the item area
        vec2 scale;
        if (sourceAspect > itemAspect) {
            // Image is wider - fit height, crop sides
            scale.y = 1.0;
            scale.x = sourceAspect / itemAspect;
        } else {
            // Image is taller - fit width, crop top/bottom
            scale.x = 1.0;
            scale.y = itemAspect / sourceAspect;
        }

        // Apply scale and center
        imageUV = (qt_TexCoord0 - 0.5) / scale + 0.5;
    } else if (fillMode == 1) { // PreserveAspectFit
        float itemAspect = itemSize.x / itemSize.y;
        float sourceAspect = sourceSize.x / sourceSize.y;

        vec2 scale;
        if (sourceAspect > itemAspect) {
            // Image is wider - fit width, letterbox top/bottom
            scale.x = 1.0;
            scale.y = itemAspect / sourceAspect;
        } else {
            // Image is taller - fit height, letterbox sides
            scale.y = 1.0;
            scale.x = sourceAspect / itemAspect;
        }

        imageUV = (qt_TexCoord0 - 0.5) * scale + 0.5;
    }
    // For Stretch (0) or other modes, use qt_TexCoord0 as-is

    // Sample the texture
    vec4 color = texture(source, imageUV);

    // Apply the rounded mask and opacity
    float finalAlpha = color.a * alpha * itemOpacity * ubuf.qt_Opacity;
    fragColor = vec4(color.rgb * finalAlpha, finalAlpha);
}