// 0.7 acceptance: a custom shader receives the scene's shadows.
//
// A floor drawn with a custom material that outputs white when the shadow map
// says lit and black when it says shadowed, a cube above it casting, and a light
// from above. Nothing in the material is HiPGR's own shading, so the pixels come
// from the documented blocks alone.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let CUSTOM_VS = embed_shader("shaders/test.vert");
let SHADOW_FS = embed_shader("shaders/test_shadow_receive.frag");

let SIZE: i64 = 128;

fn camera() -> hipgr::Camera {
    hipgr::camera_look_at(float3 { 0.0, 5.0, 7.0 }, float3 { 0.0, 0.0, 0.0 },
                          float3 { 0.0, 1.0, 0.0 }, 0.8)
}

// The floor: a quad turned horizontal, one unit below the origin.
fn floor_model() -> hipgr::Mat4 {
    hipgr::mat4_mul(hipgr::mat4_translate(float3 { 0.0, -1.0, 0.0 }),
                    hipgr::mat4_mul(hipgr::mat4_rotate(float3 { 1.0, 0.0, 0.0 }, -1.5707963),
                                    hipgr::mat4_scale(float3 { 6.0, 6.0, 1.0 })))
}

fn render(dev: hipgr::Device&, floor: hipgr::Mesh, mat: hipgr::Material,
          caster: hipgr::Mesh, caster_mat: hipgr::Material, cast: bool) -> u8[>..] {
    // A mid-grey clear: white means lit and black means shadowed, so the
    // background must be neither.
    verify::expect(hipgr::begin_frame(dev, camera(), float4 { 0.5, 0.5, 0.5, 1.0 }),
                   "frame begins");
    verify::expect(hipgr::draw(dev, floor, mat, floor_model()), "floor draw");
    if cast {
        verify::expect(hipgr::draw(dev, caster, caster_mat,
                                   hipgr::mat4_translate(float3 { 0.0, 0.2, 0.0 })),
                       "caster draw");
    }
    verify::expect(hipgr::end_frame(dev), "frame ends");
    return hipgr::frame_pixels(dev);
}

fn count_dark(px: const u8[:]) -> i64 {
    var n = 0;
    var i = 0;
    while i + 3 < px.len {
        if px[i] < 40 { n++; }
        i += 4;
    }
    return n;
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_custom_shadows: no GPU device");
        return;
    }
    defer hipgr::close(dev);
    // Linear output: the shader writes 0 or 1, so the pixel is 0 or 255.
    verify::expect(hipgr::quality(dev, hipgr::QUALITY_LINEAR), "linear quality accepted");
    verify::expect(hipgr::set_shadows(dev, true), "shadows on");
    verify::expect(hipgr::set_shadow_area(dev, float3_0, 6.0), "shadow area set");
    verify::expect(hipgr::set_light(dev, float3 { 0.15, -1.0, 0.25 }, float3_1, 0.2),
                   "light set");

    let floor = hipgr::mesh_quad(dev);
    let caster = hipgr::mesh_cube(dev);
    let shader = hipgr::shader_create(dev, CUSTOM_VS, SHADOW_FS);
    verify::expect(shader.id != 0, "shadow-receiving shader created");
    let mat = hipgr::material_create(dev, hipgr::MaterialDesc {
        shader: shader, use_shadow_map: true });
    verify::expect(mat.id != 0, "material that receives shadows created");
    // The caster only has to write depth: the built-in pair is fine for that.
    let caster_mat = hipgr::material_solid(dev, float4 { 0.5, 0.5, 0.5, 1.0 }, true);

    // --- lit floor -------------------------------------------------------------
    let lit_px = render(dev, floor, mat, caster, caster_mat, false);
    verify::expect(verify::count_color(lit_px, [255, 255, 255, 255], 2) > 2000,
                   "the floor is lit without a caster");
    verify::expect(count_dark(lit_px) < 10, "and nothing on it is shadowed");

    // --- with the caster -------------------------------------------------------
    let shadowed_px = render(dev, floor, mat, caster, caster_mat, true);
    let dark = count_dark(shadowed_px);
    verify::expect(dark > 150,
                   "a custom shader sees the shadow the caster throws on the floor");
    // The shadow is a patch, not the whole frame: the lit floor is still lit.
    verify::expect(verify::count_color(shadowed_px, [255, 255, 255, 255], 2) > 2000,
                   "the rest of the floor stays lit");

    // --- the shadow goes away with the switch ----------------------------------
    verify::expect(hipgr::set_shadows(dev, false), "shadows off");
    let unshadowed_px = render(dev, floor, mat, caster, caster_mat, true);
    verify::expect(count_dark(unshadowed_px) < 10,
                   "with the shadow pass off the custom shader sees no shadow");
    verify::expect(hipgr::set_shadows(dev, true), "shadows back on");

    // --- the light moves the shadow --------------------------------------------
    verify::expect(hipgr::set_light(dev, float3 { -0.9, -1.0, 0.1 }, float3_1, 0.2),
                   "light moved");
    let moved_px = render(dev, floor, mat, caster, caster_mat, true);
    verify::expect(verify::count_different(moved_px, shadowed_px) > dark / 2,
                   "moving the light moves the shadow the shader receives");

    // --- only a custom shader can ask ------------------------------------------
    let builtin = hipgr::material_create(dev, hipgr::MaterialDesc { use_shadow_map: true });
    verify::expect(builtin.id == 0,
                   "the built-in pair refuses a shadow map it already has");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_ARGUMENT, "shadow map error code");

    verify::pass("test_custom_shadows");
}
