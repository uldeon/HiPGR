// Many objects in one frame: 256 cubes drawn through the same material and
// mesh, the shape of the workload instancing will replace in 0.4. Counts,
// depth and timing are all checked.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

fn main() {
    let size: i64 = 160;
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, size, size) else {
        verify::skip("test_many_draws: no GPU device");
        return;
    }
    hipgr::quality(dev, hipgr::QUALITY_LINEAR);
    defer hipgr::close(dev);

    let cube = hipgr::mesh_cube(dev);
    let mat = hipgr::material_solid(dev, float4 { 0.8, 0.8, 0.85, 1.0 }, false);
    verify::expect(hipgr::set_light(dev, float3 { -0.4, -0.8, -0.6 }, float3_1, 0.3), "light set");

    let cam = hipgr::camera_look_at(float3 { 0.0, 2.5, 9.0 }, float3 { 0.0, 0.0, 0.0 },
                                    float3 { 0.0, 1.0, 0.0 }, 0.8);

    let objects: i64 = 256;
    let frames: i64 = 3;
    var drawn = 0;
    let started = hipgr::time();
    for f in frames {
        verify::expect(hipgr::begin_frame(dev, cam, float4 { 0.05, 0.06, 0.08, 1.0 }),
                       "frame begins");
        var i = 0;
        while i < objects {
            let x = (i % 16) - 8;
            let z = (i / 16) - 8;
            let model = hipgr::mat4_trs(float3 { x * 0.9, 0.0, z * 0.9 },
                                        float3 { 0.0, 1.0, 0.0 }, f * 0.1,
                                        float3 { 0.35, 0.35, 0.35 });
            verify::expect(hipgr::draw(dev, cube, mat, model), "draw succeeds");
            drawn++;
            i++;
        }
        verify::expect(hipgr::end_frame(dev), "frame ends");
    }
    let elapsed = hipgr::time() - started;

    let px = hipgr::frame_pixels(dev);
    // Something was drawn, and the sky is still visible between the cubes.
    verify::expect(verify::count_color(px, [0, 0, 0, 255], 2) < size * size,
                   "the scene is not just background");
    verify::expect(verify::count_color(px, [13, 15, 20, 255], 3) > 0,
                   "the clear colour is still visible");

    let s = hipgr::stats(dev);
    verify::expect_eq(s.frames, frames, "frames counted");
    verify::expect_eq(s.draws, drawn, "draws counted");
    verify::expect_eq(s.triangles, drawn * 12, "triangles counted");
    verify::expect_eq(hipgr::stats(dev).meshes, 1, "one mesh backs every draw");

    print("256 cubes x ", frames, " frames: ", elapsed, " s total\n");
    verify::pass("test_many_draws");
}
