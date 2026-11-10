// Depth buffer: the nearer of two overlapping quads wins no matter which is
// drawn first. Drawing the near one first is the case that fails without a
// depth test, so it is the case the test uses.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

fn main() {
    let size: i64 = 128;
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, size, size) else {
        verify::skip("test_depth: no GPU device");
        return;
    }
    hipgr::quality(dev, hipgr::QUALITY_LINEAR);
    defer hipgr::close(dev);

    let quad = hipgr::mesh_quad(dev);
    let near_mat = hipgr::material_solid(dev, float4 { 1.0, 0.0, 0.0, 1.0 }, true);
    let far_mat = hipgr::material_solid(dev, float4 { 0.0, 0.0, 1.0, 1.0 }, true);
    verify::expect(near_mat.id != 0 && far_mat.id != 0, "materials created");

    let cam = hipgr::camera_look_at(float3 { 0.0, 0.0, 2.0 }, float3_0, float3 { 0.0, 1.0, 0.0 },
                                    0.8);
    // Both quads fill the middle of the screen; the near one is 1 unit closer.
    let near_model = hipgr::mat4_scale(float3 { 1.5, 1.5, 1.0 });
    let far_model = hipgr::mat4_mul(hipgr::mat4_translate(float3 { 0.0, 0.0, -1.0 }),
                                    near_model);

    // Near first, far second: without depth testing the far blue would paint
    // over the red.
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, quad, near_mat, near_model), "near draw");
    verify::expect(hipgr::draw(dev, quad, far_mat, far_model), "far draw");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    let px = hipgr::frame_pixels(dev);
    verify::expect_pixel(px, size, size / 2, size / 2, [255, 0, 0, 255], 1,
                         "near quad survives a later far draw");

    // Far first, near second: the near one still wins.
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "reverse frame begins");
    verify::expect(hipgr::draw(dev, quad, far_mat, far_model), "far draw first");
    verify::expect(hipgr::draw(dev, quad, near_mat, near_model), "near draw second");
    verify::expect(hipgr::end_frame(dev), "reverse frame ends");
    let px2 = hipgr::frame_pixels(dev);
    verify::expect_pixel(px2, size, size / 2, size / 2, [255, 0, 0, 255], 1,
                         "near quad wins when drawn last too");

    // Sanity: the far quad alone is visible, so depth, not culling, decided.
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "far-only frame begins");
    verify::expect(hipgr::draw(dev, quad, far_mat, far_model), "far-only draw");
    verify::expect(hipgr::end_frame(dev), "far-only frame ends");
    let px3 = hipgr::frame_pixels(dev);
    verify::expect_pixel(px3, size, size / 2, size / 2, [0, 0, 255, 255], 1,
                         "far quad alone reaches the screen");

    verify::pass("test_depth");
}
