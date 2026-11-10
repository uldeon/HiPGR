// 0.2 acceptance: two kinds of light.
//
// A directional light and up to MAX_POINT_LIGHTS point lights light the same
// surface. The tests separate them: with a black directional colour only point
// lights contribute, so their falloff and radius can be measured directly.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 64;

fn camera() -> hipgr::Camera {
    hipgr::camera_look_at(float3 { 0.0, 0.0, 4.0 }, float3_0, float3 { 0.0, 1.0, 0.0 }, 0.9)
}

// The centre of the quad: a point on a surface facing +Z at the origin.
fn centre(dev: hipgr::Device&) -> u8[4] {
    return verify::pixel(hipgr::frame_pixels(dev), SIZE, SIZE / 2, SIZE / 2);
}

fn render_once(dev: hipgr::Device&, quad: hipgr::Mesh, mat: hipgr::Material,
               cam: hipgr::Camera) -> u8[4] {
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, quad, mat, hipgr::mat4_identity()), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    return centre(dev);
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_lights: no GPU device");
        return;
    }
    defer hipgr::close(dev);

    let quad = hipgr::mesh_quad(dev);
    let mat = hipgr::material_solid(dev, float4_1, false);
    verify::expect(mat.id != 0, "material created");
    let cam = camera();

    // --- directional only -----------------------------------------------------
    // Travels towards -Z, so it hits the quad's +Z face head on.
    verify::expect(hipgr::set_light(dev, float3 { 0.0, 0.0, -1.0 }, float3_1, 0.0),
                   "directional light set");
    let lit = render_once(dev, quad, mat, cam);
    verify::expect(verify::close_to(lit[0], 255, 4), "a head-on directional light is full brightness");

    // Black directional colour: nothing but point lights can light the scene.
    verify::expect(hipgr::set_light(dev, float3 { 0.0, 0.0, -1.0 }, float3_0, 0.0),
                   "directional light switched off");
    let dark = render_once(dev, quad, mat, cam);
    verify::expect(verify::close_to(dark[0], 0, 2), "a black directional light contributes nothing");

    // --- one point light ------------------------------------------------------
    // At (0, 0, 2), two units in front of the quad, radius 10: attenuation is
    // (1 - 4/100)^2 = 0.9216, so the face renders at about 235.
    verify::expect(hipgr::set_point_light(dev, 0, float3 { 0.0, 0.0, 2.0 }, float3_1, 10.0),
                   "point light set");
    let one = render_once(dev, quad, mat, cam);
    verify::expect(verify::close_to(one[0], 235, 5), "a point light falls off with distance");
    verify::expect(one[0] > 200, "a near point light lights the face");

    // A second light adds to the first.
    verify::expect(hipgr::set_point_light(dev, 1, float3 { 0.0, 0.0, 2.0 }, float3_1, 10.0),
                   "second point light set");
    verify::expect_eq(hipgr::point_light_count(dev), 2, "two point lights");
    let two = render_once(dev, quad, mat, cam);
    verify::expect(two[0] > one[0], "two point lights are brighter than one");

    // --- radius clips the light out ------------------------------------------
    hipgr::clear_point_lights(dev);
    verify::expect_eq(hipgr::point_light_count(dev), 0, "no point lights left");
    let cleared = render_once(dev, quad, mat, cam);
    verify::expect(verify::close_to(cleared[0], 0, 2), "clearing the lights darkens the face");

    // Ten units away with a radius of two: outside its reach, so no light.
    verify::expect(hipgr::set_point_light(dev, 0, float3 { 0.0, 0.0, 10.0 }, float3_1, 2.0),
                   "distant point light set");
    let unreached = render_once(dev, quad, mat, cam);
    verify::expect(verify::close_to(unreached[0], 0, 2),
                   "a point light beyond its radius contributes nothing");

    // --- arguments ------------------------------------------------------------
    verify::expect(!hipgr::set_point_light(dev, 0, float3_0, float3_1, 0.0),
                   "a zero radius is rejected");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_ARGUMENT, "radius error code");
    verify::expect(!hipgr::set_point_light(dev, hipgr::MAX_POINT_LIGHTS, float3_0, float3_1, 1.0),
                   "a light index past the limit is rejected");
    verify::expect(!hipgr::set_light(dev, float3_0, float3_1, 0.2),
                   "a zero light direction is rejected");

    verify::pass("test_lights");
}
