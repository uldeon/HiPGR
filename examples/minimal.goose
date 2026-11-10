// HiPGR: the smallest useful program, and the README's example verbatim.
//
//   goose build examples/minimal.goose && examples/minimal
//   GOOSE_GFX_HEADLESS=1 examples/minimal --frames 10
//
// One mesh, one material, one light, one spinning object.
import std;
import os;
import vec;
import hipgr from "../src/hipgr";

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open(dev, "my app", 1280, 720) else {
        write_stderr(str("hipgr: ", hipgr::error_text(hipgr::error_code(dev)), "\n"));
        return;
    }
    defer hipgr::close(dev);              // releases whatever is still live

    let cube = hipgr::mesh_cube(dev);                       // mesh
    let img  = hipgr::image_checker(dev, 64, 8, [40, 40, 60, 255], [220, 200, 120, 255]);
    let mat  = hipgr::material_textured(dev, img, float4_1, false);   // material
    hipgr::set_light(dev, float3 { -0.4, -0.8, -0.6 }, float3_1, 0.25);

    let cam = hipgr::camera_look_at(float3 { 0.0, 0.8, 3.0 }, float3_0,
                                    float3 { 0.0, 1.0, 0.0 }, 0.8);

    var t: f32 = 0.0;
    while hipgr::begin_frame(dev, cam, float4 { 0.05, 0.06, 0.08, 1.0 }) {
        t += hipgr::delta_time() as! f32;
        hipgr::draw(dev, cube, mat, hipgr::mat4_spin(float3_0, t, 1.0));
        if !hipgr::end_frame(dev) { break; }     // false: window closed / quit
        if hipgr::key_pressed("Escape") { break; }
    }
}
