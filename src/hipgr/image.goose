// HiPGR: textures as images.
//
// An image is an RGBA8 sampled texture and the handle an application keeps.
// Creating one from bytes is here; decoding files is kept separate so the
// renderer never depends on a file format parser.
namespace hipgr;

import std;
import .handle;
import .device;
import .gpu;

// Uploads tightly packed RGBA8 pixels, row 0 first.
fn image_rgba8(d: Device&, width: i64, height: i64, pixels: const u8[:]) -> Image {
    if width <= 0 || height <= 0 { d.last_error = ERR_BAD_ARGUMENT; return Image { 0 }; }
    if pixels.len != width * height * 4 { d.last_error = ERR_BAD_ARGUMENT; return Image { 0 }; }
    let t = gpu_texture_rgba8(width, height, pixels);
    if t.id == 0 { d.last_error = ERR_GPU; return Image { 0 }; }
    d.last_error = ERR_NONE;
    return alloc_image(d, t, width, height);
}

// A two-colour checkerboard, deterministic by construction: a test texture
// that needs no asset file and samples exactly.
fn image_checker(d: Device&, size: i64, cell: i64, ca: u8[4], cb: u8[4]) -> Image {
    if size <= 0 || cell <= 0 { d.last_error = ERR_BAD_ARGUMENT; return Image { 0 }; }
    var px: u8[>..] = [];
    px.resize(size * size * 4, 0);
    for y in size {
        for x in size {
            let c = if (x / cell + y / cell) % 2 == 0 { ca } else { cb };
            let o = (y * size + x) * 4;
            for k in 4 { px[o + k] = c[k]; }
        }
    }
    let bytes = px[..];
    return image_rgba8(d, size, size, bytes);
}

// A PNG or BMP from disk, as the backend decodes it. No mip chain in 0.1.
fn image_load(d: Device&, path: const u8[:]) -> Image {
    let t = gpu_texture_load(path);
    if t.id == 0 { d.last_error = ERR_GPU; return Image { 0 }; }
    d.last_error = ERR_NONE;
    let size = gpu_texture_size(t);
    return alloc_image(d, t, size.x, size.y);
}

fn release(d: Device&, h: Image) {
    let i = image_index(d, h);
    if i < 0 { d.last_error = ERR_BAD_HANDLE; return; }
    gpu_release_texture(d.images[i].texture);
    d.images[i].texture.id = 0;
    d.images[i].live = false;
    d.images[i].generation = next_generation(d.images[i].generation);
    d.stats.images = d.stats.images - 1;
}

fn image_info(d: Device&, h: Image) -> ImageInfo {
    let i = image_index(d, h);
    if i < 0 { return ImageInfo {}; }
    return ImageInfo { width: d.images[i].width, height: d.images[i].height };
}
