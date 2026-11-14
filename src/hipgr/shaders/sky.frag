// The sky: a cube map sampled along the view ray through each pixel. Drawn
// before the scene, with no depth test, so it fills whatever the scene leaves.
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 result;

layout(set = 2, binding = 0) uniform samplerCube u_sky;

// The same 304-byte Frame as the mesh shaders; the sky reads only the camera
// basis, but the block's size is part of the contract.
layout(set = 3, binding = 0) uniform Frame {
    mat4 view_proj;
    mat4 light_view_proj;
    mat4 light_view_proj_far;
    vec4 cascades;
    vec4 camera_pos;
    vec4 sky;
    vec4 params;
    vec4 cam_right;         // scaled by tan(fov / 2) * aspect
    vec4 cam_up;            // scaled by tan(fov / 2)
    vec4 cam_forward;
};

void main() {
    vec2 ndc = vec2(v_uv.x * 2.0 - 1.0, 1.0 - v_uv.y * 2.0);
    vec3 dir = normalize(cam_forward.xyz + ndc.x * cam_right.xyz + ndc.y * cam_up.xyz);
    result = vec4(texture(u_sky, dir).rgb, 1.0);
}
