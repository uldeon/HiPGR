// HiPGR: cameras.
//
// A camera is plain data: where it is, what it looks at, and how it projects.
// Applications own the camera and move it; HiPGR only turns it into the
// matrices a frame needs. Right-handed, looking down -Z, clip depth 0..1.
namespace hipgr;

import vec;
import math;
import .math;

struct Camera {
    eye: float3 = float3 { 0.0, 0.0, 3.0 },
    target: float3 = float3 { 0.0, 0.0, 0.0 },
    up: float3 = float3 { 0.0, 1.0, 0.0 },
    fov_y: f32 = 0.8,
    near: f32 = 0.1,
    far: f32 = 100.0,
    orthographic: bool = false,
    ortho_height: f32 = 10.0,
}

fn camera_look_at(eye: float3, target: float3, up: float3, fov_y: f32) -> Camera {
    Camera { eye: eye, target: target, up: up, fov_y: fov_y }
}

fn camera_perspective(eye: float3, target: float3, up: float3, fov_y: f32, near: f32,
                      far: f32) -> Camera {
    Camera { eye: eye, target: target, up: up, fov_y: fov_y, near: near, far: far }
}

fn camera_orthographic(eye: float3, target: float3, up: float3, height: f32, near: f32,
                       far: f32) -> Camera {
    Camera { eye: eye, target: target, up: up, near: near, far: far, orthographic: true,
             ortho_height: height }
}

// The direction a first-person camera looks in, from yaw about Y and pitch.
// Yaw 0 looks down -Z; positive yaw turns right, positive pitch looks up.
fn camera_direction(yaw: f32, pitch: f32) -> float3 {
    let cp = cos(pitch);
    return float3 { sin(yaw) * cp, sin(pitch), -cos(yaw) * cp };
}

fn camera_fps(eye: float3, yaw: f32, pitch: f32, fov_y: f32) -> Camera {
    let dir = camera_direction(yaw, pitch);
    return camera_look_at(eye, eye + dir, float3 { 0.0, 1.0, 0.0 }, fov_y);
}

fn camera_view(c: Camera) -> Mat4 {
    mat4_look_at(c.eye, c.target, c.up)
}

fn camera_projection(c: Camera, aspect: f32) -> Mat4 {
    let a = if aspect > 0.0 { aspect } else { 1.0 };
    let n = if c.near > 0.0 { c.near } else { 0.1 };
    let f = if c.far > n { c.far } else { n + 1.0 };
    if c.orthographic {
        let h = if c.ortho_height > 0.0 { c.ortho_height } else { 1.0 };
        let w = h * a;
        return mat4_ortho(-w * 0.5, w * 0.5, -h * 0.5, h * 0.5, n, f);
    }
    return mat4_perspective(c.fov_y, a, n, f);
}

fn camera_view_projection(c: Camera, aspect: f32) -> Mat4 {
    mat4_mul(camera_projection(c, aspect), camera_view(c))
}
