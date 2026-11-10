// HiPGR built-in textured fragment shader: albedo texture * tint, lit by one
// directional light and up to MAX_POINT_LIGHTS point lights. Set 2 is samplers,
// set 3 fragment uniform blocks.
layout(set = 2, binding = 0) uniform sampler2D u_albedo;

// params.x: 1 = unlit. user0/user1: the material's own data, unused here but
// present so a custom shader can rely on this layout byte for byte.
layout(set = 3, binding = 0) uniform Material { vec4 tint; vec4 params; vec4 user0; vec4 user1; };
// direction.xyz: the direction the light travels in; w: ambient.
// color.rgb: the directional colour; w: how many point lights follow.
// points: per light, (position, radius) then (colour, 0).
layout(set = 3, binding = 1) uniform Light { vec4 direction; vec4 color; vec4 points[16]; };

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec2 v_uv;
layout(location = 2) in vec3 v_world;

layout(location = 0) out vec4 result;

// Irradiance colour at a surface point. The solid shader repeats this function:
// the two are separate shaders, so each must declare its own blocks.
vec3 irradiance(vec3 n, vec3 p) {
    vec3 total = color.rgb * (direction.w + (1.0 - direction.w) * max(dot(n, -direction.xyz), 0.0));
    int count = int(color.w + 0.5);
    for (int i = 0; i < count; i++) {
        vec4 lp = points[i * 2];
        vec4 lc = points[i * 2 + 1];
        vec3 to_light = lp.xyz - p;
        float dist2 = max(dot(to_light, to_light), 1e-6);
        // Smooth to exactly zero at the radius: no cut-off seam, and a light
        // has no effect on geometry it cannot reach.
        float att = max(1.0 - dist2 / (lp.w * lp.w), 0.0);
        att *= att;
        float ndl = max(dot(n, to_light * inversesqrt(dist2)), 0.0);
        total += lc.rgb * (att * ndl);
    }
    return total;
}

void main() {
    vec4 albedo = texture(u_albedo, v_uv) * tint;
    vec3 light = params.x > 0.5 ? vec3(1.0) : irradiance(normalize(v_normal), v_world);
    result = vec4(albedo.rgb * light, albedo.a);
}
