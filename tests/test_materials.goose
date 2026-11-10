// 0.2 acceptance: materials are data.
//
//   * three distinct materials — textured, solid, and one with a custom shader —
//     render in the same frame, lit by a directional and a point light;
//   * MaterialDesc makes a wireframe and an alpha-blended material, and both
//     actually change what is drawn;
//   * identical state shares one pipeline, and different state does not;
//   * culling is decided by the material, not by the renderer.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

// Embedded by this program, written against the documented shader contract.
let CUSTOM_VS = embed_shader("shaders/test.vert");
let CUSTOM_FS = embed_shader("shaders/test_user0.frag");

let SIZE: i64 = 128;
let CLEAR: u8[4] = [0, 0, 0, 255];

fn camera() -> hipgr::Camera {
    hipgr::camera_look_at(float3 { 0.0, 0.0, 4.0 }, float3_0, float3 { 0.0, 1.0, 0.0 }, 0.9)
}

// Counts pixels that are not the clear colour: how much of the screen a draw
// covered.
fn coverage(px: const u8[:]) -> i64 {
    var n = 0;
    var i = 0;
    while i + 3 < px.len {
        if px[i] > 6 || px[i + 1] > 6 || px[i + 2] > 6 { n++; }
        i += 4;
    }
    return n;
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_materials: no GPU device");
        return;
    }
    defer hipgr::close(dev);

    let cube = hipgr::mesh_cube(dev);
    let quad = hipgr::mesh_quad(dev);
    let img = hipgr::image_checker(dev, 64, 8, [40, 40, 60, 255], [220, 200, 120, 255]);

    // --- three materials, two light kinds, one frame ---------------------------
    let textured = hipgr::material_textured(dev, img, float4_1, true);
    let solid = hipgr::material_solid(dev, float4 { 0.1, 0.4, 0.9, 1.0 }, true);
    let shader = hipgr::shader_create(dev, CUSTOM_VS, CUSTOM_FS);
    verify::expect(shader.id != 0, "custom shader pair created");
    let custom = hipgr::material_create(dev, hipgr::MaterialDesc {
        shader: shader,
        user0: float4 { 0.0, 1.0, 0.0, 0.0 },
        user1: float4 { 0.0, 0.0, 0.0, 1.0 },
    });
    verify::expect(custom.id != 0, "custom material created");

    verify::expect(hipgr::set_light(dev, float3 { 0.0, 0.0, -1.0 }, float3_1, 0.2),
                   "directional light set");
    verify::expect(hipgr::set_point_light(dev, 0, float3 { -1.4, 0.4, 1.2 },
                                          float3 { 0.3, 0.3, 0.3 }, 4.0),
                   "point light set");
    verify::expect_eq(hipgr::point_light_count(dev), 1, "one point light");

    verify::expect(hipgr::begin_frame(dev, camera(), float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, cube, textured,
                               hipgr::mat4_trs(float3 { -1.3, 0.0, 0.0 }, float3 { 0.0, 1.0, 0.0 },
                                               0.3, float3 { 1.0, 1.0, 1.0 })),
                   "textured draw");
    verify::expect(hipgr::draw(dev, cube, solid, hipgr::mat4_translate(float3 { 0.0, 0.0, 0.0 })),
                   "solid draw");
    verify::expect(hipgr::draw(dev, cube, custom,
                               hipgr::mat4_translate(float3 { 1.3, 0.0, 0.0 })),
                   "custom draw");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    let px = hipgr::frame_pixels(dev);

    verify::expect(verify::count_color(px, [40, 40, 60, 255], 4) > 100,
                   "textured material shows the texture");
    verify::expect(verify::count_color(px, [220, 200, 120, 255], 4) > 100,
                   "textured material shows both checker colours");
    // 0.1, 0.4, 0.9 unlit, with no conversion in between: 26, 102, 230.
    verify::expect(verify::count_color(px, [26, 102, 230, 255], 6) > 100,
                   "solid material shows its tint");
    // The custom shader writes user0 untouched: 0, 255, 0.
    verify::expect(verify::count_color(px, [0, 255, 0, 255], 3) > 100,
                   "custom shader receives Material.user0");

    // --- pipeline sharing -------------------------------------------------------
    let before = hipgr::stats(dev).pipelines;
    let a = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4 { 1.0, 0.0, 0.0, 1.0 }, cull: hipgr::CULL_BACK });
    let b = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4 { 0.0, 1.0, 0.0, 1.0 }, cull: hipgr::CULL_BACK });
    verify::expect(a.id != 0 && b.id != 0, "two materials created");
    verify::expect_eq(hipgr::stats(dev).pipelines, before,
                      "identical material state shares one pipeline");
    let blended = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4 { 0.0, 0.0, 1.0, 0.5 }, blend: hipgr::BLEND_ALPHA,
        depth_write: false });
    verify::expect(blended.id != 0, "alpha material created");
    verify::expect_eq(hipgr::stats(dev).pipelines, before + 1,
                      "different state makes a different pipeline");

    // --- wireframe --------------------------------------------------------------
    let filled = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4 { 1.0, 1.0, 1.0, 1.0 }, unlit: true });
    let wire = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4 { 1.0, 1.0, 1.0, 1.0 }, unlit: true, wireframe: true });
    verify::expect(filled.id != 0 && wire.id != 0, "wireframe material created");

    verify::expect(hipgr::begin_frame(dev, camera(), float4_0), "filled frame begins");
    verify::expect(hipgr::draw(dev, cube, filled, hipgr::mat4_identity()), "filled draw");
    verify::expect(hipgr::end_frame(dev), "filled frame ends");
    let filled_count = coverage(hipgr::frame_pixels(dev));

    verify::expect(hipgr::begin_frame(dev, camera(), float4_0), "wire frame begins");
    verify::expect(hipgr::draw(dev, cube, wire, hipgr::mat4_identity()), "wire draw");
    verify::expect(hipgr::end_frame(dev), "wire frame ends");
    let wire_count = coverage(hipgr::frame_pixels(dev));

    verify::expect(wire_count > 50, "wireframe still draws something");
    verify::expect(wire_count * 3 < filled_count,
                   "wireframe draws far fewer pixels than a filled cube");

    // --- culling decides visibility --------------------------------------------
    let front_facing = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4 { 0.0, 1.0, 0.0, 1.0 }, unlit: true });
    let front_culled = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4 { 0.0, 1.0, 0.0, 1.0 }, unlit: true, cull: hipgr::CULL_FRONT });
    verify::expect(front_facing.id != 0 && front_culled.id != 0, "cull materials created");

    verify::expect(hipgr::begin_frame(dev, camera(), float4_0), "cull frame begins");
    verify::expect(hipgr::draw(dev, quad, front_facing, hipgr::mat4_identity()), "culled draw");
    verify::expect(hipgr::end_frame(dev), "cull frame ends");
    let culled_px = hipgr::frame_pixels(dev);
    verify::expect_not_pixel(culled_px, SIZE, SIZE / 2, SIZE / 2, CLEAR, 1,
                             "back-face culling keeps a front-facing quad");

    verify::expect(hipgr::begin_frame(dev, camera(), float4_0), "cull2 frame begins");
    verify::expect(hipgr::draw(dev, quad, front_culled, hipgr::mat4_identity()), "cull2 draw");
    verify::expect(hipgr::end_frame(dev), "cull2 frame ends");
    let gone_px = hipgr::frame_pixels(dev);
    verify::expect(verify::count_color(gone_px, CLEAR, 1) == SIZE * SIZE,
                   "CULL_FRONT removes the quad entirely");

    // --- alpha blending ---------------------------------------------------------
    let red = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4 { 1.0, 0.0, 0.0, 1.0 }, unlit: true });
    let half_blue = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4 { 0.0, 0.0, 1.0, 0.5 }, unlit: true, blend: hipgr::BLEND_ALPHA,
        depth_write: false });
    verify::expect(red.id != 0 && half_blue.id != 0, "blend materials created");

    verify::expect(hipgr::begin_frame(dev, camera(), float4_0), "blend frame begins");
    // A red background filling the screen, then a smaller blue quad in front of
    // it: same depth would fail the depth test, so it is moved towards the
    // camera. It covers the middle and not the corners.
    verify::expect(hipgr::draw(dev, quad, red, hipgr::mat4_scale(float3 { 6.0, 6.0, 1.0 })),
                   "background draw");
    verify::expect(hipgr::draw(dev, quad, half_blue,
                               hipgr::mat4_mul(hipgr::mat4_translate(float3 { 0.0, 0.0, 0.5 }),
                                               hipgr::mat4_scale(float3 { 0.8, 0.8, 1.0 }))),
                   "blended draw");
    verify::expect(hipgr::end_frame(dev), "blend frame ends");
    let blend_px = hipgr::frame_pixels(dev);
    // 50% blue over red is half of each: 128, 0, 128. A shader that ignored the
    // blend state would leave 0, 0, 255.
    verify::expect_pixel(blend_px, SIZE, SIZE / 2, SIZE / 2, [128, 0, 128, 255], 6,
                         "alpha blend mixes with what is behind it");
    verify::expect_pixel(blend_px, SIZE, 4, 4, [255, 0, 0, 255], 6,
                         "the opaque background is untouched at the edge");

    // --- bad state is rejected ---------------------------------------------------
    let bad = hipgr::material_create(dev, hipgr::MaterialDesc { cull: 7 });
    verify::expect(bad.id == 0, "an unknown cull mode is rejected");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_ARGUMENT, "cull error code");

    verify::pass("test_materials");
}
