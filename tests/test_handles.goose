// Resource lifetime: a released handle is an error, never a crash; misuse is
// reported through the device instead of taking the process down.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

fn main() {
    let size: i64 = 32;
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, size, size) else {
        verify::skip("test_handles: no GPU device");
        return;
    }
    defer hipgr::close(dev);

    let cube = hipgr::mesh_cube(dev);
    let cube2 = hipgr::mesh_cube(dev);
    verify::expect(cube.id != 0 && cube2.id != 0, "two meshes created");
    verify::expect_ne(cube.id, cube2.id, "distinct mesh handles");
    verify::expect_eq(hipgr::stats(dev).meshes, 2, "two meshes tracked");

    // Releasing invalidates the handle and frees the buffers.
    hipgr::release(dev, cube);
    verify::expect(hipgr::ok(dev), "release succeeds");
    verify::expect_eq(hipgr::stats(dev).meshes, 1, "release decrements the count");
    verify::expect_eq(hipgr::mesh_info(dev, cube).triangles, 0, "released mesh has no info");

    // Using it is an error with a reason, not a crash.
    hipgr::clear_error(dev);
    let mat = hipgr::material_solid(dev, float4_1, true);
    let cam = hipgr::camera_look_at(float3 { 0.0, 0.0, 3.0 }, float3_0, float3 { 0.0, 1.0, 0.0 },
                                    0.8);
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(!hipgr::draw(dev, cube, mat, hipgr::mat4_identity()), "released mesh draw fails");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_HANDLE, "failure names the handle");
    // The frame still ends cleanly after a rejected draw.
    verify::expect(hipgr::end_frame(dev), "frame still ends");

    // Double release is reported, and cannot free anything twice.
    hipgr::release(dev, cube);
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_HANDLE, "double release is rejected");

    // A zero handle is never valid.
    verify::expect(!hipgr::draw(dev, hipgr::Mesh { 0 }, mat, hipgr::mat4_identity()),
                   "zero mesh handle rejected");

    // An image released while a material still names it is caught at draw
    // time rather than reading a stale texture.
    let img = hipgr::image_checker(dev, 8, 2, [255, 0, 0, 255], [0, 255, 0, 255]);
    let textured = hipgr::material_textured(dev, img, float4_1, true);
    verify::expect(textured.id != 0, "textured material created");
    hipgr::release(dev, img);
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(!hipgr::draw(dev, cube2, textured, hipgr::mat4_identity()),
                   "material with a released image is rejected");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_HANDLE, "released image reported");
    verify::expect(hipgr::end_frame(dev), "frame ends");

    // Frame lifecycle misuse.
    verify::expect(!hipgr::end_frame(dev), "end_frame without begin_frame fails");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_NO_FRAME, "no frame reported");
    hipgr::clear_error(dev);
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(!hipgr::begin_frame(dev, cam, float4_0), "nested begin_frame fails");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_FRAME_OPEN, "open frame reported");
    verify::expect(hipgr::end_frame(dev), "frame ends after the rejected begin");

    // Bad geometry never reaches the GPU.
    var verts: hipgr::Vertex[>..] = [];
    verts.push(hipgr::Vertex { pos: float3_0, normal: float3 { 0.0, 0.0, 1.0 }, uv: float2_0 });
    let idx: u16[3] = [0, 1, 2];
    let vs = verts[..];
    verify::expect(hipgr::mesh_create(dev, vs, idx[..]).id == 0, "out-of-range index rejected");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_ARGUMENT, "bad geometry reported");

    // Closing releases what is still live; nothing is leaked or double freed.
    hipgr::close(dev);
    verify::expect(!hipgr::is_open(dev), "device closed");
    verify::expect(!hipgr::begin_frame(dev, cam, float4_0), "closed device cannot begin a frame");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_NOT_OPEN, "closed device reported");

    verify::pass("test_handles");
}
