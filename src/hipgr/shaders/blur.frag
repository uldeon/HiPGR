// Bloom, step two: one direction of a separable Gaussian. Two passes, one
// horizontal and one vertical, give the same result as a 5x5 kernel for a fifth
// of the taps.
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 result;

layout(set = 2, binding = 0) uniform sampler2D u_source;

// texel: x/y are one texel of this target, z is 1 for the horizontal pass.
layout(set = 3, binding = 0) uniform Post { vec4 params; vec4 texel; };

void main() {
    vec2 step = vec2(texel.x * texel.z, texel.y * (1.0 - texel.z));
    vec3 c = texture(u_source, v_uv).rgb * 0.375;
    c += (texture(u_source, v_uv + step).rgb + texture(u_source, v_uv - step).rgb) * 0.25;
    c += (texture(u_source, v_uv + step * 2.0).rgb +
          texture(u_source, v_uv - step * 2.0).rgb) * 0.0625;
    result = vec4(c, 1.0);
}
