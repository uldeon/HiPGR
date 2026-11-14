// A custom fragment shader that receives the scene's shadows, using nothing but
// documented blocks: the shadow map as a sampler2DShadow at fragment set 2, and
// Frame at set 3 for the light matrix, the texel size and the bias. It outputs
// white where the surface is lit and black where it is shadowed, so a test can
// count both.
//
// The blocks are positional: HiPGR pushes Material, Light then Frame, and the
// backend requires consecutive bindings from 0, so a shader that reads Frame
// declares Light first even when it ignores it.
layout(set = 2, binding = 0) uniform sampler2DShadow u_shadow;
layout(set = 3, binding = 0) uniform Material { vec4 tint; vec4 params; vec4 user0; vec4 user1; vec4 v[8]; };
layout(set = 3, binding = 1) uniform Light { vec4 direction; vec4 color; vec4 points[16]; };
layout(set = 3, binding = 2) uniform Frame {
    mat4 view_proj;
    mat4 light_view_proj;
    mat4 light_view_proj_far;
    vec4 cascades;
    vec4 camera_pos;
    vec4 sky;
    vec4 fparams;           // x shadows on, y shadow texel, z shadow bias, w IBL strength
    vec4 cam_right;
    vec4 cam_up;
    vec4 cam_forward;
};

layout(location = 2) in vec3 v_world;

layout(location = 0) out vec4 result;

void main() {
    if (fparams.x < 0.5) { result = vec4(1.0); return; }
    vec4 s = light_view_proj * vec4(v_world, 1.0);
    vec3 p = s.xyz / max(s.w, 1e-6);
    vec2 uv = vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    if (p.z > 1.0 || uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        result = vec4(1.0);
        return;
    }
    float t = fparams.y;
    float ref = p.z - fparams.z;
    float lit = texture(u_shadow, vec3(uv + vec2(-t, -t), ref));
    lit += texture(u_shadow, vec3(uv + vec2(t, -t), ref));
    lit += texture(u_shadow, vec3(uv + vec2(-t, t), ref));
    lit += texture(u_shadow, vec3(uv + vec2(t, t), ref));
    result = vec4(vec3(lit * 0.25), 1.0);
}
