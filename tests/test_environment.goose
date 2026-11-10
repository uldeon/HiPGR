// 0.3 acceptance: the sky and distance fog.
//
// The sky is a cube map sampled along the view ray, so it must be a gradient in
// screen space, not a flat fill: looking up must be darker and bluer than
// looking at the horizon. Fog blends a surface towards that same horizon colour
// with distance.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 64;

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_environment: no GPU device");
        return;
    }
    defer hipgr::close(dev);
    verify::expect(hipgr::quality(dev, hipgr::QUALITY_MODERN), "modern quality accepted");
    verify::expect(hipgr::set_bloom(dev, 0.0, 1.0), "bloom off");
    verify::expect(hipgr::set_shadows(dev, false), "shadows off");

    let cam = hipgr::camera_look_at(float3_0, float3 { 0.0, 0.0, -1.0 },
                                    float3 { 0.0, 1.0, 0.0 }, 0.9);

    // --- the sky --------------------------------------------------------------
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "sky frame begins");
    verify::expect(hipgr::end_frame(dev), "sky frame ends");
    let sky = hipgr::frame_pixels(dev);
    let horizon = verify::pixel(sky, SIZE, SIZE / 2, SIZE / 2);
    let above = verify::pixel(sky, SIZE, SIZE / 2, SIZE / 6);
    verify::expect(horizon[2] > horizon[0] + 10, "the sky is blue at the horizon");
    verify::expect(above[2] < horizon[2], "the zenith is darker than the horizon");
    verify::expect(above[0] < horizon[0], "the zenith is darker red than the horizon");
    verify::expect(horizon[0] > 40, "the sky is a colour, not black");

    // With the sky off, the same frame is the clear colour and nothing else.
    verify::expect(hipgr::set_sky_enabled(dev, false), "sky off");
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "empty frame begins");
    verify::expect(hipgr::end_frame(dev), "empty frame ends");
    verify::expect_pixel(hipgr::frame_pixels(dev), SIZE, SIZE / 2, SIZE / 2, [0, 0, 0, 255], 1,
                         "with no sky the clear colour is visible");
    verify::expect(hipgr::set_sky_enabled(dev, true), "sky on again");

    // --- fog ------------------------------------------------------------------
    // Unlit white, so any change is the fog and nothing else. The quad sits far
    // enough away that the default fog would wash it out.
    let quad = hipgr::mesh_quad(dev);
    let white = hipgr::material_solid(dev, float4_1, true);
    let model = hipgr::mat4_mul(hipgr::mat4_translate(float3 { 0.0, 0.0, -20.0 }),
                                hipgr::mat4_scale(float3 { 3.0, 3.0, 3.0 }));
    let far = hipgr::camera_look_at(float3 { 0.0, 0.0, 3.0 }, float3_0,
                                    float3 { 0.0, 1.0, 0.0 }, 0.9);

    // Linear output for the fog numbers: with a tone curve, even an unlit white
    // surface comes back at 231, which says nothing about the fog.
    verify::expect(hipgr::set_tonemap(dev, hipgr::TONEMAP_NONE), "tonemap off");
    verify::expect(hipgr::set_fog(dev, 0.0), "fog off");
    verify::expect(hipgr::begin_frame(dev, far, float4_0), "near frame begins");
    verify::expect(hipgr::draw(dev, quad, white, model), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "near frame ends");
    let clear = verify::pixel(hipgr::frame_pixels(dev), SIZE, SIZE / 2, SIZE / 2);
    verify::expect_eq(clear[0], 255, "without fog a far surface keeps its colour");

    verify::expect(hipgr::set_fog(dev, 0.08), "fog on");
    verify::expect(hipgr::begin_frame(dev, far, float4_0), "foggy frame begins");
    verify::expect(hipgr::draw(dev, quad, white, model), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "foggy frame ends");
    let foggy = verify::pixel(hipgr::frame_pixels(dev), SIZE, SIZE / 2, SIZE / 2);
    verify::expect(foggy[0] < clear[0], "fog darkens a white surface towards the horizon");
    verify::expect(foggy[2] > foggy[0] + 10, "fog tints it towards the blue horizon");
    verify::expect(!hipgr::set_fog(dev, -1.0), "a negative fog density is rejected");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_ARGUMENT, "fog error code");

    verify::pass("test_environment");
}
