// 0.3 acceptance: the shadow map.
//
// A cube floats in front of a lit wall, the light comes in at an angle, and the
// shadow lands beside the cube where it can be seen. Turning shadows off must
// leave the wall uniformly lit; moving the light must move the shadow to the
// other side.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 64;

// World to pixel for an orthographic camera seeing x, y in -1..1.
fn pixel_x(world_x: f32) -> i64 { return ((world_x + 1.0) * 0.5 * SIZE) as i64; }

fn pixel_y(world_y: f32) -> i64 { return ((1.0 - world_y) * 0.5 * SIZE) as i64; }

fn shot(dev: hipgr::Device&, wall: hipgr::Mesh, cube: hipgr::Mesh,
        mat: hipgr::Material, cam: hipgr::Camera, cube_model: hipgr::Mat4) -> u8[>..] {
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, wall, mat, hipgr::mat4_scale(float3 { 2.0, 2.0, 1.0 })),
                   "wall draw succeeds");
    verify::expect(hipgr::draw(dev, cube, mat, cube_model), "cube draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    return hipgr::frame_pixels(dev);
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_shadows: no GPU device");
        return;
    }
    defer hipgr::close(dev);
    // Linear output, but with shadows: only the depth pass is under test here.
    hipgr::quality(dev, hipgr::QUALITY_LINEAR);
    verify::expect(hipgr::set_shadows(dev, true), "shadows on");

    let wall = hipgr::mesh_quad(dev);
    let cube = hipgr::mesh_cube(dev);
    let mat = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4_1, roughness: 1.0,
    });
    verify::expect(mat.id != 0, "material created");

    let cam = hipgr::camera_orthographic(float3 { 0.0, 0.0, 3.0 }, float3_0,
                                         float3 { 0.0, 1.0, 0.0 }, 2.0, 0.1, 10.0);
    // A cube floating in front of the wall, off to one side and small enough
    // that its shadow reaches past its own silhouette.
    let cube_model = hipgr::mat4_mul(hipgr::mat4_translate(float3 { 0.45, 0.45, 0.5 }),
                                     hipgr::mat4_scale(float3 { 0.4, 0.4, 0.4 }));

    // Two spots on the wall: A is behind the cube seen from this light, B is on
    // the far side, clear of both the cube and its shadow.
    let ax = pixel_x(0.12);
    let ay = pixel_y(0.12);
    let bx = pixel_x(0.7);
    let by = pixel_y(0.2);

    // --- shadows off: the whole wall is lit the same --------------------------
    verify::expect(hipgr::set_shadows(dev, false), "shadows off");
    // From behind the camera, angled down and to the left.
    verify::expect(hipgr::set_light(dev, float3 { -0.3, -0.3, -1.0 }, float3_1, 0.2),
                   "light set");
    let without = shot(dev, wall, cube, mat, cam, cube_model);
    let a_off = verify::pixel(without, SIZE, ax, ay);
    let b_off = verify::pixel(without, SIZE, bx, by);
    verify::expect_eq(a_off[0], 255, "unshadowed, spot A is fully lit");
    verify::expect_eq(b_off[0], 255, "unshadowed, spot B is fully lit");

    // --- shadows on: A falls into the shadow, B stays lit ---------------------
    verify::expect(hipgr::set_shadows(dev, true), "shadows on again");
    let with = shot(dev, wall, cube, mat, cam, cube_model);
    let a_on = verify::pixel(with, SIZE, ax, ay);
    let b_on = verify::pixel(with, SIZE, bx, by);
    verify::expect(a_on[0] < 100, "the cube shadows the wall behind it");
    verify::expect(a_on[0] > 20, "a shadow keeps the ambient term, it is not black");
    verify::expect_eq(b_on[0], 255, "the wall outside the shadow stays lit");
    // Same geometry, same light: only the shadow changed.
    verify::expect(a_on[0] < a_off[0], "the shadow darkens spot A");

    // --- move the light: the shadow moves -------------------------------------
    verify::expect(hipgr::set_light(dev, float3 { 0.6, -0.6, -1.0 }, float3_1, 0.2),
                   "light moved to the other side");
    let moved = shot(dev, wall, cube, mat, cam, cube_model);
    let a_moved = verify::pixel(moved, SIZE, ax, ay);
    let b_moved = verify::pixel(moved, SIZE, bx, by);
    // The wall is dimmer under this light, because it comes in at a slant.
    verify::expect(a_moved[0] > 200, "spot A is lit again once the light moves");
    verify::expect(b_moved[0] < 100, "spot B is now in the shadow");
    verify::expect(b_moved[0] < b_off[0], "the moved shadow darkens spot B");

    verify::pass("test_shadows");
}
