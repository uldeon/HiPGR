// 0.5 acceptance: the shadow pass is culled and instanced too.
//
// Two rules have to hold at once, and they pull in opposite directions:
//
//   * an object outside the *light's* box cannot contribute to the shadow map,
//     so skipping it must change no pixel;
//   * an object outside the *camera's* frustum can still cast a shadow into
//     view, so the camera's culling must not reach the shadow pass.
//
// The scene below has both: eight casters far outside the light's box, and one
// caster off to the side that the camera cannot see but whose shadow lands in
// the middle of the view. The frames with the optimisations off and on must be
// identical, the counters must show what was skipped, and turning shadows off
// must visibly change the image, which is what proves the shadows were there.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 96;

fn render(dev: hipgr::Device&, cam: hipgr::Camera, ground: hipgr::Mesh, cube: hipgr::Mesh,
          floor: hipgr::Material, mat: hipgr::Material, culling: bool, batching: bool,
          shadows: bool) -> u8[>..] {
    verify::expect(hipgr::set_culling(dev, culling), "culling switch accepted");
    verify::expect(hipgr::set_batching(dev, batching), "batching switch accepted");
    verify::expect(hipgr::set_shadows(dev, shadows), "shadow switch accepted");
    verify::expect(hipgr::begin_frame(dev, cam, float4 { 0.0, 0.0, 0.0, 1.0 }), "frame begins");

    // The receiver: a large horizontal quad at y = -1, unlit? No: lit, so a
    // shadow is the difference between the light and the ambient floor.
    let flat = hipgr::mat4_mul(hipgr::mat4_mul(hipgr::mat4_translate(float3 { 0.0, -1.0, 0.0 }),
                                               hipgr::mat4_rotate(float3 { 1.0, 0.0, 0.0 },
                                                                  -1.5707963)),
                               hipgr::mat4_scale(float3 { 60.0, 60.0, 60.0 }));
    verify::expect(hipgr::draw(dev, ground, floor, flat), "draw succeeds");

    // 40 casters over the ground, large enough that their shadows cover a good
    // part of the visible floor: the test is about which draws ran, and a
    // handful of shadowed pixels would be a weak check that they ran at all.
    for z in 5 {
        for x in 8 {
            let model = hipgr::mat4_trs(float3 { (x - 4) * 1.6, 1.0, (z - 2) * 1.6 },
                                        float3 { 0.0, 1.0, 0.0 }, 0.0,
                                        float3 { 1.4, 1.4, 1.4 });
            verify::expect(hipgr::draw(dev, cube, mat, model), "draw succeeds");
        }
    }
    // Outside the light's box entirely: no shadow, and nothing on screen.
    for i in 8 {
        let model = hipgr::mat4_trs(float3 { 100.0 + i, 0.0, 0.0 }, float3 { 0.0, 1.0, 0.0 },
                                    0.0, float3 { 0.7, 0.7, 0.7 });
        verify::expect(hipgr::draw(dev, cube, mat, model), "draw succeeds");
    }
    // The off-screen caster: the camera cannot see it, the light can, and with
    // a light travelling (-1, -0.5, 0.2) its shadow falls near x = 3, on screen.
    let offscreen = hipgr::mat4_trs(float3 { 11.0, 4.0, 0.0 }, float3 { 0.0, 1.0, 0.0 }, 0.0,
                                    float3 { 1.2, 1.2, 1.2 });
    verify::expect(hipgr::draw(dev, cube, mat, offscreen), "draw succeeds");

    verify::expect(hipgr::end_frame(dev), "frame ends");
    return hipgr::frame_pixels(dev);
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_shadow_batches: no GPU device");
        return;
    }
    defer hipgr::close(dev);
    verify::expect(hipgr::quality(dev, hipgr::QUALITY_MODERN), "modern quality accepted");
    // Only the shadow map matters here: no bloom, no fog, no sky, and no tone
    // curve, so a shadowed pixel is darker purely because the light was blocked.
    verify::expect(hipgr::set_bloom(dev, 0.0, 1.0), "bloom off");
    verify::expect(hipgr::set_fog(dev, 0.0), "fog off");
    verify::expect(hipgr::set_sky_enabled(dev, false), "sky off");
    verify::expect(hipgr::set_tonemap(dev, hipgr::TONEMAP_NONE), "tonemap none");
    verify::expect(hipgr::set_ibl(dev, 0.0), "ibl off");

    let ground = hipgr::mesh_quad(dev);
    let cube = hipgr::mesh_cube(dev);
    // CULL_NONE on the receiver: it is rotated onto the ground plane and its
    // winding is not what this test is about.
    let floor = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4 { 0.9, 0.9, 0.9, 1.0 },
        cull: hipgr::CULL_NONE,
    });
    let mat = hipgr::material_solid(dev, float4 { 0.8, 0.5, 0.3, 1.0 }, false);
    let light = float3 { -1.0, -0.5, 0.2 };
    verify::expect(hipgr::set_light(dev, light, float3_1, 0.2), "light set");
    verify::expect(hipgr::set_shadow_area(dev, float3_0, 12.0), "shadow area set");

    let cam = hipgr::camera_perspective(float3 { 0.0, 8.0, 16.0 }, float3_0,
                                        float3 { 0.0, 1.0, 0.0 }, 0.8, 0.1, 80.0);

    // --- the unoptimised path ---
    let b0 = hipgr::stats(dev);
    let plain = render(dev, cam, ground, cube, floor, mat, false, false, true);
    let s0 = hipgr::stats(dev);
    // 50 casters (the receiver casts too), and one shadow batch each.
    verify::expect_eq(s0.shadow_batches - b0.shadow_batches, 50,
                      "unbatched: the shadow pass submits a draw per caster");
    verify::expect_eq(s0.shadow_culled - b0.shadow_culled, 0,
                      "unculled: the shadow pass skips nothing");

    // --- the optimised path ---
    let b1 = hipgr::stats(dev);
    let optimised = render(dev, cam, ground, cube, floor, mat, true, true, true);
    let s1 = hipgr::stats(dev);
    // The eight far casters leave the light's box; the off-screen one stays,
    // because the light can see it.
    verify::expect_eq(s1.shadow_culled - b1.shadow_culled, 8,
                      "exactly the casters outside the light's box are skipped");
    // Two meshes: the receiver, then one instanced draw for every cube.
    verify::expect_eq(s1.shadow_batches - b1.shadow_batches, 2,
                      "batched: one draw per mesh, not per caster");
    verify::expect_eq(s1.shadow_instances - b1.shadow_instances, 41,
                      "41 casters are instanced");
    // The camera, unlike the light, cannot see the off-screen caster.
    verify::expect(s1.culled - b1.culled >= 9, "the camera culls the off-screen objects");
    verify::expect_eq(verify::count_different(plain, optimised), 0,
                      "culling and instancing the shadow pass changes no pixel");

    // --- the shadows are really there ---
    let no_shadow = render(dev, cam, ground, cube, floor, mat, true, true, false);
    let changed = verify::count_different(optimised, no_shadow);
    verify::expect(changed > 400, "the shadow map darkens the ground");
    // Including the shadow of the object the camera cannot see: the frame with
    // culling on has the same shadow the frame with culling off had, and both
    // differ from the frame with no shadows at all.
    verify::expect_eq(verify::count_different(plain, no_shadow), changed,
                      "the off-screen caster casts the same shadow either way");

    verify::pass("test_shadow_batches");
}
