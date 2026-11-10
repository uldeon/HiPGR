// HiPGR: matrix math for applications.
//
// Applications never touch the graphics backend, so they never see its matrix
// type. Mat4 is the renderer's own column-major 4x4 matrix; the arithmetic is
// delegated to the backend's math helpers today, and the layout (four float4
// columns, std140 compatible) is what uniforms and shaders expect.
namespace hipgr;

import vec;
import math;
import gfx;

struct Mat4 { m: gfx::mat4 }

fn mat4_identity() -> Mat4 { Mat4 { m: gfx::mat4_identity } }

fn mat4_mul(a: Mat4, b: Mat4) -> Mat4 { Mat4 { m: gfx::mul(a.m, b.m) } }

fn mat4_translate(t: float3) -> Mat4 { Mat4 { m: gfx::translate(t) } }

fn mat4_scale(s: float3) -> Mat4 { Mat4 { m: gfx::scale(s) } }

// The four columns of a matrix, for tests and diagnostics.
fn mat4_column(m: Mat4, i: i64) -> float4 {
    match i {
        0 => m.m.c0,
        1 => m.m.c1,
        2 => m.m.c2,
        _ => m.m.c3,
    }
}

fn mat4_mul_vec4(m: Mat4, v: float4) -> float4 { gfx::mul(m.m, v) }

// A point through a matrix, without the perspective divide.
fn mat4_point(m: Mat4, p: float3) -> float3 {
    let r = gfx::mul(m.m, float4 { p.x, p.y, p.z, 1.0 });
    float3 { r.x, r.y, r.z }
}

fn mat4_rotate(axis: float3, angle: f32) -> Mat4 { Mat4 { m: gfx::rotate(axis, angle) } }

// Translate * Rotate(axis, angle) * Scale, the usual object transform.
fn mat4_trs(t: float3, axis: float3, angle: f32, s: float3) -> Mat4 {
    mat4_mul(mat4_mul(mat4_translate(t), mat4_rotate(axis, angle)), mat4_scale(s))
}

// A transform that only spins about Y, the common case for demos.
fn mat4_spin(center: float3, yaw: f32, scale: f32) -> Mat4 {
    mat4_trs(center, float3 { 0.0, 1.0, 0.0 }, yaw, float3 { scale, scale, scale })
}

// Right-handed view matrix: the camera sits at eye, looking at target.
fn mat4_look_at(eye: float3, target: float3, up: float3) -> Mat4 {
    Mat4 { m: gfx::look_at(eye, target, up) }
}

// Perspective projection to clip depth 0..1, fov_y in radians.
fn mat4_perspective(fov_y: f32, aspect: f32, near: f32, far: f32) -> Mat4 {
    Mat4 { m: gfx::perspective(fov_y, aspect, near, far) }
}

fn mat4_ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) -> Mat4 {
    Mat4 { m: gfx::ortho(left, right, bottom, top, near, far) }
}

// The matrix that transforms normals for a model matrix: the inverse
// transpose of its upper 3x3.
//
// Normals are not directions between points, so a matrix with a non-uniform
// scale skews them when applied directly (a tall box would shade as if it were
// tilted). The inverse transpose undoes that. Translation is dropped, and a
// singular model matrix (a zero scale) falls back to identity rather than to
// NaNs: geometry scaled to nothing is invisible anyway.
fn mat4_normal(m: Mat4) -> Mat4 {
    let c0 = m.m.c0;
    let c1 = m.m.c1;
    let c2 = m.m.c2;
    let a = float3 { c0.x, c0.y, c0.z };
    let b = float3 { c1.x, c1.y, c1.z };
    let c = float3 { c2.x, c2.y, c2.z };
    let det = dot(a, cross(b, c));
    if abs(det) < 0.0000001 { return mat4_identity(); }
    let d = float3 { det, det, det };
    // The columns of the inverse are the cofactors over the determinant; the
    // transpose then swaps them into rows.
    let i0 = cross(b, c) / d;
    let i1 = cross(c, a) / d;
    let i2 = cross(a, b) / d;
    var out = mat4_identity();
    out.m.c0 = float4 { i0.x, i1.x, i2.x, 0.0 };
    out.m.c1 = float4 { i0.y, i1.y, i2.y, 0.0 };
    out.m.c2 = float4 { i0.z, i1.z, i2.z, 0.0 };
    out.m.c3 = float4 { 0.0, 0.0, 0.0, 1.0 };
    return out;
}
