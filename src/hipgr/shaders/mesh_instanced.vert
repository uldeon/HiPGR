// HiPGR built-in vertex shader, instanced: the same shading as mesh.vert, with
// the two per-object matrices read per instance from vertex buffer 1 instead of
// from a uniform block, so one draw call can carry many objects.
//
// The backend derives the instance layout from the declarations below, in
// location order: locations 3..10, eight vec4s, 128 bytes per instance. The
// matrix is the model matrix and `normal` is its inverse transpose, exactly what
// Draw holds for a non-instanced draw, so both paths do the same arithmetic.
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;
layout(location = 3) in vec4 a_model0;
layout(location = 4) in vec4 a_model1;
layout(location = 5) in vec4 a_model2;
layout(location = 6) in vec4 a_model3;
layout(location = 7) in vec4 a_normal0;
layout(location = 8) in vec4 a_normal1;
layout(location = 9) in vec4 a_normal2;
layout(location = 10) in vec4 a_normal3;

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

layout(location = 0) out vec3 v_normal;
layout(location = 1) out vec2 v_uv;
layout(location = 2) out vec3 v_world;
layout(location = 3) out vec4 v_shadow;

void main() {
    mat4 model = mat4(a_model0, a_model1, a_model2, a_model3);
    mat4 normal = mat4(a_normal0, a_normal1, a_normal2, a_normal3);
    vec4 world = model * vec4(a_pos, 1.0);
    v_normal = (normal * vec4(a_normal, 0.0)).xyz;
    v_uv = a_uv;
    v_world = world.xyz;
    v_shadow = light_view_proj * world;
    gl_Position = view_proj * world;
}
