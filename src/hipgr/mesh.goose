// HiPGR: meshes.
//
// A mesh is one vertex buffer and one index buffer on the GPU, created from
// CPU vertex data in the layout the built-in shaders read. Geometry helpers
// build the same data here; importing files (glTF and friends) is a separate
// concern that arrives with the asset layer.
namespace hipgr;

import std;
import vec;
import .handle;
import .device;
import .gpu;

// What the built-in shaders read, in shader location order. The backend lays
// vertex inputs out as this struct is packed: 32 bytes, no padding.
struct Vertex {
    pos: float3,
    normal: float3,
    uv: float2,
}

fn vertex_bytes() -> i64 { 32 }

// Creates a mesh from CPU data. Indices are 16-bit, so a mesh holds at most
// 65536 vertices; every index is checked against the vertex count before
// anything reaches the GPU.
fn mesh_create(d: Device&, vertices: const Vertex[:], indices: const u16[:]) -> Mesh {
    if vertices.len == 0 { d.last_error = ERR_BAD_ARGUMENT; return Mesh { 0 }; }
    if vertices.len > 65536 { d.last_error = ERR_BAD_ARGUMENT; return Mesh { 0 }; }
    if indices.len == 0 || indices.len % 3 != 0 {
        d.last_error = ERR_BAD_ARGUMENT;
        return Mesh { 0 };
    }
    for i in indices {
        if i >= vertices.len { d.last_error = ERR_BAD_ARGUMENT; return Mesh { 0 }; }
    }

    // Bound to locals before the slice parameters, as Goose's package docs
    // recommend for a growable value passed to a slice parameter.
    var vs: Vertex[>..] = [];
    vs.append(vertices);
    var is: u16[>..] = [];
    is.append(indices);

    let vb = gpu_vertex_buffer(bytes_of(vs));
    if vb.id == 0 { d.last_error = ERR_GPU; return Mesh { 0 }; }
    let ib = gpu_index_buffer(bytes_of(is));
    if ib.id == 0 {
        gpu_release_buffer(vb);
        d.last_error = ERR_GPU;
        return Mesh { 0 };
    }
    d.last_error = ERR_NONE;
    return alloc_mesh(d, vb, ib, vs.len, is.len);
}

fn release(d: Device&, h: Mesh) {
    let i = mesh_index(d, h);
    if i < 0 { d.last_error = ERR_BAD_HANDLE; return; }
    gpu_release_buffer(d.meshes[i].vertex_buffer);
    gpu_release_buffer(d.meshes[i].index_buffer);
    d.meshes[i].vertex_buffer.id = 0;
    d.meshes[i].index_buffer.id = 0;
    d.meshes[i].live = false;
    d.meshes[i].generation = next_generation(d.meshes[i].generation);
    d.stats.meshes = d.stats.meshes - 1;
}

fn mesh_info(d: Device&, h: Mesh) -> MeshInfo {
    let i = mesh_index(d, h);
    if i < 0 { return MeshInfo {}; }
    let r = d.meshes[i];
    return MeshInfo { vertices: r.vertex_count, indices: r.index_count,
                      triangles: r.index_count / 3, vertex_bytes: r.vertex_bytes,
                      index_bytes: r.index_bytes };
}

// --- geometry helpers -------------------------------------------------------------

// One triangle facing the camera, the first acceptance test of the renderer.
fn mesh_triangle(d: Device&) -> Mesh {
    let verts: Vertex[3] = [
        Vertex { pos: float3 { -0.6, -0.5, 0.0 }, normal: float3 { 0.0, 0.0, 1.0 },
                 uv: float2 { 0.0, 1.0 } },
        Vertex { pos: float3 { 0.6, -0.5, 0.0 }, normal: float3 { 0.0, 0.0, 1.0 },
                 uv: float2 { 1.0, 1.0 } },
        Vertex { pos: float3 { 0.0, 0.6, 0.0 }, normal: float3 { 0.0, 0.0, 1.0 },
                 uv: float2 { 0.5, 0.0 } },
    ];
    let idx: u16[3] = [0, 1, 2];
    mesh_create(d, verts[..], idx[..])
}

// A unit quad in the XY plane, facing +Z.
fn mesh_quad(d: Device&) -> Mesh {
    let verts: Vertex[4] = [
        Vertex { pos: float3 { -0.5, -0.5, 0.0 }, normal: float3 { 0.0, 0.0, 1.0 },
                 uv: float2 { 0.0, 0.0 } },
        Vertex { pos: float3 { 0.5, -0.5, 0.0 }, normal: float3 { 0.0, 0.0, 1.0 },
                 uv: float2 { 1.0, 0.0 } },
        Vertex { pos: float3 { 0.5, 0.5, 0.0 }, normal: float3 { 0.0, 0.0, 1.0 },
                 uv: float2 { 1.0, 1.0 } },
        Vertex { pos: float3 { -0.5, 0.5, 0.0 }, normal: float3 { 0.0, 0.0, 1.0 },
                 uv: float2 { 0.0, 1.0 } },
    ];
    let idx: u16[6] = [0, 1, 2, 0, 2, 3];
    mesh_create(d, verts[..], idx[..])
}

// A unit cube centred on the origin, four vertices per face so each face has
// its own normal and a full texture, wound counter-clockwise seen from
// outside (what back-face culling keeps).
fn mesh_cube(d: Device&) -> Mesh {
    var verts: Vertex[>..] = [];
    var indices: u16[>..] = [];
    let axes: float3[3] = [float3 { 1.0, 0.0, 0.0 }, float3 { 0.0, 1.0, 0.0 },
                           float3 { 0.0, 0.0, 1.0 }];
    let corners: float2[4] = [float2 { -1.0, -1.0 }, float2 { 1.0, -1.0 },
                              float2 { 1.0, 1.0 }, float2 { -1.0, 1.0 }];
    let uv: float2[4] = [float2 { 0.0, 1.0 }, float2 { 1.0, 1.0 },
                         float2 { 1.0, 0.0 }, float2 { 0.0, 0.0 }];
    for f in 6 {
        let sign: f32 = if f % 2 == 0 { 1.0 } else { -1.0 };
        let n = axes[f / 2] * float3 { sign, sign, sign };
        let u = axes[(f / 2 + 1) % 3] * float3 { sign, sign, sign };
        let v = cross(n, u);
        let base = verts.len as u16;
        for c in 4 {
            let corner = corners[c];
            let p = (n + u * float3 { corner.x, corner.x, corner.x }
                       + v * float3 { corner.y, corner.y, corner.y }) * float3 { 0.5, 0.5, 0.5 };
            verts.push(Vertex { pos: p, normal: n, uv: uv[c] });
        }
        indices.append([base, base + 1, base + 2, base, base + 2, base + 3]);
    }
    let vs = verts[..];
    let is = indices[..];
    return mesh_create(d, vs, is);
}
