#version 450
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 targetColor;
    float colorizeMode;
    float blendStrength;
    float hueAdjustment;
} ubuf;

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main() {
    vec4 tex = texture(source, qt_TexCoord0);

    // Mode 3.0: Hue-replace — shift colored pixels' hue toward target, keep neutrals
    if (ubuf.colorizeMode > 2.5) {
        if (tex.a < 0.0039) { fragColor = vec4(0.0); return; }
        vec3 original = tex.rgb / tex.a;
        vec3 hsv = rgb2hsv(original);
        vec3 thsv = rgb2hsv(ubuf.targetColor.rgb);
        float targetHue = fract(thsv.x + ubuf.hueAdjustment / 360.0);
        float colored = smoothstep(0.05, 0.20, hsv.y);
        hsv.x = mix(hsv.x, targetHue, ubuf.blendStrength);
        hsv.y = mix(hsv.y, thsv.y, colored * ubuf.blendStrength);
        vec3 shifted = hsv2rgb(hsv);
        vec3 result = mix(original, shifted, ubuf.blendStrength);
        fragColor = vec4(result * tex.a, tex.a) * ubuf.qt_Opacity;
        return;
    }

    float intensity;

    if (ubuf.colorizeMode < 0.5) {
        // Dock mode: Convert to grayscale using proper luminance weights
        intensity = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
    } else if (ubuf.colorizeMode < 1.5) {
        // Tray mode: Use the maximum RGB channel value as intensity
        intensity = max(max(tex.r, tex.g), tex.b);

        // Normalize intensity to make all icons more uniform
        intensity = smoothstep(0.1, 0.9, intensity);
    } else {
    // Distro mode: Brightness boost with proper alpha handling
    float maxChannel = max(max(tex.r, tex.g), tex.b);

    intensity = maxChannel * 1.5;
    intensity = min(intensity, 1.0);
    intensity = intensity * 0.7 + 0.3;

    intensity = intensity * tex.a;

    fragColor = vec4(ubuf.targetColor.rgb * intensity, tex.a) * ubuf.qt_Opacity;
}

    fragColor = vec4(ubuf.targetColor.rgb * intensity, tex.a) * ubuf.qt_Opacity;
}
