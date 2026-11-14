// HiPGR 0.4 benchmark: 10k objects, with and without the optimisations.
//
// The scene is a grid of 10,000 cubes, most of them outside the view, drawn with
// two materials alternating by row so that batching has to reorder draws rather
// than only merge neighbours. Four configurations are timed on the same frames,
// same camera and same profile, so the differences are the switches:
//
//   baseline    no culling, no batching: what 0.3 did
//   culling     off-screen objects skipped
//   batching    draws grouped into instanced calls
//   both        the defaults
//
// Every configuration draws the same pixels (tests/test_culling and
// tests/test_batching are what prove that). Numbers from this machine are
// software-renderer numbers; quote them as such.
//
//   goose build bench/bench_10k.goose && bench/bench_10k [side] [frames]
//   GOOSE_GFX_HEADLESS=1 bench/bench_10k 100 20
import std;
import os;
import vec;
import hipgr from "../src/hipgr";

fn draw_scene(dev: hipgr::Device&, cube: hipgr::Mesh, mats: hipgr::Material[2],
              cam: hipgr::Camera, side: i64, f: i64) -> bool {
    if !hipgr::begin_frame(dev, cam, float4 { 0.04, 0.05, 0.07, 1.0 }) { return false; }
    var i = 0;
    while i < side * side {
        let x = (i % side) - side / 2;
        let z = (i / side) - side / 2;
        let model = hipgr::mat4_spin(float3 { x * 0.8, 0.0, z * 0.8 },
                                    f * 0.02 + i * 0.001, 0.3);
        hipgr::draw(dev, cube, mats[(i / side) % 2], model);
        i++;
    }
    return hipgr::end_frame(dev);
}

fn measure(dev: hipgr::Device&, cube: hipgr::Mesh, mats: hipgr::Material[2],
           cam: hipgr::Camera, side: i64, frames: i64, culling: bool, batching: bool,
           report: bool) -> f64 {
    hipgr::set_culling(dev, culling);
    hipgr::set_batching(dev, batching);
    let before = hipgr::stats(dev);
    // Two warm-up frames: pipelines are created on first use, and the instance
    // buffer grows on the first batched frame.
    for f in 2 {
        if !draw_scene(dev, cube, mats, cam, side, f) { return -1.0; }
    }
    let started = hipgr::time();
    for f in frames {
        if !draw_scene(dev, cube, mats, cam, side, f) { return -1.0; }
    }
    let elapsed = hipgr::time() - started;
    if frames == 0 { return -1.0; }
    let after = hipgr::stats(dev);
    // Per frame, not cumulative: the warm-up frames are in the difference.
    let n = frames + 2;
    let culled = (after.culled - before.culled) / n;
    let batches = (after.batches - before.batches) / n;
    let instanced_draws = (after.instanced - before.instanced) / n;
    if report {
        print("    culled ", culled, " objects, ", batches, " batches, ",
              instanced_draws, " instanced draws per frame\n");
    }
    return elapsed / frames * 1000.0;
}

fn main() {
    var side: i64 = 100;
    var frames: i64 = 30;
    // -1: all four configurations. 0..3: only that one, for isolating a
    // measurement without the other three running first.
    var only: i64 = -1;
    let argv = args();
    if argv.len >= 2 {
        let n, ok = parse_int(argv[1]);
        if ok { side = n; }
    }
    if argv.len >= 3 {
        let n, ok = parse_int(argv[2]);
        if ok { frames = n; }
    }
    if argv.len >= 4 {
        let n, ok = parse_int(argv[3]);
        if ok { only = n; }
    }

    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, 1280, 720) else {
        write_stderr(str("bench_10k: no GPU device: ", hipgr::backend_error(), "\n"));
        return;
    }
    defer hipgr::close(dev);
    hipgr::quality(dev, hipgr::QUALITY_MODERN);

    let cube = hipgr::mesh_cube(dev);
    let img = hipgr::image_checker(dev, 64, 8, [40, 40, 60, 255], [220, 200, 120, 255]);
    var mats: hipgr::Material[2] = [
        hipgr::material_create(dev, hipgr::MaterialDesc { image: img, roughness: 0.85 }),
        hipgr::material_create(dev, hipgr::MaterialDesc {
            tint: float4 { 0.8, 0.85, 0.95, 1.0 }, metallic: 0.9, roughness: 0.25 }),
    ];
    hipgr::set_light(dev, float3 { -0.4, -0.8, -0.6 }, float3_1, 0.25);
    hipgr::set_shadow_area(dev, float3 { 0.0, 0.0, 0.0 }, 14.0);
    let cam = hipgr::camera_look_at(float3 { 0.0, 9.0, 28.0 }, float3_0,
                                    float3 { 0.0, 1.0, 0.0 }, 0.8);

    let objects = side * side;
    print("HiPGR ", hipgr::version(), " benchmark: ", objects, " objects (", side, "x", side,
          "), ", frames, " frames, driver ", hipgr::driver(dev), "\n");

    // Three interleaved trials of each configuration. Both the trials and the
    // fastest of them are printed: this machine is a shared container running a
    // CPU rasteriser, so a slow trial says something about the machine while the
    // fastest says something about the renderer. The speedup is the ratio within
    // each trial, so a trial that ran while the machine was busy penalises both
    // numbers equally.
    var best: f64[4] = [0.0, 0.0, 0.0, 0.0];
    var worst_ratio: f64 = 0.0;
    var best_ratio: f64 = 0.0;
    for trial in 3 {
        var times: f64[4] = [0.0, 0.0, 0.0, 0.0];
        for c in 4 {
            if only >= 0 && c != only { continue; }
            let t = measure(dev, cube, mats, cam, side, frames, c == 1 || c == 3, c == 2 || c == 3,
                            true);
            if t <= 0.0 { write_stderr("bench_10k: no frames drawn\n"); return; }
            times[c] = t;
            if best[c] <= 0.0 || t < best[c] { best[c] = t; }
        }
        let ratio = times[0] / times[3];
        if trial == 0 || ratio < worst_ratio { worst_ratio = ratio; }
        if ratio > best_ratio { best_ratio = ratio; }
        print("trial ", trial, ": baseline ", times[0], ", culling ", times[1],
              ", batching ", times[2], ", both ", times[3], " ms/frame (speedup ", ratio, "x)\n");
    }
    let baseline = best[0];
    let both = best[3];
    print("best of the three trials, ms/frame:\n");
    print("  baseline (no culling, no batching): ", baseline, "\n");
    print("  culling only: ", best[1], "  (", baseline / best[1], "x)\n");
    print("  batching only: ", best[2], "  (", baseline / best[2], "x)\n");
    print("  both: ", both, "  (", baseline / both, "x)\n");
    print("speedup across trials: ", worst_ratio, "x to ", best_ratio, "x\n");

    if baseline <= 0.0 || both <= 0.0 {
        write_stderr("bench_10k: no frames drawn\n");
        return;
    }
    print("speedup over baseline: ", baseline / both, "x\n");
}
