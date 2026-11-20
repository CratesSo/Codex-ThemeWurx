#include <metal_stdlib>
using namespace metal;

static float3 hueColor(float hue, float saturation, float brightness) {
    float3 rgb = clamp(abs(fract(hue + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    return mix(float3(1.0), rgb, saturation) * brightness;
}

[[ stitchable ]] half4 menuAurora(float2 position, half4 source, float2 size, float time, float dark, float customHue, float brightness, float pairEnabled, half4 firstColor, half4 secondColor) {
    float2 uv = position / max(size, float2(1.0));
    float3 teal = mix(float3(0.0, 0.38, 0.40), float3(0.12, 0.95, 0.78), dark);
    float3 violet = mix(float3(0.40, 0.12, 0.67), float3(0.65, 0.38, 1.0), dark);
    float3 blue = mix(float3(0.08, 0.30, 0.72), float3(0.20, 0.62, 1.0), dark);
    if (customHue >= 1.0) {
        teal = violet = blue = float3(1.0);
    } else if (customHue >= 0.0) {
        teal = hueColor(customHue - 0.04, mix(0.95, 0.75, dark), mix(0.50, 0.95, dark));
        violet = hueColor(customHue + 0.04, mix(0.85, 0.62, dark), mix(0.67, 1.0, dark));
        blue = hueColor(customHue, mix(0.90, 0.80, dark), mix(0.60, 1.0, dark));
    }
    if (pairEnabled > 0.5) {
        teal = float3(firstColor.rgb);
        violet = float3(secondColor.rgb);
        blue = mix(teal, violet, 0.5);
    }
    float3 light = float3(0.0);
    float intensity = 0.0;
    for (int i = 0; i < 3; ++i) {
        float phase = float(i) * 2.1;
        float center = 0.18 + float(i) * 0.32
            + 0.18 * sin(uv.x * 4.2 + time * 0.24 + phase)
            + 0.07 * sin(uv.x * 9.0 - time * 0.38 + phase);
        float distance = uv.y - center;
        float width = 0.065 + 0.025 * sin(uv.x * 3.0 + time * 0.2 + phase);
        float ribbon = exp(-pow(distance / width, 2.0));
        float haze = exp(-pow(distance / (width * 2.8), 2.0));
        float folds = 0.78 + 0.22 * sin(uv.x * 24.0 + sin(uv.y * 7.0 + phase) - time * 0.5);
        float strength = (ribbon * 0.7 + haze * 0.3) * folds;
        float hue = 0.5 + 0.5 * sin(uv.x * 3.0 - time * 0.18 + phase);
        float3 tint = mix(mix(teal, blue, smoothstep(0.0, 0.5, hue)), violet, smoothstep(0.5, 1.0, hue));
        light += tint * strength;
        intensity += strength;
    }
    float3 color = light / max(intensity, 0.001);
    // Cap opacity where ribbons overlap to keep menu text readable.
    float alpha = (1.0 - exp(-intensity)) * mix(0.30, 0.42, dark) * float(source.a);
    color = min(color * brightness, float3(1.0));
    alpha = min(alpha * brightness, 0.65);
    return half4(half3(color * alpha), half(alpha));
}
