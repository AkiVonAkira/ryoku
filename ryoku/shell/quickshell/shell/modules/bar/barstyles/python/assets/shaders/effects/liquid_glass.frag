#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec4 radii;
    vec4 tintColor;
    float bezel;
    float thickness;
    float ior;
    float dispersion;
    float frost;
    float rim;
    float saturation;
    float tintAmount;
    vec4 srcRect;
    vec2 cursor;
    float hover;
    float clear;
    float glassPad;
    float shadowAmt;
    float energy;
    float nest;
    float morph;
};

layout(binding = 1) uniform sampler2D src;

const int TAPS = 10;
const float GOLDEN = 2.39996323;
const vec2 lightDir = vec2(-0.55, -0.83);

float sdRoundBox(vec2 p, vec2 b, vec4 r) {
    float rad = p.x > 0.0 ? (p.y > 0.0 ? r.z : r.y) : (p.y > 0.0 ? r.w : r.x);
    rad = min(rad, min(b.x, b.y));
    vec2 q = abs(p) - b + rad;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rad;
}

float sdf(vec2 p) {
    return sdRoundBox(p, itemSize * 0.5 - glassPad, radii);
}

vec3 fetchLod(vec2 p, float lod) {
    vec2 uv = clamp((p + itemSize * 0.5) / itemSize, vec2(0.001), vec2(0.999));
    return textureLod(src, srcRect.xy + uv * srcRect.zw, lod).rgb;
}

float ign(vec2 p) {
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float blurLod(float rad) {
    float R = max(rad, 0.5) * 1.5;
    float gap = R * sqrt(3.14159265 / float(TAPS));
    return clamp(log2(max(gap, 1.0)) + 0.35, 0.0, 6.0);
}

vec3 blurredAt(vec2 p, float rad, float lod) {
    float R = max(rad, 0.5) * 1.5;
    float rot = ign(gl_FragCoord.xy) * 6.2831853;
    vec3 acc = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < TAPS; ++i) {
        float fi = float(i) + 0.5;
        float r = sqrt(fi / float(TAPS));
        float a = fi * GOLDEN + rot;
        float w = exp(-2.2 * r * r);
        acc += fetchLod(p + vec2(cos(a), sin(a)) * r * R, lod) * w;
        wsum += w;
    }
    return acc / wsum;
}

vec2 displacement(vec3 normal, float index, float travel) {
    vec3 r = refract(vec3(0.0, 0.0, -1.0), normal, 1.0 / index);
    return r.xy / max(-r.z, 0.2) * travel;
}

