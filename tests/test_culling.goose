// 0.4 acceptance: frustum culling.
//
// Culling may change the cost of a frame, never its pixels. The scene here has
// objects inside the view and objects well outside it; the test renders it with
// culling off and on and requires the two images to be identical, requires the
// culler to have removed exactly the objects outside the frustum, and requires
// an object straddling the edge of the view to stay: a box the frustum cuts
// through is visible, so it must not be culled.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 96;

// One frame of the scene. Returns the pixels, and leaves the stats behind.
fn render(dev: hipgr::Device&, cam: hipgr::Camera, cube: hipgr::Mesh, mat: hipgr::Material,
          culling: bool) -> u8[>..] {
    verify::expect(hipgr::set_culling(dev, culling), "culling switch accepted");
    verify::expect(hipgr::begin_frame(dev, cam, float4 { 0.0, 0.0, 0.0, 1.0 }), "frame begins");
    // 5x5 inside the view at z = -6, where the frustum is 2.5 wide either way.
    for y in 5 {
        for x in 5 {
            let model = hipgr::mat4_trs(float3 { (x - 2) * 0.6, (y - 2) * 0.6, -6.0 },
                                        float3 { 0.0, 1.0, 0.0 }, 0.0,
                                        float3 { 0.5, 0.5, 0.5 });
            verify::expect(hipgr::draw(dev, cube, mat, model), "draw succeeds");
        }
    }
    // Behind the camera: never visible from here.
    for i in 8 {
        let model = hipgr::mat4_trs(float3 { (i - 4) * 0.6, 0.0, 4.0 },
                                    float3 { 0.0, 1.0, 0.0 }, 0.0, float3 { 0.5, 0.5, 0.5 });
        verify::expect(hipgr::draw(dev, cube, mat, model), "draw succeeds");
    }
    // Far to the right of a 45-degree view, and far below it.
    for i in 6 {
        let model = hipgr::mat4_trs(float3 { 12.0 + i, 0.0, -6.0 },
                                    float3 { 0.0, 1.0, 0.0 }, 0.0, float3 { 0.5, 0.5, 0.5 });
        verify::expect(hipgr::draw(dev, cube, mat, model), "draw succeeds");
    }
    for i in 4 {
        let model = hipgr::mat4_trs(float3 { 0.0, -14.0 - i, -6.0 },
                                    float3 { 0.0, 1.0, 0.0 }, 0.0, float3 { 0.5, 0.5, 0.5 });
        verify::expect(hipgr::draw(dev, cube, mat, model), "draw succeeds");
    }
    // Straddling the left edge of the view at z = -6 (half width 2.54): its box
    // spans x -2.7..-2.2, so half of it is on screen and it must not be culled.
    let edge = hipgr::mat4_trs(float3 { -2.45, 0.0, -6.0 }, float3 { 0.0, 1.0, 0.0 }, 0.0,
                               float3 { 0.8, 0.8, 0.8 });
    verify::expect(hipgr::draw(dev, cube, mat, edge), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    return hipgr::frame_pixels(dev);
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_culling: no GPU device");
        return;
    }
    defer hipgr::close(dev);
    verify::expect(hipgr::quality(dev, hipgr::QUALITY_LINEAR), "linear quality accepted");

    let cube = hipgr::mesh_cube(dev);
    // Unlit: the pixel is the tint, so a difference can only come from culling.
    let mat = hipgr::material_solid(dev, float4 { 0.9, 0.45, 0.2, 1.0 }, true);
    let cam = hipgr::camera_perspective(float3 { 0.0, 0.0, 0.0 }, float3 { 0.0, 0.0, -6.0 },
                                        float3 { 0.0, 1.0, 0.0 }, 0.8, 0.1, 60.0);

    let before = hipgr::stats(dev).culled;
    let unculled = render(dev, cam, cube, mat, false);
    let culled_none = hipgr::stats(dev).culled - before;
    verify::expect_eq(culled_none, 0, "with culling off nothing is culled");
    verify::expect(verify::count_color(unculled, [230, 115, 51, 255], 2) > 200,
                   "the cubes are on screen with culling off");

    let before_culled = hipgr::stats(dev).culled;
    let culled = render(dev, cam, cube, mat, true);
    let removed = hipgr::stats(dev).culled - before_culled;
    // 8 behind the camera, 6 to the right and 4 below; the 25 in view and the
    // one on the edge stay.
    verify::expect_eq(removed, 18, "exactly the objects outside the frustum are culled");
    verify::expect_eq(verify::count_different(unculled, culled), 0,
                      "culling changes no pixel");

    // A mesh with no vertices outside the view is never culled, whatever its
    // size: a huge quad that covers the camera is inside the frustum.
    verify::expect(hipgr::set_culling(dev, true), "culling on");
    let quad = hipgr::mesh_quad(dev);
    let big = hipgr::mat4_mul(hipgr::mat4_translate(float3 { 0.0, 0.0, -1.0 }),
                              hipgr::mat4_scale(float3 { 40.0, 40.0, 40.0 }));
    verify::expect(hipgr::begin_frame(dev, cam, float4 { 0.0, 0.0, 0.0, 1.0 }), "frame begins");
    verify::expect(hipgr::draw(dev, quad, mat, big), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    verify::expect_eq(verify::count_color(hipgr::frame_pixels(dev), [230, 115, 51, 255], 2),
                      SIZE * SIZE, "an object covering the whole view is never culled");

    verify::pass("test_culling");
}
