// HiPGR benchmark: how long a frame of N cubes takes, end to end, including
// present, under both quality profiles. Numbers from this machine are
// software-renderer numbers; run it on a real GPU before quoting them as
// performance.
//
// The difference between the two lines is what 0.3's modern pipeline costs: the
// same draws, plus a shadow pass and the bloom and tone-mapping passes.
//
//   goose build bench/bench_scene.goose && bench/bench_scene [cubes] [frames]
//   GOOSE_GFX_HEADLESS=1 bench/bench_scene 500 60
import std;
import os;
import vec;
import hipgr from "../src/hipgr";

fn frame_once(dev: hipgr::Device&, cube: hipgr::Mesh, mat: hipgr::Material,
              cam: hipgr::Camera, objects: i64, f: i64) -> bool {
    if !hipgr::begin_frame(dev, cam, float4 { 0.04, 0.05, 0.07, 1.0 }) { return false; }
    var i = 0;
    while i < objects {
        let side = 16;
        let x = (i % side) - side / 2;
        let z = (i / side) - side / 2;
        let model = hipgr::mat4_spin(float3 { x * 0.4, 0.0, z * 0.4 },
                                    f * 0.05 + i * 0.01, 0.18);
        hipgr::draw(dev, cube, mat, model);
        i++;
    }
    return hipgr::end_frame(dev);
}

// Two warm-up frames, because pipelines, the shadow map and the bloom targets
// are created on first use: a benchmark that includes them measures start-up.
fn measure(dev: hipgr::Device&, cube: hipgr::Mesh, mat: hipgr::Material,
           cam: hipgr::Camera, objects: i64, frames: i64, profile: i32) -> f64 {
    if !hipgr::quality(dev, profile) { return -1.0; }
    for f in 2 {
        if !frame_once(dev, cube, mat, cam, objects, f) { return -1.0; }
    }
    let started = hipgr::time();
    for f in frames {
        if !frame_once(dev, cube, mat, cam, objects, f) { return -1.0; }
    }
    let elapsed = hipgr::time() - started;
    if frames == 0 { return -1.0; }
    return elapsed / frames * 1000.0;
}

fn main() {
    var objects: i64 = 256;
    var frames: i64 = 60;
    let argv = args();
    if argv.len >= 2 {
        let n, ok = parse_int(argv[1]);
        if ok { objects = n; }
    }
    if argv.len >= 3 {
        let n, ok = parse_int(argv[2]);
        if ok { frames = n; }
    }

    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, 1280, 720) else {
        write_stderr(str("bench: no GPU device: ", hipgr::backend_error(), "\n"));
        return;
    }
    defer hipgr::close(dev);

    let cube = hipgr::mesh_cube(dev);
    let img = hipgr::image_checker(dev, 64, 8, [40, 40, 60, 255], [220, 200, 120, 255]);
    let mat = hipgr::material_create(dev, hipgr::MaterialDesc { image: img, roughness: 0.85 });
    hipgr::set_light(dev, float3 { -0.4, -0.8, -0.6 }, float3_1, 0.25);
    hipgr::set_shadow_area(dev, float3 { 0.0, 0.0, 0.0 }, 8.0);
    let cam = hipgr::camera_look_at(float3 { 0.0, 6.0, 24.0 }, float3_0, float3 { 0.0, 1.0, 0.0 },
                                    0.8);

    print("HiPGR ", hipgr::version(), " benchmark: ", objects, " cubes, ", frames,
          " frames, driver ", hipgr::driver(dev), "\n");

    let linear = measure(dev, cube, mat, cam, objects, frames, hipgr::QUALITY_LINEAR);
    let modern = measure(dev, cube, mat, cam, objects, frames, hipgr::QUALITY_MODERN);
    if linear <= 0.0 || modern <= 0.0 {
        write_stderr("bench: no frames drawn\n");
        return;
    }
    print("linear: ", linear, " ms/frame, ", 1000.0 / linear, " fps\n");
    print("modern: ", modern, " ms/frame, ", 1000.0 / modern, " fps\n");

    let s = hipgr::stats(dev);
    print("draws ", s.draws, ", triangles ", s.triangles, "\n");
}
