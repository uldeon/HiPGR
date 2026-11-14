// A custom fragment shader that reads the application's own data, so a test can
// prove the eight float4s reach a shader unchanged. They live in the Material
// block as Material.v, which is the layout HiPGR documents.
layout(set = 3, binding = 0) uniform Material { vec4 tint; vec4 params; vec4 user0; vec4 user1; vec4 v[8]; };

layout(location = 2) in vec3 v_world;

layout(location = 0) out vec4 result;

void main() {
    // v[0].x selects between the colour in v[3] and the one in v[4], so one
    // shader proves three slots and that they are independent.
    result = vec4(mix(v[3].rgb, v[4].rgb, v[0].x), 1.0);
}
