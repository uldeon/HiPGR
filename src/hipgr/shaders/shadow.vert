// The depth pass from the light: the same geometry, seen through the light's
// view-projection instead of the camera's. Geometry only — the material is
// irrelevant, so any mesh can cast a shadow whatever it is shaded with.
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;

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
layout(set = 1, binding = 1) uniform Draw { mat4 model; mat4 normal; };

void main() {
    // No normal offset here: a vertex pushed towards the light would also push
    // the surface that receives its own shadow, which makes every lit surface
    // its own occluder. The bias is applied once, in the fragment shader, when
    // the shadow map is read.
    gl_Position = light_view_proj * model * vec4(a_pos, 1.0);
}
