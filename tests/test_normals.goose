// 0.2 acceptance: normals survive a non-uniform scale.
//
// Two renders must agree: one mesh scaled by the model matrix, and an
// equivalent mesh with the stretch already in its vertices and the correctly
// transformed normal baked in. If the renderer transformed normals with the
// model matrix instead of its inverse transpose, the first render would be
// darker than the second.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 64;
let STRETCH = float3 { 2.0, 1.0, 1.0 };

// A triangle with a deliberately diagonal normal: the case a uniform scale and
// a stretched cube both hide.
fn make_mesh(dev: hipgr::Device&, scale_pos: float3, normal: float3) -> hipgr::Mesh {
    let p = [float3 { -0.9, -0.9, 0.0 }, float3 { 0.9, -0.9, 0.0 }, float3 { 0.0, 0.9, 0.0 }];
    var verts: hipgr::Vertex[>..] = [];
    for i in 3 {
        verts.push(hipgr::Vertex {
            pos: float3 { p[i].x * scale_pos.x, p[i].y * scale_pos.y, p[i].z * scale_pos.z },
            normal: normal,
            uv: float2 { 0.0, 0.0 },
        });
    }
    let idx: u16[3] = [0, 1, 2];
    let vs = verts[..];
    return hipgr::mesh_create(dev, vs, idx[..]);
}

fn main() {
    // The matrix itself: for scale(2, 1, 1) the inverse transpose is
    // diag(0.5, 1, 1).
    let n = hipgr::mat4_normal(hipgr::mat4_scale(STRETCH));
    verify::expect_near(hipgr::mat4_column(n, 0).x, 0.5, 0.0001, "normal column 0 scales by 1/2");
    verify::expect_near(hipgr::mat4_column(n, 1).y, 1.0, 0.0001, "normal column 1 keeps its length");
    verify::expect_near(hipgr::mat4_column(n, 2).z, 1.0, 0.0001, "normal column 2 keeps its length");
    verify::expect_near(hipgr::mat4_column(n, 3).w, 1.0, 0.0001, "normal matrix keeps no translation");

    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_normals: no GPU device");
        return;
    }
    hipgr::quality(dev, hipgr::QUALITY_LINEAR);
    defer hipgr::close(dev);

    let n0 = float3 { 0.70710678, 0.70710678, 0.0 };
    // Inverse transpose of scale(2,1,1) applied to n0, normalized.
    let n1 = float3 { 0.4472136, 0.8944272, 0.0 };

    let stretched = make_mesh(dev, float3 { 1.0, 1.0, 1.0 }, n0);
    let equivalent = make_mesh(dev, STRETCH, n1);

    let mat = hipgr::material_solid(dev, float4_1, false);
    verify::expect(mat.id != 0, "material created");
    // Light travels along -n1's opposite: -direction is (0.5, 0.866, 0), close
    // to the correct normal and far from the untransformed one.
    verify::expect(hipgr::set_light(dev, float3 { -0.5, -0.8660254, 0.0 }, float3_1, 0.2),
                   "light set");
    let cam = hipgr::camera_look_at(float3 { 0.0, 0.0, 3.0 }, float3_0, float3 { 0.0, 1.0, 0.0 },
                                    1.0);

    // Scaled by the model matrix.
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, stretched, mat, hipgr::mat4_scale(STRETCH)), "scaled draw");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    let a = verify::pixel(hipgr::frame_pixels(dev), SIZE, SIZE / 2, SIZE / 2);

    // The same geometry, with the stretch baked into the vertices.
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "second frame begins");
    verify::expect(hipgr::draw(dev, equivalent, mat, hipgr::mat4_identity()), "baked draw");
    verify::expect(hipgr::end_frame(dev), "second frame ends");
    let b = verify::pixel(hipgr::frame_pixels(dev), SIZE, SIZE / 2, SIZE / 2);

    verify::expect(verify::same_color(a, b, 3),
                   "a stretched mesh shades like the equivalent baked one");

    // And both are the colour the maths says: ndl ~ 0.998 * 0.8 + 0.2 ambient.
    verify::expect(verify::close_to(a[0], 255, 6), "the lit face is at full brightness");

    verify::pass("test_normals");
}
