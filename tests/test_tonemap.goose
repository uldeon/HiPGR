// 0.3 acceptance: the post chain.
//
// The scene pass writes linear HDR values into an RGBA16F target; the composite
// pass applies exposure, bloom and the tone curve. Each of those is measured
// here on an unlit quad, whose colour is exactly known, so the numbers come from
// the curves themselves rather than from the lighting code.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 64;

fn shot(dev: hipgr::Device&, mesh: hipgr::Mesh, mat: hipgr::Material,
        cam: hipgr::Camera, model: hipgr::Mat4, x: i64, y: i64) -> u8[4] {
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, mesh, mat, model), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    return verify::pixel(hipgr::frame_pixels(dev), SIZE, x, y);
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_tonemap: no GPU device");
        return;
    }
    defer hipgr::close(dev);

    // The post chain is what this test is about, so nothing else contributes.
    verify::expect(hipgr::quality(dev, hipgr::QUALITY_MODERN), "modern quality accepted");
    verify::expect(hipgr::set_bloom(dev, 0.0, 1.0), "bloom off");
    verify::expect(hipgr::set_sky_enabled(dev, false), "sky off");
    verify::expect(hipgr::set_shadows(dev, false), "shadows off");
    verify::expect(hipgr::set_fog(dev, 0.0), "fog off");

    let quad = hipgr::mesh_quad(dev);
    // Unlit mid grey: the scene pass writes exactly 0.5.
    let grey = hipgr::material_solid(dev, float4 { 0.5, 0.5, 0.5, 1.0 }, true);
    // The quad is one unit and the camera sees two, so it covers the middle.
    let cam = hipgr::camera_orthographic(float3 { 0.0, 0.0, 3.0 }, float3_0,
                                         float3 { 0.0, 1.0, 0.0 }, 2.0, 0.1, 10.0);
    let one = hipgr::mat4_identity();

    // --- no tone mapping: the linear value, unchanged (0.2 behaviour) ---------
    verify::expect(hipgr::set_tonemap(dev, hipgr::TONEMAP_NONE), "tonemap none");
    let linear = shot(dev, quad, grey, cam, one, SIZE / 2, SIZE / 2);
    verify::expect(verify::close_to(linear[0], 128, 2), "no tone mapping is the linear value");

    // --- Reinhard: c / (1 + c), then the sRGB transfer function ---------------
    // 0.5 / 1.5 = 0.33333; 1.055 * 0.33333^(1/2.4) - 0.055 = 0.61250.
    verify::expect(hipgr::set_tonemap(dev, hipgr::TONEMAP_REINHARD), "tonemap reinhard");
    let reinhard = shot(dev, quad, grey, cam, one, SIZE / 2, SIZE / 2);
    verify::expect(verify::close_to(reinhard[0], 156, 2), "Reinhard maps 0.5 to 0.613");

    // --- ACES: the filmic curve, then the sRGB transfer function --------------
    // ACES(0.5) = 0.61631; 1.055 * 0.61631^(1/2.4) - 0.055 = 0.80732.
    verify::expect(hipgr::set_tonemap(dev, hipgr::TONEMAP_ACES), "tonemap aces");
    let aces = shot(dev, quad, grey, cam, one, SIZE / 2, SIZE / 2);
    verify::expect(verify::close_to(aces[0], 206, 2), "ACES maps 0.5 to 0.807");
    verify::expect(aces[0] > reinhard[0] && reinhard[0] > linear[0],
                   "the curves are ordered by how much they lift the midtones");

    // --- exposure -------------------------------------------------------------
    verify::expect(hipgr::set_tonemap(dev, hipgr::TONEMAP_NONE), "tonemap none again");
    verify::expect(hipgr::set_exposure(dev, 2.0), "exposure set");
    let doubled = shot(dev, quad, grey, cam, one, SIZE / 2, SIZE / 2);
    verify::expect(verify::close_to(doubled[0], 255, 1), "double exposure doubles the linear value");
    verify::expect(hipgr::set_exposure(dev, 0.5), "exposure halved");
    let halved = shot(dev, quad, grey, cam, one, SIZE / 2, SIZE / 2);
    verify::expect(verify::close_to(halved[0], 64, 2), "half exposure halves the linear value");
    verify::expect(!hipgr::set_exposure(dev, 0.0), "a zero exposure is rejected");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_ARGUMENT, "exposure error code");
    verify::expect(hipgr::set_exposure(dev, 1.0), "exposure restored");

    // --- bloom ----------------------------------------------------------------
    // A small quad at 2.0, above the bright-pass threshold of 1.0: with bloom on,
    // light bleeds into the black background around it.
    let bright = hipgr::material_solid(dev, float4 { 2.0, 2.0, 2.0, 1.0 }, true);
    let small = hipgr::mat4_scale(float3 { 0.3, 0.3, 1.0 });
    let inside = SIZE / 2;
    // Just above the quad's top edge, and further away from it: the glow has to
    // be there, and it has to fade.
    let near = SIZE / 2 - 6;
    let far = SIZE / 2 - 10;

    let center_off = shot(dev, quad, bright, cam, small, inside, inside);
    let near_off = shot(dev, quad, bright, cam, small, inside, near);
    verify::expect_eq(center_off[0], 255, "the bright quad itself clips to white");
    verify::expect(near_off[0] < 3, "no bloom leaves the background black");

    verify::expect(hipgr::set_bloom(dev, 0.6, 1.0), "bloom on");
    let near_on = shot(dev, quad, bright, cam, small, inside, near);
    let far_on = shot(dev, quad, bright, cam, small, inside, far);
    verify::expect(near_on[0] > near_off[0] + 20, "bloom bleeds light outside the quad");
    verify::expect(far_on[0] < near_on[0], "the glow fades with distance from the quad");

    // A dimmer quad is below the threshold and does not bloom.
    let dim = hipgr::material_solid(dev, float4 { 0.8, 0.8, 0.8, 1.0 }, true);
    let dim_halo = shot(dev, quad, dim, cam, small, inside, near);
    verify::expect(dim_halo[0] < 3, "a surface below the threshold does not bloom");

    verify::pass("test_tonemap");
}
