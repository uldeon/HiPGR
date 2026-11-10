// HiPGR benchmark: how long a frame of N cubes takes, end to end, including
// present. Numbers from this machine are software-renderer numbers (see
// RECONNAISSANCE.md); run it on a real GPU before quoting them as performance.
//
//   goose build bench/bench_scene.goose && bench/bench_scene [cubes] [frames]
//   GOOSE_GFX_HEADLESS=1 bench/bench_scene 500 60
import std;
import os;
import vec;
import hipgr from "../src/hipgr";

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
    let mat = hipgr::material_textured(dev, img, float4_1, false);
    hipgr::set_light(dev, float3 { -0.4, -0.8, -0.6 }, float3_1, 0.25);
    let cam = hipgr::camera_look_at(float3 { 0.0, 6.0, 24.0 }, float3_0, float3 { 0.0, 1.0, 0.0 },
                                    0.8);

    print("HiPGR ", hipgr::version(), " benchmark: ", objects, " cubes, ", frames,
          " frames, driver ", hipgr::driver(dev), "\n");

    var drawn = 0;
    let started = hipgr::time();
    for f in frames {
        if !hipgr::begin_frame(dev, cam, float4 { 0.04, 0.05, 0.07, 1.0 }) { break; }
        var i = 0;
        while i < objects {
            let side = 16;
            let x = (i % side) - side / 2;
            let z = (i / side) - side / 2;
            let model = hipgr::mat4_spin(float3 { x * 0.4, 0.0, z * 0.4 },
                                        f * 0.05 + i * 0.01, 0.18);
            hipgr::draw(dev, cube, mat, model);
            drawn++;
            i++;
        }
        if !hipgr::end_frame(dev) { break; }
    }
    let elapsed = hipgr::time() - started;

    let s = hipgr::stats(dev);
    if s.frames == 0 {
        write_stderr("bench: no frames drawn\n");
        return;
    }
    let ms = elapsed / s.frames * 1000.0;
    print("frames ", s.frames, ", draws ", s.draws, ", triangles ", s.triangles, "\n");
    print("elapsed ", elapsed, " s, ", ms, " ms/frame, ", 1000.0 / ms, " fps\n");
}
