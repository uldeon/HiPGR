// A custom fragment shader: no lighting, just stripes from the UVs, with both
// colours coming from the material's own data. Its whole point is that HiPGR
// never has to know what it does.
// Material is 192 bytes from 0.6: v[8] is the application's own data, unused here
// but declared because the block's size is part of the contract.
layout(set = 3, binding = 0) uniform Material { vec4 tint; vec4 params; vec4 user0; vec4 user1; vec4 v[8]; };
layout(set = 3, binding = 1) uniform Light { vec4 direction; vec4 color; vec4 points[16]; };

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec2 v_uv;
layout(location = 2) in vec3 v_world;

layout(location = 0) out vec4 result;

void main() {
    // user0 and user1: the two stripe colours, chosen by the application.
    float stripe = step(0.5, fract(v_uv.x * 5.0));
    float edge = step(0.04, min(v_uv.x, min(v_uv.y, min(1.0 - v_uv.x, 1.0 - v_uv.y))));
    vec3 c = mix(user0.rgb, user1.rgb, stripe) * (0.75 + 0.25 * edge);
    result = vec4(c, 1.0);
}
