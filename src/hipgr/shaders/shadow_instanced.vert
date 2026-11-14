// The depth pass from the light, instanced: the same geometry as shadow.vert,
// with the model matrix read per instance from vertex buffer 1 instead of from
// the Draw block, so one draw call can carry many casters.
//
// Only the model matrix is per instance (locations 3..6, four vec4s, 64 bytes):
// a depth pass has no use for the normal, and the stride is the shader's, so a
// shadow batch costs half the instance bandwidth of a shaded one.
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;
layout(location = 3) in vec4 a_model0;
layout(location = 4) in vec4 a_model1;
layout(location = 5) in vec4 a_model2;
layout(location = 6) in vec4 a_model3;

layout(set = 1, binding = 0) uniform Frame {
    mat4 view_proj;
    mat4 light_view_proj;
    vec4 camera_pos;
    vec4 sky;
    vec4 params;            // z: shadow bias
    vec4 cam_right;
    vec4 cam_up;
    vec4 cam_forward;
};

void main() {
    mat4 model = mat4(a_model0, a_model1, a_model2, a_model3);
    gl_Position = light_view_proj * model * vec4(a_pos, 1.0);
}
