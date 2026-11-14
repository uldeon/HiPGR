// HiPGR: the frame's draw order.
//
// draw() appends renderables in submission order; end_frame() turns that list
// into a plan before any pass runs:
//
//   cull        objects entirely outside the camera frustum are skipped
//   order       opaque first, then transparent back to front
//   batch       runs of one geometry and one material become one instanced draw
//
// All three are switches on the device, and all three are allowed to change the
// cost of a frame but not its pixels: tests/test_culling and tests/test_batching
// render the same scene with them on and off and compare the images.
//
// The shadow pass is not culled: an object off screen can still cast a shadow
// into view, and the shadow map has no camera frustum to test against.
namespace hipgr;

import std;
import vec;
import math;
import .state;
import .device;
import .mesh;
import .material;
import .gpu;
import .uniforms;

// A frustum plane, as dot(normal, p) + d >= 0 for a point inside. The planes
// come out of the view-projection scaled rather than unit length, which does not
// matter: a point's distance and a box's radius are scaled by the same factor.
struct Plane {
    normal: float3 = float3 { 0.0, 0.0, 0.0 },
    d: f32 = 0.0,
}

struct Frustum {
    planes: Plane[6] = [Plane {}; 6],
}

fn plane_from(coefficients: float4) -> Plane {
    return Plane { normal: float3 { coefficients.x, coefficients.y, coefficients.z },
                   d: coefficients.w };
}

// One row of a column-major matrix, which is what the plane extraction needs.
fn matrix_row(m: Mat4, i: i64) -> float4 {
    let c0 = m.m.c0;
    let c1 = m.m.c1;
    let c2 = m.m.c2;
    let c3 = m.m.c3;
    match i {
        0 => float4 { c0.x, c1.x, c2.x, c3.x },
        1 => float4 { c0.y, c1.y, c2.y, c3.y },
        2 => float4 { c0.z, c1.z, c2.z, c3.z },
        _ => float4 { c0.w, c1.w, c2.w, c3.w },
    }
}

// The six planes of a clip-space box, from the rows of the view-projection:
// the row combination that a clip-space inequality turns into is row3 plus or
// minus each other row. Depth is 0..1 here, so the near plane is z >= 0 rather
// than z >= -w.
fn frustum_from(view_proj: Mat4) -> Frustum {
    let r0 = matrix_row(view_proj, 0);
    let r1 = matrix_row(view_proj, 1);
    let r2 = matrix_row(view_proj, 2);
    let r3 = matrix_row(view_proj, 3);
    var f = Frustum {};
    f.planes[0] = plane_from(r3 + r0);      // left:   x >= -w
    f.planes[1] = plane_from(r3 - r0);      // right:  x <=  w
    f.planes[2] = plane_from(r3 + r1);      // bottom
    f.planes[3] = plane_from(r3 - r1);      // top
    f.planes[4] = plane_from(r2);           // near:   z >= 0
    f.planes[5] = plane_from(r3 - r2);      // far
    return f;
}

// A box's world-space bounds: the model matrix applied to the eight corners of
// its local box. Conservative, which is the point: a box that straddles the
// frustum must never be culled, so the test runs on the axis-aligned bound of
// the transformed corners rather than on the corners themselves.
fn world_bounds(b: Bounds, model: Mat4) -> Bounds {
    var lo = float3 { 0.0, 0.0, 0.0 };
    var hi = float3 { 0.0, 0.0, 0.0 };
    for k in 8 {
        let corner = float3 {
            if k % 2 == 0 { b.min.x } else { b.max.x },
            if k % 4 < 2 { b.min.y } else { b.max.y },
            if k < 4 { b.min.z } else { b.max.z },
        };
        let w = mat4_point(model, corner);
        if k == 0 {
            lo = w;
            hi = w;
        } else {
            if w.x < lo.x { lo.x = w.x; }
            if w.y < lo.y { lo.y = w.y; }
            if w.z < lo.z { lo.z = w.z; }
            if w.x > hi.x { hi.x = w.x; }
            if w.y > hi.y { hi.y = w.y; }
            if w.z > hi.z { hi.z = w.z; }
        }
    }
    return Bounds { min: lo, max: hi };
}

fn center_of(b: Bounds) -> float3 {
    return (b.min + b.max) * float3 { 0.5, 0.5, 0.5 };
}

fn half_extent_of(b: Bounds) -> float3 {
    return (b.max - b.min) * float3 { 0.5, 0.5, 0.5 };
}

// True when the box is entirely on the outside of at least one plane, which is
// the only case in which it can be skipped. The corner farthest along the
// plane's normal decides: if even that one is outside, they all are.
fn frustum_excludes(f: Frustum, center: float3, half_extent: float3) -> bool {
    let e = float3 {
        if half_extent.x < 0.0 { -half_extent.x } else { half_extent.x },
        if half_extent.y < 0.0 { -half_extent.y } else { half_extent.y },
        if half_extent.z < 0.0 { -half_extent.z } else { half_extent.z },
    };
    for i in 6 {
        let p = f.planes[i];
        let n = p.normal;
        let distance = dot(n, center) + p.d;
        let radius = (if n.x < 0.0 { -n.x } else { n.x }) * e.x
                   + (if n.y < 0.0 { -n.y } else { n.y }) * e.y
                   + (if n.z < 0.0 { -n.z } else { n.z }) * e.z;
        if distance + radius < 0.0 { return true; }
    }
    return false;
}

