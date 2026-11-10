// The vertex side of the demo's custom material, written against HiPGR's
// documented contract: the Vertex layout in, Frame and Draw blocks, and a world
// position out for anything that needs one.
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
