// An application that uses HiPGR from outside the package, the way a host such
// as G3E would: it imports the package by path, never the backend, and does its
// own frame loop. scripts/consumer.sh builds and runs it from a clean copy of
// the tree, which is 0.5's "an external project builds against HiPGR without
// patching it".
//
// It is deliberately not under tests/ or examples/: it is not a HiPGR test, it is
// a consumer, and the property being checked is that HiPGR's public API is
// enough on its own.
import std;
import vec;
import hipgr from "../src/hipgr";

fn main() {
    var dev = hipgr::Device { .. };
    if !hipgr::open_headless(dev, 64, 64) {
        // No device: nothing was validated, and the runner says so.
        print("SKIP consumer: no GPU device\n");
        return;
    }
    defer hipgr::close(dev);

    // Everything a small application needs, through the public API only.
    if !hipgr::quality(dev, hipgr::QUALITY_MODERN) { fail("quality"); }
    let cube = hipgr::mesh_cube(dev);
    if cube.id == 0 { fail("mesh"); }
    let mat = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: float4 { 0.9, 0.4, 0.2, 1.0 },
        metallic: 0.2,
        roughness: 0.6,
    });
    if mat.id == 0 { fail("material"); }
    if !hipgr::set_light(dev, float3 { -0.4, -0.8, -0.6 }, float3_1, 0.25) { fail("light"); }
    if !hipgr::set_point_light(dev, 0, float3 { 1.5, 1.5, 2.0 }, float3 { 1.0, 0.7, 0.4 }, 6.0) {
        fail("point light");
    }
    let cam = hipgr::camera_look_at(float3 { 1.2, 1.0, 3.0 }, float3_0,
                                   float3 { 0.0, 1.0, 0.0 }, 0.8);

    for f in 3 {
        if !hipgr::begin_frame(dev, cam, float4 { 0.05, 0.06, 0.08, 1.0 }) { fail("begin_frame"); }
        if !hipgr::draw(dev, cube, mat, hipgr::mat4_spin(float3_0, f * 0.3, 1.4)) { fail("draw"); }
        if !hipgr::end_frame(dev) { fail("end_frame"); }
    }

    let px = hipgr::frame_pixels(dev);
    if px.len != 64 * 64 * 4 { fail("read back the wrong number of pixels"); }
    // The centre of the frame is the cube, not the sky behind it.
    let o = (32 * 64 + 32) * 4;
    if px[o] < 10 && px[o + 1] < 10 && px[o + 2] < 10 { fail("the cube did not render"); }

    let s = hipgr::stats(dev);
    if s.frames != 3 || s.draws != 3 { fail("stats"); }
    if s.batches < 3 { fail("frames were not batched as expected"); }
    print("PASS consumer\n");
}

fn fail(what: const u8[:]) {
    print("FAIL consumer: ", what, "\n");
    abort("consumer failed");
}
