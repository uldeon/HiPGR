// A custom fragment shader with two samplers of its own, at fragment set 2
// bindings 0 and 1 — the order HiPGR binds the material's texture slots in. It
// multiplies one by the red of the other, so a test can tell the slots apart and
// can see the white 1x1 that an unset slot is bound to.
layout(set = 2, binding = 0) uniform sampler2D u_a;
layout(set = 2, binding = 1) uniform sampler2D u_b;
layout(set = 3, binding = 0) uniform Material { vec4 tint; vec4 params; vec4 user0; vec4 user1; vec4 v[8]; };

layout(location = 1) in vec2 v_uv;

layout(location = 0) out vec4 result;

void main() {
    result = vec4(texture(u_a, v_uv).rgb * texture(u_b, v_uv).r, 1.0);
}
