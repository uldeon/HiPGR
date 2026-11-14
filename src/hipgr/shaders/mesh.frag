// HiPGR built-in fragment shader: metallic/roughness PBR, direct lighting from
// one directional light and up to 8 point lights, a shadow map, normal mapping
// from the material's normal map, emissive, and distance fog.
//
// Set 2 is samplers, set 3 fragment uniform blocks. One shader serves solid and
// textured materials: a material with no image samples a 1x1 white texture, and
// one with no normal map samples a flat normal.
layout(set = 2, binding = 0) uniform sampler2D u_albedo;
layout(set = 2, binding = 1) uniform sampler2D u_normal_map;
layout(set = 2, binding = 2) uniform sampler2DShadow u_shadow;
// The sky, integrated: diffuse irradiance, and radiance prefiltered per roughness.
layout(set = 2, binding = 3) uniform samplerCube u_irradiance;
layout(set = 2, binding = 4) uniform samplerCube u_prefiltered;

// params: x unlit, y metallic, z roughness, w normal-map strength.
layout(set = 3, binding = 0) uniform Material {
    vec4 tint;
    vec4 params;
    vec4 user0;
    vec4 user1;
    // The application's eight float4s. The built-in shader does not read them,
    // but the block's size is part of the contract, so they are declared.
    vec4 v[8];
};
// direction.xyz: the direction the light travels in, w: ambient.
// color.rgb: the directional colour, w: point light count.
// points: per light, (position, radius) then (colour, 0).
layout(set = 3, binding = 1) uniform Light {
    vec4 direction;
    vec4 color;
    vec4 points[16];
};

layout(set = 3, binding = 2) uniform Frame {
    mat4 view_proj;
    mat4 light_view_proj;
    vec4 camera_pos;
    vec4 sky;
    vec4 fparams;           // x shadows on, y shadow texel, z shadow bias, w IBL strength
    vec4 cam_right;
    vec4 cam_up;
    vec4 cam_forward;
};
// rgb emitted regardless of light, w unused.
layout(set = 3, binding = 3) uniform Surface { vec4 emissive; };

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec2 v_uv;
layout(location = 2) in vec3 v_world;
layout(location = 3) in vec4 v_shadow;

layout(location = 0) out vec4 result;

const float PI = 3.14159265359;

// Lambertian diffuse plus a GGX microfacet specular lobe: the standard
// metallic/roughness direct-lighting model.
float ndf_ggx(vec3 n, vec3 h, float rough) {
    float a = max(rough * rough, 1e-3);
    float a2 = a * a;
    float ndh = max(dot(n, h), 0.0);
    float d = ndh * ndh * (a2 - 1.0) + 1.0;
    return a2 / max(PI * d * d, 1e-6);
}

float geometry_smith(vec3 n, vec3 v, vec3 l, float rough) {
    float k = (rough + 1.0) * (rough + 1.0) / 8.0;
    float ndv = max(dot(n, v), 0.0);
    float ndl = max(dot(n, l), 0.0);
    return (ndv / (ndv * (1.0 - k) + k)) * (ndl / (ndl * (1.0 - k) + k));
}

vec3 fresnel_schlick(float cos_theta, vec3 f0) {
    return f0 + (1.0 - f0) * pow(1.0 - cos_theta, 5.0);
}

// The prefiltered cube's last mip. One mip per roughness band:
// ENV_PREFILTER_MIPS - 1, fixed at build time in env.goose.
const float ENV_MAX_LOD = 4.0;

// The split-sum BRDF term: the integral of the specular BRDF over the
// environment, fitted analytically (Karis' EnvBRDFApprox) instead of read from a
// precomputed table. Returns a scale and a bias for f0.
vec2 env_brdf(float rough, float ndv) {
    const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
    const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
    vec4 r = rough * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * ndv)) * r.x + r.y;
    return vec2(-1.04, 1.04) * a004 + r.zw;
}

// `radiance` is HiPGR's light colour: 1.0 on a white surface facing the light
// renders at 1.0. The division by PI that keeps the diffuse term energy
// conserving is undone here, so light colours are intensities an application can
// read off a colour picker rather than 1/PI of one.
vec3 direct(vec3 n, vec3 v, vec3 l, vec3 radiance, vec3 albedo, float metallic, float rough) {
    radiance *= PI;
    vec3 h = normalize(v + l);
    vec3 f0 = mix(vec3(0.04), albedo, metallic);
    vec3 f = fresnel_schlick(max(dot(h, v), 0.0), f0);
    float d = ndf_ggx(n, h, rough);
    float g = geometry_smith(n, v, l, rough);
    float ndl = max(dot(n, l), 0.0);
    float ndv = max(dot(n, v), 0.0);
    vec3 spec = (d * g * f) / max(4.0 * ndv * ndl, 1e-4);
    vec3 kd = (vec3(1.0) - f) * (1.0 - metallic);
    return (kd * albedo / PI + spec) * radiance * ndl;
}

