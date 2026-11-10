// HiPGR built-in textured fragment shader: albedo texture * tint, lit by one
// directional light. Set 2 is samplers, set 3 fragment uniform blocks.
layout(set = 2, binding = 0) uniform sampler2D u_albedo;

// params.x: 1 = unlit.
layout(set = 3, binding = 0) uniform Material { vec4 tint; vec4 params; };
// direction.xyz: the direction the light travels in; color.w: ambient.
layout(set = 3, binding = 1) uniform Light { vec4 direction; vec4 color; };

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec2 v_uv;

layout(location = 0) out vec4 result;

void main() {
    vec4 albedo = texture(u_albedo, v_uv) * tint;
    float ndl = max(dot(normalize(v_normal), normalize(-direction.xyz)), 0.0);
    float shade = color.w + (1.0 - color.w) * ndl;
    if (params.x > 0.5) { shade = 1.0; }
    result = vec4(albedo.rgb * color.rgb * shade, albedo.a);
}
