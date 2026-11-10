// HiPGR built-in solid fragment shader: tint only, no texture, no sampler.
// Same blocks as the textured shader so one renderer path serves both.
layout(set = 3, binding = 0) uniform Material { vec4 tint; vec4 params; };
layout(set = 3, binding = 1) uniform Light { vec4 direction; vec4 color; };

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec2 v_uv;

layout(location = 0) out vec4 result;

void main() {
    float ndl = max(dot(normalize(v_normal), normalize(-direction.xyz)), 0.0);
    float shade = color.w + (1.0 - color.w) * ndl;
    if (params.x > 0.5) { shade = 1.0; }
    result = vec4(tint.rgb * color.rgb * shade, tint.a);
}
