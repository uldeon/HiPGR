// 0.6 acceptance: multisampling.
//
// A slanted edge is the whole point. Without multisampling a pixel is either
// inside the triangle or not, so an edge that crosses pixels diagonally is a
// staircase of full-strength red and full-strength background. With four
// samples the same edge leaves pixels that are partly covered, and those read
// as intermediate values — which is what antialiasing is.
//
// The test counts those intermediate pixels, requires the flat interior to be
// unchanged by the sample count, and checks the switch's validation.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 96;
let FACE: u8 = 229;       // 0.9 unlit red, written linearly: 0.9 * 255
let FACE_I: i64 = 229;

// Pixels that are neither the face nor the background: partial coverage.
fn count_partial(px: const u8[:]) -> i64 {
    var n = 0;
    var i = 0;
    while i + 3 < px.len {
        let r = px[i] as i64;
        let g = px[i + 1] as i64;
        let b = px[i + 2] as i64;
        if r > 8 && r < FACE_I - 8 && g < 8 && b < 8 { n++; }
        i += 4;
    }
    return n;
}

fn render(dev: hipgr::Device&, quad: hipgr::Mesh, mat: hipgr::Material,
          cam: hipgr::Camera, model: hipgr::Mat4) -> u8[>..] {
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, quad, mat, model), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    return hipgr::frame_pixels(dev);
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_msaa: no GPU device");
        return;
    }
    defer hipgr::close(dev);
    // Linear output: a covered pixel is exactly the tint times its coverage, so
    // the intermediate values are the antialiasing and nothing else.
    verify::expect(hipgr::quality(dev, hipgr::QUALITY_LINEAR), "linear quality accepted");

    let quad = hipgr::mesh_quad(dev);
    let mat = hipgr::material_solid(dev, float4 { 0.9, 0.0, 0.0, 1.0 }, true);
    let cam = hipgr::camera_look_at(float3 { 0.0, 0.0, 3.0 }, float3_0,
                                    float3 { 0.0, 1.0, 0.0 }, 0.8);
    // Turned enough that all four edges cross pixels diagonally, and big enough
    // that there is a solid interior to compare.
    let model = hipgr::mat4_mul(hipgr::mat4_mul(hipgr::mat4_translate(float3 { 0.0, 0.0, -1.5 }),
                                               hipgr::mat4_rotate(float3 { 0.0, 0.0, 1.0 },
                                                                  0.35)),
                               hipgr::mat4_scale(float3 { 1.6, 1.6, 1.6 }));

    verify::expect_eq(hipgr::msaa_samples(dev), 1, "multisampling is off by default");
    let plain = render(dev, quad, mat, cam, model);
    let plain_partial = count_partial(plain);
    let plain_face = verify::count_color(plain, [FACE, 0, 0, 255], 2);
    verify::expect(plain_face > 1000, "the rotated quad is on screen");
    // A rasteriser without multisampling has no partial coverage at all.
    verify::expect(plain_partial < 20, "without MSAA an edge is a staircase");

    // --- four samples ----------------------------------------------------------
    verify::expect(hipgr::set_msaa(dev, 4), "4x multisampling accepted");
    verify::expect_eq(hipgr::msaa_samples(dev), 4, "the setting reads back");
    let smooth = render(dev, quad, mat, cam, model);
    let smooth_partial = count_partial(smooth);
    verify::expect(smooth_partial > 80, "4x MSAA leaves partial pixels along the edges");
    verify::expect(smooth_partial > plain_partial + 80,
                   "and far more of them than no multisampling leaves");

    // The interior is untouched: multisampling is an edge effect, not a filter
    // over the whole image.
    verify::expect_pixel(smooth, SIZE, SIZE / 2, SIZE / 2, [FACE, 0, 0, 255], 0,
                         "the flat interior is unchanged");
    let smooth_face = verify::count_color(smooth, [FACE, 0, 0, 255], 0);
    verify::expect(smooth_face > 1000, "the face is still solid where it is solid");
    // The shape is the same shape: MSAA trades edge pixels for gradients, it does
    // not move the geometry.
    verify::expect(smooth_face + smooth_partial > plain_face + plain_partial - 200,
                   "the same area is covered, counted with the gradients");

    // --- the switch ------------------------------------------------------------
    // 4 is the only count offered: 2 and 8 are refused because the backend cannot
    // report which counts it supports and these resolved to nothing here.
    verify::expect(!hipgr::set_msaa(dev, 3), "3 samples per pixel is refused");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_ARGUMENT, "MSAA error code");
    verify::expect(!hipgr::set_msaa(dev, 2), "2 samples per pixel is refused");
    verify::expect(!hipgr::set_msaa(dev, 8), "8 samples per pixel is refused");
    verify::expect(hipgr::msaa_samples(dev) == 4, "a refused change leaves the setting alone");

    // Back to one sample per pixel: the staircase returns exactly.
    verify::expect(hipgr::set_msaa(dev, 1), "multisampling off again");
    let back = render(dev, quad, mat, cam, model);
    verify::expect_eq(verify::count_different(back, plain), 0,
                      "turning MSAA off restores the plain frame exactly");

    verify::pass("test_msaa");
}