// --- the plan ------------------------------------------------------------------

// Culls, orders and batches the recorded items into d.plan and d.batches, and
// fills the per-frame instance buffer. Runs before the shadow pass, because the
// batches have to exist before anything is drawn, but the plan itself is the
// scene pass's.
fn build_plan(d: Device&, view_proj: Mat4) -> bool {
    d.plan.clear();
    d.batches.clear();
    d.instances.clear();

    let frustum = frustum_from(view_proj);
    let eye = d.camera.eye;
    for i in d.items.len {
        let item = d.items[i];
        let mi = mesh_index(d, item.mesh);
        let ai = material_index(d, item.material);
        if mi < 0 || ai < 0 { continue; }
        let b = world_bounds(d.meshes[mi].bounds, item.model);
        // A degenerate mesh (one vertex) still has a box, and a box of zero size
        // is still tested exactly.
        if d.culling && frustum_excludes(frustum, center_of(b), half_extent_of(b)) {
            d.stats.culled++;
            continue;
        }
        let delta = center_of(b) - eye;
        d.plan.push(PlanItem {
            index: i,
            mesh_id: item.mesh.id,
            material_id: item.material.id,
            depth: dot(delta, delta),
            transparent: d.materials[ai].blend != BLEND_NONE,
        });
    }

    // Opaque to the front, transparent to the back, in place.
    var lo = 0;
    var hi = d.plan.len;
    while lo < hi {
        if !d.plan[lo].transparent { lo++; }
        else {
            hi--;
            let moved = d.plan[hi];
            d.plan[hi] = d.plan[lo];
            d.plan[lo] = moved;
        }
    }
    let opaque_count = lo;

    // Opaque draws are grouped by geometry and material so the batcher can merge
    // them. Reordering opaque draws is safe for the same reason deferred
    // renderers do it: depth testing, not submission order, decides visibility.
    // Stable, so a scene that already submits in a good order keeps it.
    if d.batching && opaque_count > 1 {
        stable_sort(d.plan[..opaque_count]) { a, b =>
            a.mesh_id < b.mesh_id || (a.mesh_id == b.mesh_id && a.material_id < b.material_id)
        };
    }
    // Transparency is order dependent: farthest first, so nearer transparent
    // surfaces blend over what is behind them.
    if d.plan.len - opaque_count > 1 {
        stable_sort(d.plan[opaque_count..]) { a, b => a.depth > b.depth };
    }
    return build_batches(d);
}

// Groups consecutive plan entries with one geometry and one material into one
// batch, and fills the instance buffer in batch order.
fn build_batches(d: Device&) -> bool {
    var i = 0;
    while i < d.plan.len {
        let first = d.plan[i];
        var j = i + 1;
        while j < d.plan.len {
            let other = d.plan[j];
            if other.mesh_id != first.mesh_id || other.material_id != first.material_id { break; }
            j++;
        }
        let count = j - i;
        var instanced = false;
        if d.batching && count > 1 {
            let ai = material_index(d, d.items[first.index].material);
            if ai >= 0 && pipeline_instanced_get(d, ai).id != 0 { instanced = true; }
        }
        var instance_start = 0;
        if instanced {
            instance_start = d.instances.len;
            for k in i..j {
                let item = d.items[d.plan[k].index];
                let normal = mat4_normal(item.model);
                d.instances.push(Instance { model: item.model, normal: normal });
            }
            d.stats.instances += count;
            d.stats.instanced++;
        }
        d.batches.push(Batch { plan_start: i, count: count, instance_start: instance_start,
                               instanced: instanced });
        i = j;
    }
    d.stats.batches += d.batches.len;
    return upload_instances(d);
}

// Grows the instance buffer to a power of two and rewrites it whole: a complete
// rewrite is what lets the backend cycle the buffer instead of waiting for a
// frame still reading it, and an instance that is never drawn costs nothing.
fn upload_instances(d: Device&) -> bool {
    if d.instances.len == 0 { return true; }
    if d.instance_capacity < d.instances.len {
        var cap = if d.instance_capacity > 0 { d.instance_capacity } else { 64 };
        while cap < d.instances.len { cap = cap * 2; }
        let buffer = gpu_empty_vertex_buffer(cap * 128);
        if buffer.id == 0 { d.last_error = ERR_GPU; return false; }
        if d.instance_buffer.id != 0 { gpu_release_buffer(d.instance_buffer); }
        d.instance_buffer = buffer;
        d.instance_capacity = cap;
    }
    while d.instances.len < d.instance_capacity { d.instances.push(Instance {}); }
    let data = d.instances[..];
    if !gpu_update_buffer(d.instance_buffer, bytes_of(data)) {
        d.last_error = ERR_GPU;
        return false;
    }
    return true;
}
