// 0.4 acceptance: draw batching and instancing.
//
// Objects that share a mesh and a material are drawn with one instanced draw
// call instead of one each. The test renders the same scene with batching off
// and on, requires the images to be identical, and requires the batch count to
// fall from one per object to one per geometry-and-material pair.
//
// The scene deliberately interleaves three materials, so batching has to group
// draws that were not submitted together: that is the sorting half of the
// optimisation, and the pixel comparison is what makes reordering opaque draws
// acceptable.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 128;
let OBJECTS: i64 = 240;

// Pixels where one channel clearly dominates: how each of the three tints shows
// up, without predicting what the lighting does to the exact value.
fn count_dominant(px: const u8[:], channel: i64) -> i64 {
    var n = 0;
    var i = 0;
    while i + 3 < px.len {
        let r = px[i] as i64;
        let g = px[i + 1] as i64;
        let b = px[i + 2] as i64;
        let v = if channel == 0 { r } else if channel == 1 { g } else { b };
        let rest = if channel == 0 { if g > b { g } else { b } }
                   else if channel == 1 { if r > b { r } else { b } }
                   else { if r > g { r } else { g } };
        if v > 40 && v > rest + 20 { n++; }
        i += 4;
    }
    return n;
}

fn render(dev: hipgr::Device&, cam: hipgr::Camera, cube: hipgr::Mesh, mats: hipgr::Material[3],
          batching: bool) -> u8[>..] {
    verify::expect(hipgr::set_batching(dev, batching), "batching switch accepted");
    verify::expect(hipgr::begin_frame(dev, cam, float4 { 0.0, 0.0, 0.0, 1.0 }), "frame begins");
    var i = 0;
    while i < OBJECTS {
        let x = (i % 12) - 6;
        let y = ((i / 12) % 5) - 2;
        let z = (i / 60) % 4;
        let model = hipgr::mat4_trs(float3 { x * 0.85, y * 0.85, -4.0 - z * 1.5 },
                                    float3 { 0.0, 1.0, 0.0 }, i * 0.01,
                                    float3 { 0.4, 0.4, 0.4 });
        verify::expect(hipgr::draw(dev, cube, mats[i % 3], model), "draw succeeds");
        i++;
    }
    verify::expect(hipgr::end_frame(dev), "frame ends");
    return hipgr::frame_pixels(dev);
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_batching: no GPU device");
        return;
    }
    defer hipgr::close(dev);
    verify::expect(hipgr::quality(dev, hipgr::QUALITY_LINEAR), "linear quality accepted");
    // Culling off for the batching counts: a culled object would leave its run
    // out of the batch list, and this test is about grouping, not removal.
    verify::expect(hipgr::set_culling(dev, false), "culling off");

    let cube = hipgr::mesh_cube(dev);
    // Lit, so the image depends on the normals the instanced shader supplies as
    // well as on the model matrices: an instancing bug in either shows up.
    var mats: hipgr::Material[3] = [
        hipgr::material_solid(dev, float4 { 0.9, 0.3, 0.2, 1.0 }, false),
        hipgr::material_solid(dev, float4 { 0.2, 0.8, 0.3, 1.0 }, false),
        hipgr::material_solid(dev, float4 { 0.3, 0.4, 0.95, 1.0 }, false),
    ];
    verify::expect(hipgr::set_light(dev, float3 { -0.4, -0.8, -0.6 }, float3_1, 0.3),
                   "light set");
    let cam = hipgr::camera_perspective(float3 { 0.0, 0.0, 2.0 }, float3 { 0.0, 0.0, -6.0 },
                                        float3 { 0.0, 1.0, 0.0 }, 0.9, 0.1, 60.0);

    // --- batching off: one batch per object ---
    let b0 = hipgr::stats(dev);
    let unbatched = render(dev, cam, cube, mats, false);
    let s0 = hipgr::stats(dev);
    verify::expect_eq(s0.batches - b0.batches, OBJECTS, "unbatched: a batch per object");
    verify::expect_eq(s0.instances - b0.instances, 0, "unbatched: nothing is instanced");
    verify::expect_eq(s0.instanced - b0.instanced, 0, "unbatched: no instanced draw");
    // All three materials are on screen, so the batches that follow are not
    // grouping an empty image.
    verify::expect(count_dominant(unbatched, 0) > 100, "the red material is on screen");
    verify::expect(count_dominant(unbatched, 1) > 100, "the green material is on screen");
    verify::expect(count_dominant(unbatched, 2) > 100, "the blue material is on screen");

    // --- batching on: one batch per geometry and material ---
    let b1 = hipgr::stats(dev);
    let batched = render(dev, cam, cube, mats, true);
    let s1 = hipgr::stats(dev);
    verify::expect_eq(s1.batches - b1.batches, 3, "batched: one batch per material");
    verify::expect_eq(s1.instances - b1.instances, OBJECTS, "every object is an instance");
    verify::expect_eq(s1.instanced - b1.instanced, 3, "three instanced draws");
    verify::expect_eq(verify::count_different(unbatched, batched), 0,
                      "batching changes no pixel");

    // The draw count is unchanged: batching merges draw calls, it does not
    // silently drop objects.
    verify::expect_eq(s1.draws - b1.draws - (s0.draws - b0.draws), 0,
                      "the same number of objects was submitted");

    // Culling and batching together: the objects outside the view are skipped,
    // and what is left is still exactly what the unoptimised path draws.
    verify::expect(hipgr::set_culling(dev, true), "culling on");
    let wide = hipgr::camera_perspective(float3 { 0.0, 0.0, 2.0 }, float3 { 0.0, 0.0, -6.0 },
                                         float3 { 0.0, 1.0, 0.0 }, 0.35, 0.1, 60.0);
    let narrow_unbatched = render(dev, wide, cube, mats, false);
    let narrow_batched = render(dev, wide, cube, mats, true);
    verify::expect_eq(verify::count_different(narrow_unbatched, narrow_batched), 0,
                      "batching changes no pixel in a culled scene");

    verify::pass("test_batching");
}
