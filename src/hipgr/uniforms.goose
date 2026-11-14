// HiPGR: the uniform blocks.
//
// One definition per block, used by the renderer, the post chain and every
// built-in shader. The bytes are std140 and the backend checks each block's
// size against the shader's, so a change here must change the shaders in
// shaders/ in exactly the same way.
//
//   set 1 binding 0  Frame     304 bytes  (vertex)
//   set 1 binding 1  Draw      128        (vertex)
//   set 3 binding 0  Material  192        (fragment)
//   set 3 binding 1  Light     288        (fragment)
//   set 3 binding 2  Frame     224        (fragment: fog, shadow parameters)
//   set 3 binding 3  Surface    16        (fragment, built-in material only)
//   set 3 binding 0  Post       32        (fragment, post and sky pipelines)
namespace hipgr;

import vec;
import .device;
import .camera;
import .math;

// Perspective camera basis, scaled so a screen ray is
// `forward + ndc.x * right + ndc.y * up`.
struct FrameUniform {
    view_proj: Mat4,         // 64
    light_view_proj: Mat4,   // 64: world -> the near shadow map's clip space
    light_view_proj_far: Mat4, // 64: the same for the far cascade
    // x: 1 when the shadow maps follow the camera (two cascades), 0 for one box;
    // y: the view depth where the near cascade ends, in world units; z: where
    // the far one ends; w: unused.
    cascades: float4,        // 16
    camera_pos: float4,      // 16: xyz eye, w exposure
    sky: float4,             // 16: rgb sky colour for fog, w fog density
    params: float4,          // 16: x shadows on, y shadow texel, z shadow bias, w IBL strength
    cam_right: float4,       // 16
    cam_up: float4,          // 16
    cam_forward: float4,     // 16
}

struct DrawUniform { model: Mat4, normal: Mat4 }   // 128

// params: x unlit, y metallic, z roughness, w normal-map strength.
// v: the application's eight float4s, in declaration order.
//
// The block was 64 bytes through 0.5 and is 192 from 0.6, which is why 0.6 is a
// minor version with a migration note: a custom shader that declares the old
// four vectors has the wrong size, and the backend rejects the push with a
// message naming both sizes rather than shading with garbage.
struct MaterialUniform {
    tint: float4,
    params: float4,
    user0: float4,
    user1: float4,
    v: float4[8] = [float4_0; 8],
}

// Emissive colour, in its own block so Material keeps to shading state. Only the
// built-in shader declares it, and only built-in materials push it.
struct SurfaceUniform { emissive: float4 }

// direction.xyz: the direction the directional light travels in, w: ambient.
// color.rgb: its colour, w: point light count.
// points: per light, (position, radius) then (colour, 0).
struct LightUniform { direction: float4, color: float4, points: float4[16] }

// params: x exposure, y bloom strength, z tone-map mode (0 none, 1 Reinhard,
// 2 ACES), w bloom threshold. texel: x/y one texel of the sampled target, z 1
// when the blur runs horizontally, w unused.
struct PostUniform { params: float4, texel: float4 }

// An orthographic box of half-extent `r` around `center`, looking down `dir`.
// The up vector is chosen so a vertical light still has a usable one.
fn shadow_box_view_projection(center: float3, r: f32, dir: float3) -> Mat4 {
    let radius = if r > 0.1 { r } else { 0.1 };
    let eye = center - dir * (radius * 2.0);
    let up = if abs(dir.y) > 0.99 { float3 { 0.0, 0.0, 1.0 } } else { float3 { 0.0, 1.0, 0.0 } };
    let view = mat4_look_at(eye, center, up);
    let proj = mat4_ortho(-radius, radius, -radius, radius, 0.05, radius * 4.0 + 0.1);
    return mat4_mul(proj, view);
}

// The light's view-projection in single-box mode.
fn light_view_projection(d: Device&) -> Mat4 {
    return shadow_box_view_projection(d.shadow_center, d.shadow_radius, d.light_direction);
}

