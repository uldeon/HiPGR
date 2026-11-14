// 0.8 acceptance: two shadow cascades that follow the camera.
//
// Three properties, each measured in pixels:
//
//   1. Inside both boxes, cascades change nothing a single box already got.
//   2. With the camera moved 60 units away, the single box keeps no shadow at
//      all and the cascades keep one: they follow the camera.
//   3. Both maps are really used: shrink the near range and the same caster,
//      now only in the far box, still casts.
//
// The scene is a big lit floor, a flat caster above it, and a light that is
// slanted enough that the shadow lands beside the caster instead of under it.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 192;

fn floor_at(center: float3) -> hipgr::Mat4 {
    hipgr::mat4_mul(hipgr::mat4_translate(center),
                    hipgr::mat4_mul(hipgr::mat4_rotate(float3 { 1.0, 0.0, 0.0 }, 1.5707963),
                                    hipgr::mat4_scale(float3 { 40.0, 40.0, 1.0 })))
}

fn caster_at(at: float3) -> hipgr::Mat4 {
    hipgr::mat4_mul(hipgr::mat4_translate(at), hipgr::mat4_scale(float3 { 2.0, 2.0, 1.0 }))
}

// Pixels of the floor that are in shadow: lit floor is 255 under this light,
// shadowed floor keeps only the ambient term, and the clear colour is mid-grey.
fn count_dark(px: const u8[:]) -> i64 {
    var n = 0;
    var i = 0;
    while i + 3 < px.len {
        if px[i] as i64 < 60 && px[i + 1] as i64 < 60 && px[i + 2] as i64 < 60 { n++; }
        i += 4;
    }
    return n;
}

fn shot(dev: hipgr::Device&, cam: hipgr::Camera, floor: hipgr::Mesh, mat: hipgr::Material,
        caster: hipgr::Mesh, cmat: hipgr::Material, floor_center: float3,
        at: float3) -> u8[>..] {
    verify::expect(hipgr::begin_frame(dev, cam, float4 { 0.5, 0.5, 0.5, 1.0 }), "frame begins");
    verify::expect(hipgr::draw(dev, floor, mat, floor_at(floor_center)), "floor draw");
    verify::expect(hipgr::draw(dev, caster, cmat, caster_at(at)), "caster draw");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    return hipgr::frame_pixels(dev);
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_cascades: no GPU device");
        return;
    }
    defer hipgr::close(dev);
    verify::expect(hipgr::quality(dev, hipgr::QUALITY_LINEAR), "linear quality accepted");
    verify::expect(hipgr::set_shadows(dev, true), "shadows on");
    verify::expect(hipgr::set_light(dev, float3 { 0.8, -1.0, 0.45 }, float3_1, 0.08),
                   "light set");

    let floor = hipgr::mesh_quad(dev);
    let caster = hipgr::mesh_cube(dev);
    let mat = hipgr::material_create(dev, hipgr::MaterialDesc { roughness: 1.0,
                                                               cull: hipgr::CULL_NONE });
    let cmat = hipgr::material_solid(dev, float4 { 0.8, 0.8, 0.8, 1.0 }, true);
    let cam = hipgr::camera_look_at(float3 { 0.0, 20.0, 12.0 }, float3 { 0.0, 0.0, -14.0 },
                                    float3 { 0.0, 1.0, 0.0 }, 1.2);
    let home = float3 { 0.0, -1.0, 0.0 };
    let in_view = float3 { 0.0, 4.0, -10.0 };

    // --- one box, for comparison ------------------------------------------------
    verify::expect_eq(hipgr::shadow_mode(dev), hipgr::SHADOW_FIXED,
                      "a device starts with one fixed box");
    verify::expect(hipgr::set_shadow_area(dev, float3_0, 30.0), "fixed area set");
    let f0 = hipgr::stats(dev).shadow_batches;
    let fixed_px = shot(dev, cam, floor, mat, caster, cmat, home, in_view);
    let fixed_dark = count_dark(fixed_px);
    let fixed_batches = hipgr::stats(dev).shadow_batches - f0;

    // --- two cascades ----------------------------------------------------------
    verify::expect(hipgr::set_shadow_cascades(dev, 30.0, 120.0), "cascades accepted");
    verify::expect_eq(hipgr::shadow_mode(dev), hipgr::SHADOW_CASCADES, "mode is cascades");
    verify::expect(hipgr::shadow_near_range(dev) == 30.0, "near range reads back");
    verify::expect(hipgr::shadow_far_range(dev) == 120.0, "far range reads back");
    let c0 = hipgr::stats(dev).shadow_batches;
    let casc_px = shot(dev, cam, floor, mat, caster, cmat, home, in_view);
    let casc_dark = count_dark(casc_px);
    let casc_batches = hipgr::stats(dev).shadow_batches - c0;

    verify::expect(fixed_dark > 30, "the fixed box shadows the caster");
    verify::expect(casc_dark > 30, "the cascades shadow it too");
    // Same shadow, not a different one: the near cascade covers this caster at
    // half the box size, so the patch is within a few percent of the same size.
    let bigger = if casc_dark > fixed_dark { casc_dark } else { fixed_dark };
    let smaller = if casc_dark > fixed_dark { fixed_dark } else { casc_dark };
    verify::expect(bigger - smaller <= bigger / 4, "and the patch is about the same size");
    // One draw per cascade, and the shadow pass counts both.
    verify::expect_eq(casc_batches, fixed_batches * 2, "both cascades run their own pass");
    verify::expect(casc_batches >= 4, "with the floor and the caster, that is two each");

    // --- the camera moves, the shadows follow ----------------------------------
    let far_cam = hipgr::camera_look_at(float3 { 0.0, 20.0, 72.0 }, float3 { 0.0, 0.0, 46.0 },
                                        float3 { 0.0, 1.0, 0.0 }, 1.2);
    let away = float3 { 0.0, -1.0, 60.0 };
    let near_away = float3 { 0.0, 4.0, 50.0 };
    let moved_casc = count_dark(shot(dev, far_cam, floor, mat, caster, cmat, away, near_away));
    verify::expect(moved_casc > 50, "cascades shadow the scene where the camera now is");

    verify::expect(hipgr::set_shadow_area(dev, float3_0, 30.0), "back to one box");
    let moved_fixed = count_dark(shot(dev, far_cam, floor, mat, caster, cmat, away, near_away));
    verify::expect(moved_fixed < 10,
                   "the single box, still at the origin, loses the shadow entirely");

    // --- both maps are used ----------------------------------------------------
    // With a 5-unit near range this caster is only in the far box, so a shadow
    // here means the far pass rendered and the shader sampled it.
    verify::expect(hipgr::set_shadow_cascades(dev, 5.0, 120.0), "narrow near range accepted");
    let only_far = count_dark(shot(dev, cam, floor, mat, caster, cmat, home, in_view));
    verify::expect(only_far > 20, "a caster only the far cascade holds still casts");

    // --- the switch ------------------------------------------------------------
    verify::expect(!hipgr::set_shadow_cascades(dev, 20.0, 10.0), "far below near is refused");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_ARGUMENT, "range error code");
    verify::expect(!hipgr::set_shadow_cascades(dev, 0.0, 10.0), "a zero near range is refused");
    verify::expect(!hipgr::set_shadow_cascades(dev, 10.0, 600.0), "a far range past 512 is refused");
    verify::expect_eq(hipgr::shadow_mode(dev), hipgr::SHADOW_CASCADES,
                      "a refused change leaves the mode alone");

    verify::pass("test_cascades");
}