void main() {
    vec2 p = qt_TexCoord0 * itemSize - itemSize * 0.5;
    float dist = sdf(p);
    float coverage = clamp(0.5 - dist, 0.0, 1.0);
    float shadow = 0.13 * shadowAmt * (1.0 - smoothstep(-2.0, 9.0, sdf(p - vec2(0.0, 3.0))));
    if (dist > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, shadow) * qt_Opacity;
        return;
    }

    float t = max(-dist, 0.0);
    float bz = max(bezel, 1.0) * 1.45;
    vec2 g = vec2(0.0, -1.0);
    if (t < bz + 2.0) {
        const vec2 e = vec2(0.75, 0.0);
        vec2 grad = vec2(sdf(p + e.xy) - sdf(p - e.xy), sdf(p + e.yx) - sdf(p - e.yx));
        if (length(grad) > 0.0001) g = normalize(grad);
    }

    float u = clamp(t / bz, 0.0, 1.0);
    float om = 1.0 - u;
    float om4 = om * om * om * om;
    float slope = min((om * om * om) / pow(max(1.0 - om4, 1e-3), 0.75), 7.0);
    vec2 toCursor = cursor - itemSize * 0.5 - p;
    float cd = length(toCursor);
    float reach = max(40.0, min(itemSize.x, itemSize.y) * 0.6) * (1.0 + 0.4 * morph);
    float near = hover * exp(-cd * cd / (2.0 * reach * reach));
    float sigma = reach * 0.5;
    float bulgeH = hover * exp(-cd * cd / (2.0 * sigma * sigma)) * 0.35 * (1.0 + 1.4 * morph) * thickness * (1.0 - 0.5 * nest);
    vec2 bulge = bulgeH * toCursor / (sigma * sigma);
    vec3 normal = normalize(vec3(g * slope - bulge, 1.0));
    float th = thickness * 1.35 * (1.0 + (0.12 + 0.3 * morph) * near + 0.5 * energy);

    vec2 dG = displacement(normal, ior, th);
    vec2 dR = dG * (1.0 + dispersion * 0.6);
    vec2 dB = dG * (1.0 - dispersion * 0.6);

    float rad = frost * mix(0.45, 1.0, smoothstep(0.0, bz, t));
    vec2 glassSize = itemSize - 2.0 * glassPad;
    vec2 zq = p / max(glassSize * 0.5, vec2(1.0));
    float zr = clamp(length(zq), 0.0, 1.0);
    float zoomAmt = 0.10 * clamp(energy, 0.0, 1.0);
    vec2 ps = vec2(p.x, p.y * (1.0 - 0.08 * 1.5)) * (1.0 - zoomAmt * (1.0 - zr * zr));
    vec2 follow = clamp((cursor - itemSize * 0.5) / max(itemSize * 0.5, vec2(1.0)), vec2(-1.0), vec2(1.0));
    ps -= follow * 6.0 * near * morph * (1.0 - zr * zr * 0.5);
    float lod = blurLod(rad);
    vec3 col = blurredAt(ps + dG, rad, lod);
    if (dot(dG, dG) > 0.25) {
        col.r = fetchLod(ps + dR, lod + 0.5).r;
        col.b = fetchLod(ps + dB, lod + 0.5).b;
    }

    float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(l), col, saturation);

    float ty = clamp((p.y + glassSize.y * 0.5) / glassSize.y, 0.0, 1.0);
    col *= 1.0 - (1.0 - nest) * 0.06 * exp(-t / 6.0) * clamp(g.y, 0.0, 1.0);
    col *= 1.0 - (1.0 - nest) * 0.025 * exp(-t / (bz * 0.45));

    vec2 cursorDir = cd > 0.001 ? toCursor / cd : normalize(lightDir);
    vec2 L = normalize(mix(normalize(lightDir), cursorDir, hover * 0.4));
    float facing = dot(g, L);
    float spec = pow(max(facing, 0.0), 1.6) + 0.55 * pow(max(-facing, 0.0), 2.2);
    float hair = exp(-t / 1.1);
    float wide = exp(-t / 5.0);
    float edgeHi = (hair * (0.18 + 0.78 * spec) + wide * 0.10 * (0.30 + spec)) * rim * (1.0 + 0.5 * near + 0.9 * energy);
    float mx = (t - bz * 0.5) / (bz * 0.2 + 1.0);
    float men = exp(-mx * mx) * 0.07 * (0.35 + spec) * rim;
    float chroma = max(tintColor.r, max(tintColor.g, tintColor.b)) - min(tintColor.r, min(tintColor.g, tintColor.b));
    float neutralK = 1.0 - smoothstep(0.10, 0.18, chroma);
    vec3 tcol = mix(tintColor.rgb, vec3(0.5), neutralK);
    float tAmt = tintAmount * mix(1.0, 0.6, neutralK);
    float dark = 1.0 - clamp(dot(tcol, vec3(0.2126, 0.7152, 0.0722)) * 2.0, 0.0, 1.0);
    float lift = mix(mix(0.07, 0.04, dark), mix(0.03, 0.02, dark), clear) * (1.0 - 0.85 * nest);
    float sheen = (1.0 - ty) * mix(0.03, 0.02, clear) * (1.0 - 0.8 * nest);
    vec3 light = vec3(edgeHi + men + sheen + near * 0.015 * rim + energy * 0.03);
    light += vec3(lift) * mix(1.0, smoothstep(0.0, 1.0, length(dG) * 0.5), clear);

    float tA = clamp(tAmt * (0.7 + 0.6 * l), 0.0, 1.0);
    float lensA = smoothstep(0.0, 1.0, length(dG) * 0.5);
    vec3 opaqueRgb = mix(col, tcol, tA);
    vec3 clearRgb = col * lensA * (1.0 - tA) + tcol * tA;
    float clearA = lensA * (1.0 - tA) + tA;

    vec3 premul = mix(opaqueRgb, clearRgb, clear);
    premul += light;
    float alpha = mix(1.0, clearA, clear);

    float gn = hash12(gl_FragCoord.xy) + hash12(gl_FragCoord.xy * 1.7 + 17.0) - 1.0;
    premul += vec3(gn * 0.03 * (1.0 - 0.7 * nest)) * alpha;

    float a = coverage * qt_Opacity;
    float outA = clamp(alpha, 0.0, 1.0) * coverage + shadow * (1.0 - coverage);
    fragColor = vec4(clamp(premul, 0.0, 1.0) * a, outA * qt_Opacity);
}