// The sphere that contains every point of the camera frustum out to `depth`.
// A cascade box and its culling test are built from it, so nothing a camera can
// see out to that depth is outside the map.
fn cascade_sphere(cam: Camera, aspect: f32, depth: f32) -> float3, f32 {
    let basis = camera_basis(cam, aspect);
    let tan_y = tan(cam.fov_y * 0.5);
    let half = depth * 0.5;
    let h = depth * tan_y;
    let w = h * aspect;
    let radius = sqrt(half * half + w * w + h * h);
    let center = cam.eye + basis.forward * half;
    return center, radius;
}

fn cascade_view_projection(d: Device&, cam: Camera, aspect: f32, depth: f32) -> Mat4 {
    let center, radius = cascade_sphere(cam, aspect, depth);
    return shadow_box_view_projection(center, radius, d.light_direction);
}

fn frame_uniform(d: Device&, cam: Camera, aspect: f32) -> FrameUniform {
    let vp = camera_view_projection(cam, aspect);
    let basis = camera_basis(cam, aspect);
    // Single-box mode leaves the far matrix equal to the near one and the flag
    // off, so the shader has one code path to compile and none to take.
    var near_vp = light_view_projection(d);
    var far_vp = near_vp;
    var cascades = float4 { 0.0, 0.0, 0.0, 0.0 };
    if d.shadow_mode == SHADOW_CASCADES {
        near_vp = cascade_view_projection(d, cam, aspect, d.shadow_near);
        far_vp = cascade_view_projection(d, cam, aspect, d.shadow_far);
        cascades = float4 { 1.0, d.shadow_near, d.shadow_far, 0.0 };
    }
    return FrameUniform {
        view_proj: vp,
        light_view_proj: near_vp,
        light_view_proj_far: far_vp,
        cascades: cascades,
        camera_pos: float4 { cam.eye.x, cam.eye.y, cam.eye.z, d.exposure },
        sky: float4 { d.sky_horizon.x, d.sky_horizon.y, d.sky_horizon.z, d.fog_density },
        params: float4 { if d.shadows { 1.0 } else { 0.0 }, 1.0 / 1024.0, d.shadow_bias, d.ibl },
        cam_right: float4 { basis.right.x, basis.right.y, basis.right.z, 0.0 },
        cam_up: float4 { basis.up.x, basis.up.y, basis.up.z, 0.0 },
        cam_forward: float4 { basis.forward.x, basis.forward.y, basis.forward.z, 0.0 },
    };
}

fn light_uniform(d: Device&) -> LightUniform {
    var points: float4[16] = [float4 { 0.0, 0.0, 0.0, 0.0 }; 16];
    let n = if d.lights.len > MAX_POINT_LIGHTS { MAX_POINT_LIGHTS } else { d.lights.len };
    for i in n {
        let l = d.lights[i];
        points[i * 2] = float4 { l.position.x, l.position.y, l.position.z, l.radius };
        points[i * 2 + 1] = float4 { l.color.x, l.color.y, l.color.z, 0.0 };
    }
    return LightUniform {
        direction: float4 { d.light_direction.x, d.light_direction.y, d.light_direction.z,
                            d.ambient },
        color: float4 { d.light_color.x, d.light_color.y, d.light_color.z, n },
        points: points,
    };
}

fn material_uniform(metallic: f32, roughness: f32, normal_strength: f32, unlit: bool,
                    tint: float4, user0: float4, user1: float4,
                    v: const float4[:]) -> MaterialUniform {
    var out = MaterialUniform {
        tint: tint,
        params: float4 { if unlit { 1.0 } else { 0.0 }, metallic, roughness, normal_strength },
        user0: user0,
        user1: user1,
    };
    var i = 0;
    while i < 8 {
        if i < v.len { out.v[i] = v[i]; }
        i++;
    }
    return out;
}

fn surface_uniform(emissive: float4) -> SurfaceUniform {
    return SurfaceUniform { emissive: emissive };
}

fn post_uniform(d: Device&, target_w: i64, target_h: i64, horizontal: bool) -> PostUniform {
    let tw = if target_w > 0 { 1.0 / target_w } else { 0.0 };
    let th = if target_h > 0 { 1.0 / target_h } else { 0.0 };
    return PostUniform {
        params: float4 { d.exposure, d.bloom_strength, d.tonemap, d.bloom_threshold },
        texel: float4 { tw, th, if horizontal { 1.0 } else { 0.0 }, 0.0 },
    };
}
