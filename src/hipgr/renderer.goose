// HiPGR: frames and draw submission.
//
// The frame lifecycle is explicit:
//
//   begin_frame(dev, camera, clear)   // sizes the targets, starts recording
//   draw(dev, mesh, material, model)  // once per object, recorded not drawn
//   end_frame(dev)                    // renders the frame, presents it
//
// draw() records and end_frame() renders, because a frame is four passes in a
// fixed order (shadow, scene, bloom, composite) and the recording is what lets
// the shadow pass see the whole scene before the scene pass begins. It also
// leaves room for sorting and culling without changing the API.
//
// Nothing here knows what a scene is. Applications submit renderables, in any
// order they like.
namespace hipgr;

import vec;
import .math;
import .camera;
import .state;
import .device;
import .mesh;
import .material;
import .gpu;
import .uniforms;
import .post;

fn begin_frame(d: Device&, cam: Camera, clear: float4) -> bool {
    if !d.opened { d.last_error = ERR_NOT_OPEN; return false; }
    if d.frame_open { d.last_error = ERR_FRAME_OPEN; return false; }
    let size = screen_size(d);
    if size.x <= 0 || size.y <= 0 { d.last_error = ERR_GPU; return false; }
    if !ensure_targets(d, size.x, size.y) { return false; }
    if !ensure_pipelines(d) { return false; }

    d.camera = cam;
    d.clear_color = clear;
    d.items.clear();
    d.frame_open = true;
    d.last_error = ERR_NONE;
    return true;
}

fn draw(d: Device&, m: Mesh, mat: Material, model: Mat4) -> bool {
    if !d.frame_open { d.last_error = ERR_NO_FRAME; return false; }
    let mi = mesh_index(d, m);
    if mi < 0 { d.last_error = ERR_BAD_HANDLE; return false; }
    let ai = material_index(d, mat);
    if ai < 0 { d.last_error = ERR_BAD_HANDLE; return false; }
    let ar = d.materials[ai];
    // Materials name their images by handle, so releasing one while a material
    // still uses it is caught here, while the frame is recorded, instead of
    // while it is being rendered.
    if ar.builtin {
        if ar.image.id != 0 && image_index(d, ar.image) < 0 {
            d.last_error = ERR_BAD_HANDLE;
            return false;
        }
        if ar.normal_image.id != 0 && image_index(d, ar.normal_image) < 0 {
            d.last_error = ERR_BAD_HANDLE;
            return false;
        }
    }

    d.items.push(DrawItem { mesh: m, material: mat, model: model });
    d.stats.draws++;
    d.stats.triangles += d.meshes[mi].index_count / 3;
    d.last_error = ERR_NONE;
    return true;
}

// Renders what was recorded and presents it. Returns false when the platform
// asked the program to quit (the window closed, or quit() was called).
fn end_frame(d: Device&) -> bool {
    if !d.frame_open { d.last_error = ERR_NO_FRAME; return false; }
    let size = screen_size(d);
    let aspect = size.x as f32 / size.y;
    let frame = frame_uniform(d, d.camera, aspect);

    // Depth from the light first: the scene pass needs the finished shadow map.
    if d.shadows && d.items.len > 0 { run_shadow_pass(d, frame); }
    run_scene_pass(d, frame, d.clear_color);
    run_bloom(d);
    run_composite(d, d.clear_color);

    d.items.clear();
    d.frame_open = false;
    d.stats.frames++;
    return gpu_present();
}

// The bytes of the last presented screen, RGBA8, top row first. A debugging
// and regression-test facility: read back after a frame.
fn frame_pixels(d: Device&) -> u8[>..] {
    return gpu_read_pixels();
}

fn screenshot(d: Device&, path: const u8[:]) -> bool {
    gpu_screenshot(path)
}
