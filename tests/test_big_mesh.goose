// 0.2 acceptance: mesh data for real scenes.
//
//   * a mesh larger than 65536 vertices is indexed with 32-bit indices, and
//     renders;
//   * mesh_update replaces geometry in place, growing and shrinking, without
//     the mesh handle changing;
//   * an update that would read the wrong index width, or index a vertex that
//     does not exist, is refused and leaves the mesh as it was.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 96;

fn camera() -> hipgr::Camera {
    hipgr::camera_look_at(float3 { 0.0, 0.0, 3.0 }, float3_0, float3 { 0.0, 1.0, 0.0 }, 1.0)
}

// A flat grid of quads in the XY plane, facing +Z.
fn grid_verts(n: i64) -> hipgr::Vertex[>..] {
    var verts: hipgr::Vertex[>..] = [];
    let step = 2.0 / n;
    for y in n + 1 {
        for x in n + 1 {
            verts.push(hipgr::Vertex {
                pos: float3 { x * step - 1.0, y * step - 1.0, 0.0 },
                normal: float3 { 0.0, 0.0, 1.0 },
                uv: float2 { 0.0, 0.0 },
            });
        }
    }
    return verts;
}

fn grid_indices16(n: i64) -> u16[>..] {
    var idx: u16[>..] = [];
    let row = (n + 1) as u16;
    for y in n {
        for x in n {
            let a = (y * (n + 1) + x) as u16;
            let b = a + 1;
            let c = a + row;
            let d = c + 1;
            idx.append([a, b, d, a, d, c]);
        }
    }
    return idx;
}

fn grid_indices32(n: i64) -> u32[>..] {
    var idx: u32[>..] = [];
    let row = (n + 1) as u32;
    for y in n {
        for x in n {
            let a = (y * (n + 1) + x) as u32;
            let b = a + 1;
            let c = a + row;
            let d = c + 1;
            idx.append([a, b, d, a, d, c]);
        }
    }
    return idx;
}

fn coverage(px: const u8[:]) -> i64 {
    var n = 0;
    var i = 0;
    while i + 3 < px.len {
        if px[i] > 6 || px[i + 1] > 6 || px[i + 2] > 6 { n++; }
        i += 4;
    }
    return n;
}

fn render_coverage(dev: hipgr::Device&, m: hipgr::Mesh, mat: hipgr::Material) -> i64 {
    verify::expect(hipgr::begin_frame(dev, camera(), float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, m, mat, hipgr::mat4_identity()), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    return coverage(hipgr::frame_pixels(dev));
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_big_mesh: no GPU device");
        return;
    }
    hipgr::quality(dev, hipgr::QUALITY_LINEAR);
    defer hipgr::close(dev);

    let mat = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4 { 0.0, 1.0, 0.0, 1.0 }, unlit: true });
    verify::expect(mat.id != 0, "material created");

    // --- 32-bit indices -------------------------------------------------------
    // 257 x 257 vertices is 66049: past what a 16-bit index can address.
    let n: i64 = 256;
    let vs = grid_verts(n);
    let is = grid_indices32(n);
    let big = hipgr::mesh_create32(dev, vs[..], is[..]);
    verify::expect(big.id != 0, "a 66049-vertex mesh is created");
    let info = hipgr::mesh_info(dev, big);
    verify::expect_eq(info.vertices, 66049, "vertex count");
    verify::expect_eq(info.triangles, 131072, "triangle count");
    verify::expect_eq(info.index_size, 4, "a mesh this large uses 32-bit indices");
    verify::expect_eq(info.index_bytes, 393216 * 4, "index buffer size");

    verify::expect(render_coverage(dev, big, mat) > 2000, "the large mesh renders");

    // --- growth and shrink ----------------------------------------------------
    let small_verts: hipgr::Vertex[3] = [
        hipgr::Vertex { pos: float3 { -0.9, -0.9, 0.0 }, normal: float3 { 0.0, 0.0, 1.0 },
                        uv: float2 { 0.0, 0.0 } },
        hipgr::Vertex { pos: float3 { 0.9, -0.9, 0.0 }, normal: float3 { 0.0, 0.0, 1.0 },
                        uv: float2 { 1.0, 0.0 } },
        hipgr::Vertex { pos: float3 { 0.0, 0.9, 0.0 }, normal: float3 { 0.0, 0.0, 1.0 },
                        uv: float2 { 0.5, 1.0 } },
    ];
    let tri_idx: u16[3] = [0, 1, 2];
    let growing = hipgr::mesh_create(dev, small_verts[..], tri_idx[..]);
    verify::expect(growing.id != 0, "the mesh to grow is created");
    verify::expect_eq(hipgr::mesh_info(dev, growing).index_size, 2, "small mesh uses 16-bit indices");
    let small_coverage = render_coverage(dev, growing, mat);
    verify::expect(small_coverage > 200, "the small mesh renders");

    // Grow: 33 x 33 vertices, 2048 triangles, into the same handle.
    let vs2 = grid_verts(32);
    let is2 = grid_indices16(32);
    verify::expect(hipgr::mesh_update(dev, growing, vs2[..], is2[..]), "mesh grows");
    let grown = hipgr::mesh_info(dev, growing);
    verify::expect_eq(grown.vertices, 1089, "grown vertex count");
    verify::expect_eq(grown.triangles, 2048, "grown triangle count");
    let grown_coverage = render_coverage(dev, growing, mat);
    verify::expect(grown_coverage > small_coverage, "the grown mesh covers more of the screen");

    // Shrink back: the same handle, smaller than the buffers it already has.
    verify::expect(hipgr::mesh_update(dev, growing, small_verts[..], tri_idx[..]),
                   "mesh shrinks");
    verify::expect_eq(hipgr::mesh_info(dev, growing).vertices, 3, "shrunk vertex count");
    verify::expect(render_coverage(dev, growing, mat) > 200, "the shrunk mesh still renders");

    // --- refused updates leave the mesh alone ---------------------------------
    verify::expect(!hipgr::mesh_update(dev, big, small_verts[..], tri_idx[..]),
                   "a 32-bit mesh cannot be updated with 16-bit indices");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_ARGUMENT, "index width error code");
    verify::expect_eq(hipgr::mesh_info(dev, big).vertices, 66049, "the refused update changed nothing");

    let out_of_range: u16[3] = [0, 1, 99];
    verify::expect(!hipgr::mesh_update(dev, growing, small_verts[..], out_of_range[..]),
                   "an index past the vertices is refused");
    verify::expect_eq(hipgr::mesh_info(dev, growing).vertices, 3, "and changes nothing");

    // --- a mesh created with too many vertices for its indices ----------------
    let too_many: u16[3] = [0, 1, 2];
    let huge = hipgr::mesh_create(dev, vs[..], too_many[..]);
    verify::expect(huge.id == 0, "a 16-bit mesh refuses more than 65536 vertices");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_ARGUMENT, "vertex count error code");

    verify::pass("test_big_mesh");
}
