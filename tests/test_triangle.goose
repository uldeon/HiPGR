// 0.1 acceptance: a triangle reaches the screen where it should, and nowhere
// else. Runs headless; the pixels are read back from the GPU.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

fn main() {
    let size: i64 = 64;
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, size, size) else {
        verify::skip("test_triangle: no GPU device");
        return;
    }
    hipgr::quality(dev, hipgr::QUALITY_LINEAR);
    defer hipgr::close(dev);

    let tri = hipgr::mesh_triangle(dev);
    verify::expect(tri.id != 0, "triangle mesh created");
    let mat = hipgr::material_solid(dev, float4 { 1.0, 0.0, 0.0, 1.0 }, true);
    verify::expect(mat.id != 0, "solid material created");

    let cam = hipgr::camera_look_at(float3 { 0.0, 0.0, 2.0 }, float3_0, float3 { 0.0, 1.0, 0.0 },
                                    0.8);
    let model = hipgr::mat4_identity();

    verify::expect_eq(hipgr::screen_size(dev).x, size, "screen width");
    verify::expect_eq(hipgr::screen_size(dev).y, size, "screen height");

    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, tri, mat, model), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");

    let px = hipgr::frame_pixels(dev);
    verify::expect_eq(px.len, size * size * 4, "read back the whole screen");

    // Inside the triangle: its centre.
    verify::expect_pixel(px, size, size / 2, size / 2, [255, 0, 0, 255], 1, "centre is the tint");
    verify::expect_pixel(px, size, size / 2, size / 2 - 10, [255, 0, 0, 255], 1,
                         "above centre is the tint");
    // Outside it: the cleared corners and the base line.
    verify::expect_pixel(px, size, 2, 2, [0, 0, 0, 255], 1, "corner is the clear colour");
    verify::expect_pixel(px, size, size - 3, 2, [0, 0, 0, 255], 1, "corner is the clear colour");
    verify::expect_pixel(px, size, 2, size - 3, [0, 0, 0, 255], 1, "corner is the clear colour");

    let s = hipgr::stats(dev);
    verify::expect_eq(s.frames, 1, "one frame counted");
    verify::expect_eq(s.draws, 1, "one draw counted");
    verify::expect_eq(s.triangles, 1, "one triangle counted");

    verify::pass("test_triangle");
}
