// The last pass: the HDR scene, plus bloom, through the tone curve, then to
// the screen. Tone mapping is a choice, so tests can turn it off and read back
// exactly what the scene pass produced.
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 result;

layout(set = 2, binding = 0) uniform sampler2D u_hdr;
layout(set = 2, binding = 1) uniform sampler2D u_bloom;

// params: x exposure, y bloom strength, z tone-map mode (0 none, 1 Reinhard,
// 2 ACES), w bloom threshold.
layout(set = 3, binding = 0) uniform Post { vec4 params; vec4 texel; };

// The sRGB transfer function, which is what the display expects: a linear slope
// near black (where a pure power curve crushes detail) and a 1/2.4 power above
// it. `pow(c, 1/2.2)` is the usual shortcut; it is close but not the same, and
// the difference is largest exactly where the eye is most sensitive.
vec3 srgb_encode(vec3 c) {
    vec3 low = c * 12.92;
    vec3 high = 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
    return mix(low, high, step(vec3(0.0031308), c));
}

// The Narkowicz ACES approximation: filmic, keeps hue, clips gracefully.
vec3 aces(vec3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void main() {
    vec3 c = texture(u_hdr, v_uv).rgb;
    if (params.y > 0.0) { c += texture(u_bloom, v_uv).rgb * params.y; }
    c *= params.x;
    if (params.z > 1.5) {
        c = aces(c);
    } else if (params.z > 0.5) {
        c = c / (1.0 + c);
    }
    // Encoding only when tone mapping is on: with it off the output is the
    // linear value the scene pass wrote, exactly as in 0.2.
    if (params.z > 0.5) { c = srgb_encode(c); }
    result = vec4(c, 1.0);
}