// 1 where the fragment is lit, 0 where the shadow map says it is an occluder.
// Four hardware comparison taps: the sampler filters four depths at once, which
// is a 2x2 PCF kernel for the cost of one lookup each.
float shadow_factor(vec4 s) {
    if (fparams.x < 0.5) { return 1.0; }
    vec3 p = s.xyz / max(s.w, 1e-6);
    vec2 uv = vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    if (p.z > 1.0 || uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { return 1.0; }
    float ref = p.z - fparams.z;
    float t = fparams.y;
    float lit = texture(u_shadow, vec3(uv + vec2(-t, -t), ref));
    lit += texture(u_shadow, vec3(uv + vec2(t, -t), ref));
    lit += texture(u_shadow, vec3(uv + vec2(-t, t), ref));
    lit += texture(u_shadow, vec3(uv + vec2(t, t), ref));
    return lit * 0.25;
}

// A tangent frame from screen-space derivatives, so a normal map works without
// a tangent vertex attribute (and without extra vertex memory). The frame is
// built from the inverse of the screen-to-UV Jacobian, sign included: the
// determinant is negative whenever the winding and the screen's y axis disagree,
// and dropping that sign would rotate the normal map by 180 degrees.
mat3 cotangent_frame(vec3 n, vec3 p, vec2 uv) {
    vec3 dp1 = dFdx(p);
    vec3 dp2 = dFdy(p);
    vec2 duv1 = dFdx(uv);
    vec2 duv2 = dFdy(uv);
    float det = duv1.x * duv2.y - duv2.x * duv1.y;
    float sign = det < 0.0 ? -1.0 : 1.0;
    // dP/du and dP/dv, up to the (positive) determinant's magnitude.
    vec3 t = (dp1 * duv2.y - dp2 * duv2.x) * sign;
    vec3 b = (dp2 * duv1.x - dp1 * duv1.y) * sign;
    float invmax = inversesqrt(max(dot(t, t), dot(b, b)) + 1e-8);
    return mat3(t * invmax, b * invmax, n);
}

void main() {
    vec4 albedo = texture(u_albedo, v_uv) * tint;
    vec3 n = normalize(v_normal);
    float strength = clamp(params.w, 0.0, 4.0);
    if (strength > 0.0) {
        vec3 mapped = texture(u_normal_map, v_uv).xyz * 2.0 - 1.0;
        mapped.xy *= strength;
        n = normalize(cotangent_frame(n, v_world, v_uv) * mapped);
    }

    vec3 out_color;
    if (params.x > 0.5) {
        // Unlit: the material's own colour, untouched. Tests rely on this.
        out_color = albedo.rgb;
    } else {
        float metallic = clamp(params.y, 0.0, 1.0);
        float rough = clamp(params.z, 0.04, 1.0);
        // A shadowed surface is lit only by the ambient term.
        vec3 v = normalize(camera_pos.xyz - v_world);
        float shadow = shadow_factor(v_shadow);

        out_color = direct(n, v, -direction.xyz, color.rgb * shadow, albedo.rgb, metallic, rough);

        int count = int(color.w + 0.5);
        for (int i = 0; i < count; i++) {
            vec4 lp = points[i * 2];
            vec4 lc = points[i * 2 + 1];
            vec3 to_light = lp.xyz - v_world;
            float dist2 = max(dot(to_light, to_light), 1e-6);
            float att = max(1.0 - dist2 / (lp.w * lp.w), 0.0);
            att *= att;
            if (att > 0.0) {
                out_color += direct(n, v, to_light * inversesqrt(dist2), lc.rgb * att,
                                    albedo.rgb, metallic, rough);
            }
        }

        // Image-based lighting from the sky, split-sum: a cosine-weighted
        // irradiance cube for the diffuse half, a radiance cube prefiltered per
        // roughness band for the specular half. Specular is not occluded, so a
        // shadowed metal still reflects the sky, as it should.
        vec3 f0 = mix(vec3(0.04), albedo.rgb, metallic);
        if (fparams.w > 0.0) {
            vec3 diffuse_ibl = texture(u_irradiance, n).rgb * albedo.rgb * (1.0 - metallic);
            vec3 radiance = textureLod(u_prefiltered, reflect(-v, n), rough * ENV_MAX_LOD).rgb;
            vec2 brdf = env_brdf(rough, max(dot(n, v), 0.0));
            out_color += (diffuse_ibl + radiance * (f0 * brdf.x + brdf.y)) * fparams.w;
        } else {
            // 0.2's constant ambient: what a device with IBL off still renders.
            out_color += (albedo.rgb * (1.0 - metallic) + f0 * 0.5) * direction.w;
        }
    }

    out_color += emissive.rgb;

    // Distance fog towards the horizon colour.
    float dist = length(camera_pos.xyz - v_world);
    float fog = 1.0 - exp(-dist * sky.w);
    out_color = mix(out_color, sky.rgb, clamp(fog, 0.0, 1.0));

    result = vec4(out_color, albedo.a);
}
