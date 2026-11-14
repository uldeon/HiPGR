// 0.4 acceptance: image-based lighting from the sky.
//
// Four checks, because "the scene got brighter" would also be true of a bug:
// a mirror metal takes the colour of the sky along the direction it reflects, a
// rough metal mixes that colour with the rest of the sky, a matte surface
// receives the sky's irradiance (which for a constant sky is exactly that
// constant: a value the tone mapper pins down, so a wrong normalisation cannot
// pass), and turning IBL off reproduces 0.2's constant ambient pixel for pixel.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 64;
let WHITE = float4 { 1.0, 1.0, 1.0, 1.0 };

fn shot(dev: hipgr::Device&, quad: hipgr::Mesh, mat: hipgr::Material,
        cam: hipgr::Camera) -> u8[4] {
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, quad, mat, hipgr::mat4_identity()), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    return verify::pixel(hipgr::frame_pixels(dev), SIZE, SIZE / 2, SIZE / 2);
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_ibl: no GPU device");
        return;
    }
    defer hipgr::close(dev);
    verify::expect(hipgr::quality(dev, hipgr::QUALITY_MODERN), "modern quality");
    // Fog would tint an unlit surface with the sky, which is exactly the value
    // the IBL-off check below has to see as zero.
    verify::expect(hipgr::set_fog(dev, 0.0), "fog off");

    let quad = hipgr::mesh_quad(dev);
    let cam = hipgr::camera_orthographic(float3 { 0.0, 0.0, 3.0 }, float3_0,
                                         float3 { 0.0, 1.0, 0.0 }, 2.0, 0.1, 10.0);
    // No direct light and no ambient: everything that is left is image-based.
    verify::expect(hipgr::set_light(dev, float3 { 0.0, 0.0, -1.0 }, float3_0, 0.0),
                   "light off");

    let mirror = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: WHITE, metallic: 1.0, roughness: 0.04,
    });
    verify::expect(mirror.id != 0, "mirror metal created");

    // --- the reflection takes the sky's colour ---------------------------------
    // A flat sky, so the only thing left for the reflection direction to decide
    // is whether it works at all. The quad faces the camera and the camera looks
    // down -Z, so the reflected view direction is +Z.
    let blue = float3 { 0.0, 0.0, 0.9 };
    verify::expect(hipgr::set_sky(dev, blue, blue), "blue sky set");
    let b = shot(dev, quad, mirror, cam);
    verify::expect(b[2] > 190, "a mirror metal reflects a blue sky as blue");
    verify::expect(b[0] < 10 && b[1] < 10, "and reflects nothing else");

    let red = float3 { 0.9, 0.0, 0.0 };
    verify::expect(hipgr::set_sky(dev, red, red), "red sky set");
    let r = shot(dev, quad, mirror, cam);
    verify::expect(r[0] > 190, "the same metal now reflects a red sky as red");
    verify::expect(r[2] < 10, "with no blue left over");

    // --- diffuse irradiance -----------------------------------------------------
    // A matte white surface under a constant sky receives that sky: 0.8 grey, no
    // direct light, ACES at exposure 1 lands at 224. A missing 1/PI, a missing
    // cosine weight, or a hemisphere integral that does not normalise all land
    // somewhere else, so this pins the value, not just its direction.
    let grey = float3 { 0.8, 0.8, 0.8 };
    verify::expect(hipgr::set_sky(dev, grey, grey), "grey sky set");
    let matte = hipgr::material_create(dev, hipgr::MaterialDesc { tint: WHITE, roughness: 1.0 });
    verify::expect(matte.id != 0, "matte white material created");
    let m = shot(dev, quad, matte, cam);
    verify::expect(verify::close_to(m[0], 224, 8), "irradiance of a constant sky is that sky");
    verify::expect(verify::close_to(m[1], m[0], 2) && verify::close_to(m[2], m[0], 2),
                   "and a grey sky lights it grey");

    verify::expect(hipgr::set_ibl(dev, 0.0), "ibl off");
    let unlit = shot(dev, quad, matte, cam);
    verify::expect(unlit[0] < 6, "with IBL off and no other light, a matte surface is black");
    verify::expect(hipgr::set_ibl(dev, 1.0), "ibl on");

    // A different sky colour is a different ambient light, not a constant.
    let green = float3 { 0.0, 0.6, 0.0 };
    verify::expect(hipgr::set_sky(dev, green, green), "green sky set");
    let g = shot(dev, quad, matte, cam);
    verify::expect(g[1] > 150 && g[0] < 20, "a green sky lights the surface green");

    // --- roughness blends the sky -----------------------------------------------
    // Red at the horizon, blue overhead, seen from below: the mirror points at the
    // zenith, and a fully rough metal gathers the horizon too. Prefiltering that
    // did nothing would leave the two identical.
    let horizon = float3 { 0.9, 0.0, 0.0 };
    let zenith = float3 { 0.0, 0.0, 0.9 };
    verify::expect(hipgr::set_sky(dev, horizon, zenith), "gradient sky set");
    let below = hipgr::camera_orthographic(float3 { 0.0, -3.0, 3.0 }, float3_0,
                                          float3 { 0.0, 1.0, 0.0 }, 2.0, 0.1, 10.0);
    let sharp = shot(dev, quad, mirror, below);
    verify::expect(sharp[2] > 190, "a mirror pointing at the zenith reflects it");
    verify::expect(sharp[0] < 40, "and only a little of the horizon");

    let dull = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: WHITE, metallic: 1.0, roughness: 1.0,
    });
    verify::expect(dull.id != 0, "rough metal created");
    let blurred = shot(dev, quad, dull, below);
    verify::expect(blurred[0] > sharp[0] + 30 && blurred[0] > 80,
                   "a rough metal gathers the horizon the mirror misses");
    verify::expect(blurred[2] < sharp[2] + 5, "and spreads the zenith out");

    // --- IBL off is 0.2, pixel for pixel -----------------------------------------
    // The fallback is the old constant ambient, not merely something similar: a
    // device with IBL off and the modern extras off has to match one that asked
    // for QUALITY_LINEAR outright.
    verify::expect(hipgr::set_tonemap(dev, hipgr::TONEMAP_NONE), "tonemap off");
    verify::expect(hipgr::set_bloom(dev, 0.0, 1.0), "bloom off");
    verify::expect(hipgr::set_shadows(dev, false), "shadows off");
    verify::expect(hipgr::set_sky_enabled(dev, false), "sky off");
    verify::expect(hipgr::set_light(dev, float3 { 0.0, 0.0, -1.0 }, float3_1, 0.25), "light on");
    verify::expect(hipgr::set_ibl(dev, 0.0), "ibl off");
    let ambient = shot(dev, quad, matte, cam);
    verify::expect(ambient[0] > 0, "the ambient term still lights the surface");
    verify::expect(hipgr::quality(dev, hipgr::QUALITY_LINEAR), "linear quality");
    let linear = shot(dev, quad, matte, cam);
    verify::expect(verify::same_color(ambient, linear, 0),
                   "IBL off matches QUALITY_LINEAR exactly");

    verify::pass("test_ibl");
}
