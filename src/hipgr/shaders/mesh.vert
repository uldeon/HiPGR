// HiPGR built-in vertex shader: one packed vertex, a frame block and a draw
// block. Set 1 is where the backend puts vertex uniform blocks.
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;

layout(set = 1, binding = 0) uniform Frame { mat4 view_proj; };
layout(set = 1, binding = 1) uniform Draw { mat4 model; };

layout(location = 0) out vec3 v_normal;
layout(location = 1) out vec2 v_uv;

void main() {
    // Rotated with the model matrix. A non-uniform scale would need the
    // inverse transpose (0.2); uniform scale and rotation are exact.
    v_normal = (model * vec4(a_normal, 0.0)).xyz;
    v_uv = a_uv;
    gl_Position = view_proj * model * vec4(a_pos, 1.0);
}
