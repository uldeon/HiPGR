// 0.7 acceptance: a custom material samples its own textures.
//
// The shader multiplies the texture in slot 0 by the red of the one in slot 1.
// Three solid textures make every expectation exact and every slot identifiable:
//
//   slot 0 = A (200, 100, 50), slot 1 = B (128, 128, 128)  -> A * 0.502 = 100, 50, 25
//   slot 1 unset (white)                                   -> A * 1.000 = 200, 100, 50
//   slot 0 = B, slot 1 = A                                 -> B * A.r   = 100, 100, 100
//
// The second line also proves the default: an unset slot is a white texel, so a
// shader that samples one before the application binds anything is unaffected.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let CUSTOM_VS = embed_shader("shaders/test.vert");
let TEXTURE_FS = embed_shader("shaders/test_texture.frag");

let SIZE: i64 = 96;

fn camera() -> hipgr::Camera {
    hipgr::camera_look_at(float3 { 0.0, 0.0, 4.0 }, float3_0, float3 { 0.0, 1.0, 0.0 }, 0.9)
}

// A texture that is one colour, so bilinear sampling returns it exactly.
fn solid(dev: hipgr::Device&, r: u8, g: u8, b: u8) -> hipgr::Image {
    var px: u8[>..] = [];
    px.resize(4 * 4 * 4, 0);
    for i in 16 {
        px[i * 4] = r;
        px[i * 4 + 1] = g;
        px[i * 4 + 2] = b;
        px[i * 4 + 3] = 255;
    }
    let bytes = px[..];
    return hipgr::image_rgba8(dev, 4, 4, bytes);
}

fn render(dev: hipgr::Device&, quad: hipgr::Mesh, mat: hipgr::Material) -> u8[>..] {
    verify::expect(hipgr::begin_frame(dev, camera(), float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, quad, mat, hipgr::mat4_identity()), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    return hipgr::frame_pixels(dev);
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_custom_textures: no GPU device");
        return;
    }
    defer hipgr::close(dev);
    verify::expect(hipgr::quality(dev, hipgr::QUALITY_LINEAR), "linear quality accepted");

    let quad = hipgr::mesh_quad(dev);
    let a = solid(dev, 200, 100, 50);
    let b = solid(dev, 128, 128, 128);
    verify::expect(a.id != 0 && b.id != 0, "textures created");

    let shader = hipgr::shader_create(dev, CUSTOM_VS, TEXTURE_FS);
    verify::expect(shader.id != 0, "custom shader with two samplers created");

    // --- both slots ------------------------------------------------------------
    let mat = hipgr::material_create(dev, hipgr::MaterialDesc {
        shader: shader, texture_count: 2 });
    verify::expect(mat.id != 0, "material with two texture slots created");
    verify::expect(hipgr::set_material_texture(dev, mat, 0, a), "slot 0 bound");
    verify::expect(hipgr::set_material_texture(dev, mat, 1, b), "slot 1 bound");
    verify::expect_eq(hipgr::material_texture(dev, mat, 1).id, b.id, "slot 1 reads back");

    let px0 = render(dev, quad, mat);
    verify::expect_pixel(px0, SIZE, SIZE / 2, SIZE / 2, [100, 50, 25, 255], 2,
                         "the shader samples both slots: slot 0 times slot 1's red");
    verify::expect(verify::count_color(px0, [100, 50, 25, 255], 2) > 400,
                   "and does so over the whole quad");

    // --- an unset slot is white ------------------------------------------------
    verify::expect(hipgr::set_material_texture(dev, mat, 1, hipgr::Image { 0 }),
                   "slot 1 unbound");
    let px1 = render(dev, quad, mat);
    verify::expect_pixel(px1, SIZE, SIZE / 2, SIZE / 2, [200, 100, 50, 255], 2,
                         "an unset slot samples white, so slot 0 passes through");

    // --- the slots are separate positions --------------------------------------
    verify::expect(hipgr::set_material_texture(dev, mat, 0, b), "slot 0 rebound");
    verify::expect(hipgr::set_material_texture(dev, mat, 1, a), "slot 1 rebound");
    let px2 = render(dev, quad, mat);
    // Swapping them changes the colour, which proves the order is the shader's
    // sampler order and not something HiPGR decides.
    verify::expect_pixel(px2, SIZE, SIZE / 2, SIZE / 2, [100, 100, 100, 255], 2,
                         "swapping the two slots gives a different colour");

    // --- the count has to match the shader -------------------------------------
    let too_many = hipgr::material_create(dev, hipgr::MaterialDesc {
        shader: shader, texture_count: hipgr::TEXTURE_SLOTS + 1 });
    verify::expect(too_many.id == 0, "a slot count past the fourth is refused");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_ARGUMENT, "count error code");

    let builtin_with_textures = hipgr::material_create(dev, hipgr::MaterialDesc {
        texture_count: 1 });
    verify::expect(builtin_with_textures.id == 0,
                   "the built-in shader refuses sampler slots that are HiPGR's");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_ARGUMENT, "builtin error code");

    let one_slot = hipgr::material_create(dev, hipgr::MaterialDesc {
        shader: shader, texture_count: 1 });
    verify::expect(one_slot.id != 0, "a material can declare fewer slots than the shader");
    verify::expect(!hipgr::set_material_texture(dev, one_slot, 1, a),
                   "writing past the declared count is refused");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_ARGUMENT, "slot error code");
    // A declared count that is lower than the shader's is a mistake the backend
    // catches on the draw itself ("reads sampler 1, which no bind_texture gave
    // it"), which stops the program: it is a programming error, not a recoverable
    // one, so it is documented rather than asserted here.

    hipgr::release(dev, a);
    verify::expect(!hipgr::set_material_texture(dev, mat, 0, a),
                   "a released image is refused");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_HANDLE, "image error code");

    verify::pass("test_custom_textures");
}
