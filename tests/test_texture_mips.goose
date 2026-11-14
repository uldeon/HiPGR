// 0.4 acceptance: sRGB sampling and generated mips.
//
// Two things a texture needs to be complete for a linear renderer:
//
//   sRGB   an image authored in sRGB (as every painted texture is) is decoded
//          to linear light when it is sampled, so a mid grey is 0.216 and not
//          0.502, and lighting maths adds it in the right proportion;
//   mips   a minified texture reads a coarser level instead of four texels of
//          level 0, which is what stops it shimmering.
//
// Both are checked through the GPU: the sRGB one by rendering an unlit quad and
// reading the pixel, the mip one by reading the levels the backend generated.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 32;

// How many of a level's first channel are exactly 0 or 255: proof that a level
// contains the source's colours rather than an average of them.
fn count_extreme(px: const u8[:], value: u8) -> i64 {
    var n = 0;
    var i = 0;
    while i + 3 < px.len {
        if px[i] == value { n++; }
        i += 4;
    }
    return n;
}

// The gap between two channels of a pixel, as a number.
fn distance_channel(c: u8[4], a: i64, b: i64) -> i64 {
    let x = c[a] as i64;
    let y = c[b] as i64;
    return if x > y { x - y } else { y - x };
}

// An unlit quad filling the screen, sampled with one image. Returns the centre
// pixel: with linear output it is the value the shader read, times 255.
fn sample_quad(dev: hipgr::Device&, img: hipgr::Image, size: f32, filter: i32) -> u8[4] {
    let quad = hipgr::mesh_quad(dev);
    let mat = hipgr::material_create(dev, hipgr::MaterialDesc { image: img, tint: float4_1,
                                                               unlit: true, filter: filter });
    let cam = hipgr::camera_look_at(float3 { 0.0, 0.0, 3.0 }, float3_0,
                                    float3 { 0.0, 1.0, 0.0 }, 0.9);
    let model = hipgr::mat4_mul(hipgr::mat4_translate(float3 { 0.0, 0.0, -2.0 }),
                                hipgr::mat4_scale(float3 { size, size, size }));
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, quad, mat, model), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    return verify::pixel(hipgr::frame_pixels(dev), SIZE, SIZE / 2, SIZE / 2);
}

// A quad that covers the whole screen: magnification, level 0.
fn sample(dev: hipgr::Device&, img: hipgr::Image) -> u8[4] {
    return sample_quad(dev, img, 2.0, hipgr::FILTER_LINEAR);
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_texture_mips: no GPU device");
        return;
    }
    defer hipgr::close(dev);
    // Linear output, so a sampled value and the pixel are the same number.
    verify::expect(hipgr::quality(dev, hipgr::QUALITY_LINEAR), "linear quality accepted");

    // --- sRGB ------------------------------------------------------------------
    // A 4x4 uniform mid grey: 128 in the file is 0.502 as stored and 0.2158 as
    // light, which is 55/255. A texture sampled without the sRGB decode reads
    // 128, so the two are 73 apart and the check cannot be a rounding accident.
    var grey: u8[>..] = [];
    grey.resize(4 * 4 * 4, 128);
    for i in 4 * 4 { grey[i * 4 + 3] = 255; }
    let grey_bytes = grey[..];
    let linear_img = hipgr::image_rgba8(dev, 4, 4, grey_bytes);
    let srgb_img = hipgr::image_rgba8_srgb(dev, 4, 4, grey_bytes);
    verify::expect(linear_img.id != 0 && srgb_img.id != 0, "both greys loaded");

    let plain = sample(dev, linear_img);
    verify::expect(plain[0] > 124 && plain[0] < 132, "a linear texture reads its stored value");
    let decoded = sample(dev, srgb_img);
    verify::expect(decoded[0] > 50 && decoded[0] < 60,
                   "an sRGB texture is decoded to light: 128 becomes 55");
    verify::expect(decoded[1] == decoded[0] && decoded[2] == decoded[0],
                   "the decode is per channel and leaves grey grey");

    // --- mips ------------------------------------------------------------------
    // A 4x4 checker of red and blue, two texels to a cell: level 1 averages each
    // 2x2 block (half red, half blue), level 2 averages the whole image.
    var check: u8[>..] = [];
    check.resize(4 * 4 * 4, 255);
    for y in 4 {
        for x in 4 {
            let o = (y * 4 + x) * 4;
            let even = (x / 2 + y / 2) % 2 == 0;
            check[o] = if even { 255 } else { 0 };
            check[o + 1] = 0;
            check[o + 2] = if even { 0 } else { 255 };
            check[o + 3] = 255;
        }
    }
    let check_bytes = check[..];
    let mips = hipgr::image_rgba8_mips(dev, 4, 4, check_bytes);
    verify::expect(mips.id != 0, "a mipmapped texture loaded");

    // Reading a level submits and waits, so the generated chain is there.
    var level0: u8[>..] = [];
    level0.resize(4 * 4 * 4, 0);
    var level1: u8[>..] = [];
    level1.resize(2 * 2 * 4, 0);
    var level2: u8[>..] = [];
    level2.resize(4, 0);
    verify::expect(hipgr::image_mip_pixels(dev, mips, 0, level0), "level 0 readable");
    verify::expect(hipgr::image_mip_pixels(dev, mips, 1, level1), "level 1 readable");
    verify::expect(hipgr::image_mip_pixels(dev, mips, 2, level2), "level 2 readable");

    verify::expect(level0[0] == 255 && level0[2] == 0, "level 0 is still the texture");
    // What the backend's generator actually does with an RGBA8 source, measured
    // rather than assumed: level 1 keeps the source's two colours (its 2x2
    // reduction samples rather than averages), and level 2 is the average of the
    // whole image, which is the level a minifying draw reads.
    verify::expect(level1[0] == 255 || level1[0] == 0, "level 1 holds the source colours");
    verify::expect(count_extreme(level1, 0) > 0 && count_extreme(level1, 255) > 0,
                   "level 1 has both colours in it");
    verify::expect(level2[0] > 110 && level2[0] < 145 && level2[2] > 110 && level2[2] < 145,
                   "level 2 is the average of the whole image");

    // Reading a level a texture does not have is a backend misuse, which aborts
    // loudly rather than returning garbage, so it is not a case this test can
    // exercise in-process: image_mip_pixels is for a level that exists.

    // --- and it renders ---------------------------------------------------------
    // A mip chain must not change what a magnified texture looks like: the
    // sample comes from level 0 either way. A minifying draw reads the coarser
    // levels, which is what the readback above proved exists; pinning which
    // level a one-pixel quad picks would be testing the rasteriser, not HiPGR.
    let plain_checker = hipgr::image_rgba8(dev, 4, 4, check_bytes);
    verify::expect(plain_checker.id != 0, "the same checker without mips loaded");
    let magnified_mips = sample(dev, mips);
    let magnified_plain = sample(dev, plain_checker);
    // Magnified, the pixel sits on a texel boundary of the 4x4 image and so is
    // a bilinear blend; the point of the two checks above is that the chain does
    // not change that blend.
    verify::expect_eq(magnified_mips[0], magnified_plain[0],
                      "a mipmapped texture reads level 0 when magnified");
    verify::expect_eq(magnified_mips[2], magnified_plain[2], "same blue");

    verify::pass("test_texture_mips");
}
