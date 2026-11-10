// HiPGR example: the smallest complete program.
//
// A window (or, with GOOSE_GFX_HEADLESS=1, a headless device), one mesh, one
// material, one triangle. Escape or closing the window quits.
//
//   goose build examples/triangle.goose && examples/triangle
//
// Import nothing but hipgr: the graphics backend stays behind it.
import std;
import os;
import hipgr from "../src/hipgr";

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open(dev, "HiPGR: triangle", 640, 480) else {
        write_stderr(str("hipgr: ", hipgr::error_text(hipgr::error_code(dev)), ": ",
                         hipgr::backend_error(), "\n"));
        return;
    }
    defer hipgr::close(dev);

    let tri = hipgr::mesh_triangle(dev);
    if tri.id == 0 {
        write_stderr(str("hipgr: mesh: ", hipgr::error_text(hipgr::error_code(dev)), "\n"));
        return;
    }
    let mat = hipgr::material_solid(dev, float4 { 0.95, 0.55, 0.2, 1.0 }, true);

    let cam = hipgr::camera_look_at(float3 { 0.0, 0.0, 2.0 }, float3 { 0.0, 0.0, 0.0 },
                                    float3 { 0.0, 1.0, 0.0 }, 0.8);
    let model = hipgr::mat4_identity();

    while hipgr::begin_frame(dev, cam, float4 { 0.08, 0.09, 0.12, 1.0 }) {
        hipgr::draw(dev, tri, mat, model);
        if !hipgr::end_frame(dev) { break; }
        if hipgr::key_pressed("Escape") { break; }
    }

    let s = hipgr::stats(dev);
    print("frames ", s.frames, ", draws ", s.draws, ", triangles ", s.triangles, "\n");
}
