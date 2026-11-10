// A custom fragment shader: it ignores lighting and outputs the material's own
// data, so a test can prove that Material.user0 reaches application shaders
// unchanged. The blocks are declared in HiPGR's documented layout.
layout(set = 3, binding = 0) uniform Material { vec4 tint; vec4 params; vec4 user0; vec4 user1; };
layout(set = 3, binding = 1) uniform Light { vec4 direction; vec4 color; vec4 points[16]; };

layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec2 v_uv;
layout(location = 2) in vec3 v_world;

layout(location = 0) out vec4 result;

void main() {
    // user1 unused: declared to prove the layout is readable as documented.
    result = vec4(user0.rgb, user1.a + 1.0);
}
