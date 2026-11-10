// 0.1 acceptance: a rotating, textured 3D cube. Checks that the texture is
// sampled over the face, that the background survives, that depth writes keep
// the cube solid, and that rotating the model changes the image.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

fn main() {
    let size: i64 = 128;
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, size, size) else {
        verify::skip("test_cube_textured: no GPU device");
        return;
    }
    hipgr::quality(dev, hipgr::QUALITY_LINEAR);
    defer hipgr::close(dev);

    let cube = hipgr::mesh_cube(dev);
    verify::expect_eq(hipgr::mesh_info(dev, cube).triangles, 12, "cube has 12 triangles");

    let dark: u8[4] = [40, 40, 60, 255];
    let light: u8[4] = [220, 200, 120, 255];
    let img = hipgr::image_checker(dev, 64, 8, dark, light);
    verify::expect(img.id != 0, "checker image created");
    verify::expect_eq(hipgr::image_info(dev, img).width, 64, "image width");

    // Unlit and untinted, so a texel survives to the screen unchanged.
    let mat = hipgr::material_textured(dev, img, float4_1, true);
    verify::expect(mat.id != 0, "textured material created");

    let cam = hipgr::camera_look_at(float3 { 0.0, 0.0, 3.0 }, float3_0, float3 { 0.0, 1.0, 0.0 },
                                    0.8);
    let still = hipgr::mat4_identity();

    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, cube, mat, still), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    let first = hipgr::frame_pixels(dev);

    // Both checker colours appear on the face: the texture is being sampled,
    // not replaced by one constant.
    let n_dark = verify::count_color(first, dark, 3);
    let n_light = verify::count_color(first, light, 3);
    verify::expect(n_dark > 200, "dark checker cells cover part of the cube");
    verify::expect(n_light > 200, "light checker cells cover part of the cube");
    // The corners of the screen stay background.
    verify::expect_pixel(first, size, 2, 2, [0, 0, 0, 255], 1, "background corner");

    // The cube is opaque: no background pixel inside its silhouette.
    verify::expect_not_pixel(first, size, size / 2, size / 2, [0, 0, 0, 255], 1,
                             "centre is cube, not background");

    // Rotate: the image must change.
    let spun = hipgr::mat4_spin(float3_0, 0.7, 1.0);
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "second frame begins");
    verify::expect(hipgr::draw(dev, cube, mat, spun), "second draw succeeds");
    verify::expect(hipgr::end_frame(dev), "second frame ends");
    let second = hipgr::frame_pixels(dev);

    let changed = verify::count_different(first, second);
    verify::expect(changed > 500, "rotation changes the rendered image");

    let s = hipgr::stats(dev);
    verify::expect_eq(s.frames, 2, "two frames counted");
    verify::expect_eq(s.draws, 2, "two draws counted");
    verify::expect_eq(s.triangles, 24, "24 triangles counted");

    verify::pass("test_cube_textured");
}
