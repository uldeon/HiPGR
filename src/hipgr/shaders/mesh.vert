// HiPGR built-in vertex shader: one packed vertex, the frame block and the draw
// block. Set 1 is where the backend puts vertex uniform blocks.
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;

// 224 bytes: two matrices, then the camera, sky and shadow parameters and the
// camera basis. shaders/mesh.frag declares the same block at set 3.
layout(set = 1, binding = 0) uniform Frame {
    mat4 view_proj;
    mat4 light_view_proj;
    vec4 camera_pos;        // xyz eye, w exposure
    vec4 sky;               // rgb horizon colour, w fog density
    vec4 params;            // x shadows on, y shadow texel, z shadow bias, w sky on
    vec4 cam_right;
    vec4 cam_up;
    vec4 cam_forward;
};
// normal is the inverse transpose of model's upper 3x3, so normals survive a
// non-uniform scale.
layout(set = 1, binding = 1) uniform Draw { mat4 model; mat4 normal; };

layout(location = 0) out vec3 v_normal;
layout(location = 1) out vec2 v_uv;
layout(location = 2) out vec3 v_world;
// World position in the shadow map's clip space, interpolated and divided in
// the fragment shader.
layout(location = 3) out vec4 v_shadow;

void main() {
    vec4 world = model * vec4(a_pos, 1.0);
    v_normal = (normal * vec4(a_normal, 0.0)).xyz;
    v_uv = a_uv;
    v_world = world.xyz;
    v_shadow = light_view_proj * world;
    gl_Position = view_proj * world;
}
