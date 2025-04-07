#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

float r(float2 p)
{
    return fract(cos(p.x * 42.98 + p.y * 43.23) * 1127.53);
}

float n(float2 p)
{
    float2 fn = floor(p);
    float2 sn = smoothstep(float2(0.0), float2(1.0), fract(p));

    float h1 = mix(r(fn), r(fn + float2(1.0, 0.0)), sn.x);
    float h2 = mix(r(fn + float2(0.0, 1.0)), r(fn + float2(1.0, 1.0)), sn.x);
    return mix(h1, h2, sn.y);
}

float noise(float2 p)
{
    return n(p / 32.0) * 0.58 +
    n(p / 16.0) * 0.2 +
    n(p / 8.0)  * 0.1 +
    n(p / 4.0)  * 0.05 +
    n(p / 2.0)  * 0.02 +
    n(p)        * 0.0125;
}

[[ stitchable ]] half4 removeEffect(float2 position, half4 currentColor, float t, float2 size) {
    return mix(currentColor, half4(0), smoothstep(t + .1, t - .1, noise(position * .4)));
}

[[stitchable]] half4 green(float2 position, half4 currentColor) {
    // red: 0, green: 1, blue: 0, alpha: 1
    return half4(0, 1, 0, 1);
}
