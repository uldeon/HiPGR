// Bloom, step one: keep what is brighter than the threshold, at half
// resolution. Everything a light or the sun pushed above 1.0 lives here, which
// is exactly what a display cannot show and what a glow should approximate.
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 result;

layout(set = 2, binding = 0) uniform sampler2D u_source;

// params: x exposure, y bloom strength, z tone-map mode, w bloom threshold.
layout(set = 3, binding = 0) uniform Post { vec4 params; vec4 texel; };

void main() {
    vec3 c = texture(u_source, v_uv).rgb;
    float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
    float knee = max(params.w, 0.001);
    float weight = clamp((luma - knee) / knee, 0.0, 1.0);
    result = vec4(c * weight, 1.0);
}
