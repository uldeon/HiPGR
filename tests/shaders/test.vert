// The vertex shader contract, written out independently of HiPGR's own copy:
// whatever an application embeds must see the same inputs and blocks.
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;

layout(set = 1, binding = 0) uniform Frame { mat4 view_proj; };
layout(set = 1, binding = 1) uniform Draw { mat4 model; mat4 normal; };

layout(location = 0) out vec3 v_normal;
layout(location = 1) out vec2 v_uv;
layout(location = 2) out vec3 v_world;

void main() {
    vec4 world = model * vec4(a_pos, 1.0);
    v_normal = (normal * vec4(a_normal, 0.0)).xyz;
    v_uv = a_uv;
    v_world = world.xyz;
    gl_Position = view_proj * world;
}
