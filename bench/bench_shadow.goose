// HiPGR benchmark: what the shadow pass costs, with the frame's other work held
// fixed. The same 10,000-object frame is timed with shadows on and off; the
// difference is the shadow pass (plus the shader's shadow lookup, which is in
// both).
//
// Used to measure 0.5's culling and instancing of that pass against 0.4, which
// is why it takes the switches as arguments rather than assuming them.
//
//   goose build bench/bench_shadow.goose && bench/bench_shadow [side] [frames]
import std;
import os;
import vec;
import hipgr from "../src/hipgr";

fn draw_scene(dev: hipgr::Device&, cube: hipgr::Mesh, mat: hipgr::Material,
              cam: hipgr::Camera, side: i64, f: i64) -> bool {
    if !hipgr::begin_frame(dev, cam, float4 { 0.04, 0.05, 0.07, 1.0 }) { return false; }
    var i = 0;
    while i < side * side {
        let x = (i % side) - side / 2;
        let z = (i / side) - side / 2;
        let model = hipgr::mat4_spin(float3 { x * 0.8, 0.0, z * 0.8 }, f * 0.02 + i * 0.001, 0.3);
        hipgr::draw(dev, cube, mat, model);
        i++;
    }
    return hipgr::end_frame(dev);
}

fn measure(dev: hipgr::Device&, cube: hipgr::Mesh, mat: hipgr::Material, cam: hipgr::Camera,
           side: i64, frames: i64, shadows: bool) -> f64 {
    hipgr::set_shadows(dev, shadows);
    for f in 2 {
        if !draw_scene(dev, cube, mat, cam, side, f) { return -1.0; }
    }
    let started = hipgr::time();
    for f in frames {
        if !draw_scene(dev, cube, mat, cam, side, f) { return -1.0; }
    }
    let elapsed = hipgr::time() - started;
    if frames == 0 { return -1.0; }
    return elapsed / frames * 1000.0;
}

fn main() {
    var side: i64 = 100;
    var frames: i64 = 12;
    let argv = args();
    if argv.len >= 2 {
        let n, ok = parse_int(argv[1]);
        if ok { side = n; }
    }
    if argv.len >= 3 {
        let n, ok = parse_int(argv[2]);
        if ok { frames = n; }
    }

    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, 1280, 720) else {
        write_stderr(str("bench_shadow: no GPU device: ", hipgr::backend_error(), "\n"));
        return;
    }
    defer hipgr::close(dev);
    hipgr::quality(dev, hipgr::QUALITY_MODERN);
    // The camera keeps everything in view, so culling cannot make the *scene*
    // pass cheaper and the two runs differ only in the shadow pass.
    let cam = hipgr::camera_look_at(float3 { 0.0, 40.0, 60.0 }, float3_0,
                                    float3 { 0.0, 1.0, 0.0 }, 1.1);
    hipgr::set_light(dev, float3 { -0.4, -0.8, -0.6 }, float3_1, 0.25);
    hipgr::set_shadow_area(dev, float3_0, 45.0);

    let cube = hipgr::mesh_cube(dev);
    let mat = hipgr::material_solid(dev, float4 { 0.8, 0.8, 0.85, 1.0 }, false);

    print("HiPGR ", hipgr::version(), " shadow benchmark: ", side * side, " objects, ",
          frames, " frames, driver ", hipgr::driver(dev), "\n");
    var best_on = 0.0;
    var best_off = 0.0;
    for trial in 2 {
        let off = measure(dev, cube, mat, cam, side, frames, false);
        let on = measure(dev, cube, mat, cam, side, frames, true);
        if off <= 0.0 || on <= 0.0 {
            write_stderr("bench_shadow: no frames drawn\n");
            return;
        }
        print("trial ", trial, ": shadows off ", off, ", on ", on, " ms/frame\n");
        if trial == 0 || on < best_on { best_on = on; }
        if trial == 0 || off < best_off { best_off = off; }
    }
    let s = hipgr::stats(dev);
    print("shadow pass: ", best_on - best_off, " ms/frame, ", s.shadow_batches,
          " shadow draws and ", s.shadow_culled, " casters culled in total\n");
}
