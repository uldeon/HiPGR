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

// A mesh's local axis-aligned bounds, which is what frustum culling tests. The
// mesh never changes after creation, so this is computed once from the vertices
// and stored with the mesh; the culler only has to transform its eight corners.
// Bounds itself is declared in device.goose, next to the mesh record that holds
// it, so the two modules do not import each other.
fn bounds_of(vertices: const Vertex[:]) -> Bounds {
    if vertices.len == 0 { return Bounds {}; }
    var lo = vertices[0].pos;
    var hi = lo;
    for v in vertices {
        let p = v.pos;
        if p.x < lo.x { lo.x = p.x; }
        if p.y < lo.y { lo.y = p.y; }
        if p.z < lo.z { lo.z = p.z; }
        if p.x > hi.x { hi.x = p.x; }
        if p.y > hi.y { hi.y = p.y; }
        if p.z > hi.z { hi.z = p.z; }
    }
    return Bounds { min: lo, max: hi };
}

// Checks shared by both index widths and both upload paths. Every index is
// checked against the vertex count before anything reaches the GPU.
fn mesh_validate(d: Device&, vertices: const Vertex[:], index_count: i64) -> bool {
    if vertices.len == 0 { d.last_error = ERR_BAD_ARGUMENT; return false; }
    if index_count == 0 || index_count % 3 != 0 {
        d.last_error = ERR_BAD_ARGUMENT;
        return false;
    }
    return true;
}

// The one limit 16-bit indices have: at most 65536 addressable vertices.
fn mesh_fits_u16(d: Device&, vertices: const Vertex[:]) -> bool {
    if vertices.len > 65536 { d.last_error = ERR_BAD_ARGUMENT; return false; }
    return true;
}

// Uploads already-validated geometry and records the mesh.
fn mesh_upload(d: Device&, vertices: const Vertex[:], index_bytes: const u8[:],
               index_count: i64, index_size: i64) -> Mesh {
    let bounds = bounds_of(vertices);
    // Bound to locals before the slice parameters, as Goose's package docs
    // recommend for a growable value passed to a slice parameter.
    var vs: Vertex[>..] = [];
    vs.append(vertices);
    var is: u8[>..] = [];
    is.append(index_bytes);

    let vb = gpu_vertex_buffer(bytes_of(vs));
    if vb.id == 0 { d.last_error = ERR_GPU; return Mesh { 0 }; }
    let ib = gpu_index_buffer(bytes_of(is));
    if ib.id == 0 {
        gpu_release_buffer(vb);
        d.last_error = ERR_GPU;
        return Mesh { 0 };
    }
    d.last_error = ERR_NONE;
    return alloc_mesh(d, vb, ib, vs.len, index_count, index_size, bounds);
}

// Creates a mesh from CPU data, indexed with 16-bit indices: at most 65536
// vertices.
fn mesh_create(d: Device&, vertices: const Vertex[:], indices: const u16[:]) -> Mesh {
    if !mesh_validate(d, vertices, indices.len) { return Mesh { 0 }; }
    if !mesh_fits_u16(d, vertices) { return Mesh { 0 }; }
    for i in indices {
        if i >= vertices.len { d.last_error = ERR_BAD_ARGUMENT; return Mesh { 0 }; }
    }
    var is: u16[>..] = [];
    is.append(indices);
    return mesh_upload(d, vertices, bytes_of(is), is.len, 2);
}

// The same, with 32-bit indices: for large meshes, whose vertex count would not
// fit in 16 bits. Which one a mesh uses is recorded and reported by
// mesh_info().index_size.
fn mesh_create32(d: Device&, vertices: const Vertex[:], indices: const u32[:]) -> Mesh {
    if !mesh_validate(d, vertices, indices.len) { return Mesh { 0 }; }
    for i in indices {
        if i >= vertices.len { d.last_error = ERR_BAD_ARGUMENT; return Mesh { 0 }; }
    }
    var is: u32[>..] = [];
    is.append(indices);
    return mesh_upload(d, vertices, bytes_of(is), is.len, 4);
}

// Replaces a mesh's geometry, for animation and streaming. The vertex count may
// change, in either direction: the existing buffers are reused when the new
// data fits and replaced when it does not, so a mesh handle stays valid for the
// life of the mesh. Only a 16-bit-indexed mesh can be updated this way, because
// the index slice's own width decides how its bytes are read.
fn mesh_update(d: Device&, h: Mesh, vertices: const Vertex[:], indices: const u16[:]) -> bool {
    let i = mesh_index(d, h);
    if i < 0 { d.last_error = ERR_BAD_HANDLE; return false; }
    if d.meshes[i].index_size != 2 { d.last_error = ERR_BAD_ARGUMENT; return false; }
    if !mesh_validate(d, vertices, indices.len) { return false; }
    if !mesh_fits_u16(d, vertices) { return false; }
    for k in indices {
        if k >= vertices.len { d.last_error = ERR_BAD_ARGUMENT; return false; }
    }

    var vs: Vertex[>..] = [];
    vs.append(vertices);
    var is: u16[>..] = [];
    is.append(indices);
    let vb_bytes = bytes_of(vs);
    let ib_bytes = bytes_of(is);
    let r = d.meshes[i];

    if vb_bytes.len <= r.vertex_bytes && ib_bytes.len <= r.index_bytes {
        // The usual case for animation: the buffers are big enough, so only the
        // used prefix is rewritten. Anything past the new counts is never read.
        if !gpu_update_buffer(r.vertex_buffer, vb_bytes) { d.last_error = ERR_GPU; return false; }
        if !gpu_update_buffer(r.index_buffer, ib_bytes) { d.last_error = ERR_GPU; return false; }
    } else {
        // Built before the old ones are released, so a failed allocation leaves
        // the mesh exactly as it was.
        let nvb = gpu_vertex_buffer(vb_bytes);
        if nvb.id == 0 { d.last_error = ERR_GPU; return false; }
        let nib = gpu_index_buffer(ib_bytes);
        if nib.id == 0 { gpu_release_buffer(nvb); d.last_error = ERR_GPU; return false; }
        gpu_release_buffer(r.vertex_buffer);
        gpu_release_buffer(r.index_buffer);
        d.meshes[i].vertex_buffer = nvb;
        d.meshes[i].index_buffer = nib;
        d.meshes[i].vertex_bytes = vb_bytes.len;
        d.meshes[i].index_bytes = ib_bytes.len;
    }
    d.meshes[i].vertex_count = vs.len;
    d.meshes[i].index_count = is.len;
    d.meshes[i].bounds = bounds_of(vs[..]);
    d.last_error = ERR_NONE;
    return true;
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
                      index_bytes: r.index_bytes, index_size: r.index_size };
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
