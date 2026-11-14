// 0.4 acceptance: sorted transparency.
//
// Two overlapping transparent quads are submitted near-first, the order a scene
// built in any arbitrary order would produce. HiPGR sorts transparent draws back
// to front, so the result must be the far quad composited first and the near one
// over it: 0.5 * near + 0.5 * (0.5 * far) with black behind. The wrong order
// would swap the two channel values, which is what the second half checks.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 64;

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_transparency: no GPU device");
        return;
    }
    defer hipgr::close(dev);
    // Linear output: with no tone curve the composited value is the arithmetic
    // above, so the expected pixel is exact.
    verify::expect(hipgr::quality(dev, hipgr::QUALITY_LINEAR), "linear quality accepted");

    let quad = hipgr::mesh_quad(dev);
    let red = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4 { 1.0, 0.0, 0.0, 0.5 },
        unlit: true,
        blend: hipgr::BLEND_ALPHA,
        depth_write: false,
    });
    let blue = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4 { 0.0, 0.0, 1.0, 0.5 },
        unlit: true,
        blend: hipgr::BLEND_ALPHA,
        depth_write: false,
    });
    verify::expect(red.id != 0 && blue.id != 0, "transparent materials created");

    let cam = hipgr::camera_look_at(float3 { 0.0, 0.0, 3.0 }, float3_0,
                                    float3 { 0.0, 1.0, 0.0 }, 0.9);
    // Same size and place on screen, 0.5 apart in depth.
    let far_red = hipgr::mat4_mul(hipgr::mat4_translate(float3 { 0.0, 0.0, -2.0 }),
                                  hipgr::mat4_scale(float3 { 2.0, 2.0, 2.0 }));
    let near_blue = hipgr::mat4_mul(hipgr::mat4_translate(float3 { 0.0, 0.0, -1.5 }),
                                    hipgr::mat4_scale(float3 { 2.0, 2.0, 2.0 }));

    // Near first, which is the wrong order to draw them in.
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, quad, blue, near_blue), "draw succeeds");
    verify::expect(hipgr::draw(dev, quad, red, far_red), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    let near_first = hipgr::frame_pixels(dev);

    // Far first, the order an application would have to produce itself without
    // sorting. The two frames must agree.
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, quad, red, far_red), "draw succeeds");
    verify::expect(hipgr::draw(dev, quad, blue, near_blue), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    let far_first = hipgr::frame_pixels(dev);

    verify::expect_eq(verify::count_different(near_first, far_first), 0,
                      "submission order does not change a transparent scene");

    // And the sorted result is the right one: blue over red, not red over blue.
    // 0.5 blue + 0.5 * (0.5 red) is 64 red, 0 blue, 128; the wrong order is the
    // same two numbers swapped.
    let a = verify::pixel(near_first, SIZE, SIZE / 2, SIZE / 2);
    verify::expect(a[2] > 110 && a[2] < 146, "the near blue survives: blue channel at 128");
    verify::expect(a[0] > 46 && a[0] < 82, "the far red shows through: red channel at 64");
    verify::expect(a[1] < 6, "nothing adds green");

    // Opaque geometry goes first: a transparent quad in front of an opaque one
    // still blends over it, whichever was submitted first.
    let green = hipgr::material_solid(dev, float4 { 0.0, 1.0, 0.0, 1.0 }, true);
    let solid = hipgr::mat4_mul(hipgr::mat4_translate(float3 { 0.0, 0.0, -3.0 }),
                                hipgr::mat4_scale(float3 { 2.0, 2.0, 2.0 }));
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, quad, blue, near_blue), "draw succeeds");
    verify::expect(hipgr::draw(dev, quad, green, solid), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    let mixed = verify::pixel(hipgr::frame_pixels(dev), SIZE, SIZE / 2, SIZE / 2);
    verify::expect(mixed[1] > 110 && mixed[1] < 146,
                   "the opaque green is behind, at 128");
    verify::expect(mixed[2] > 110 && mixed[2] < 146, "the transparent blue is over it, at 128");

    verify::pass("test_transparency");
}
