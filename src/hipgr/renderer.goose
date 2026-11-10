// HiPGR: frames and draw submission.
//
// The frame lifecycle is explicit:
//
//   begin_frame(dev, camera, clear)   // starts the pass, pushes frame state
//   draw(dev, mesh, material, model)  // once per object
//   end_frame(dev)                    // ends the pass, presents; false = quit
//
// Nothing here knows what a scene is. Applications submit renderables, in any
// order they like; sorting, instancing and culling arrive in 0.4, together
// with the benchmarks that justify them.
namespace hipgr;

import vec;
import .math;
import .camera;
import .state;
import .device;
import .mesh;
import .material;
import .gpu;

// std140-laid-out uniform blocks. Each matches the block of the built-in
// shaders byte for byte; the backend rejects a mismatched size.
struct FrameUniform { view_proj: Mat4 }

// model transforms the geometry, normal its normals: the inverse transpose of
// model's upper 3x3, so a non-uniform scale shades correctly.
struct DrawUniform { model: Mat4, normal: Mat4 }

struct MaterialUniform { tint: float4, params: float4, user0: float4, user1: float4 }

// direction.xyz: the direction the directional light travels in, w: ambient.
// color.rgb: its colour, w: how many point lights follow, as a float.
// points: per light, (position, radius) then (colour, 0). MAX_POINT_LIGHTS
// lights need 2 * MAX_POINT_LIGHTS vec4s, so the block size is fixed.
struct LightUniform { direction: float4, color: float4, points: float4[16] }

fn light_uniform(d: Device&) -> LightUniform {
    var points: float4[16] = [float4 { 0.0, 0.0, 0.0, 0.0 }; 16];
    let n = if d.lights.len > MAX_POINT_LIGHTS { MAX_POINT_LIGHTS } else { d.lights.len };
    for i in n {
        let l = d.lights[i];
        points[i * 2] = float4 { l.position.x, l.position.y, l.position.z, l.radius };
        points[i * 2 + 1] = float4 { l.color.x, l.color.y, l.color.z, 0.0 };
    }
    return LightUniform {
        direction: float4 { d.light_direction.x, d.light_direction.y, d.light_direction.z,
                            d.ambient },
        color: float4 { d.light_color.x, d.light_color.y, d.light_color.z, n },
        points: points,
    };
}

fn begin_frame(d: Device&, cam: Camera, clear: float4) -> bool {
    if !d.opened { d.last_error = ERR_NOT_OPEN; return false; }
    if d.frame_open { d.last_error = ERR_FRAME_OPEN; return false; }
    let size = screen_size(d);
    if size.x <= 0 || size.y <= 0 { d.last_error = ERR_GPU; return false; }

    let aspect = size.x as f32 / size.y;
    if !gpu_begin_screen(clear) { d.last_error = ERR_GPU; return false; }

    let vp = camera_view_projection(cam, aspect);
    gpu_uniform_block(STAGE_VERTEX, 0, FrameUniform { view_proj: vp });
    gpu_uniform_block(STAGE_FRAGMENT, 1, light_uniform(d));
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

    let mr = d.meshes[mi];
    let ar = d.materials[ai];
    // A textured material names its image by handle, so releasing the image
    // while the material still uses it is caught here, before the backend sees
    // a stale texture.
    var image_at: i64 = -1;
    if ar.image.id != 0 {
        image_at = image_index(d, ar.image);
        if image_at < 0 { d.last_error = ERR_BAD_HANDLE; return false; }
    }

    gpu_bind_pipeline(ar.pipeline);
    gpu_bind_vertex_buffer(mr.vertex_buffer);
    gpu_bind_index_buffer(mr.index_buffer, mr.index_size);
    gpu_uniform_block(STAGE_VERTEX, 1, DrawUniform { model: model,
                                                     normal: mat4_normal(model) });
    gpu_uniform_block(STAGE_FRAGMENT, 0, MaterialUniform {
        tint: ar.tint,
        params: float4 { if ar.unlit { 1.0 } else { 0.0 }, 0.0, 0.0, 0.0 },
        user0: ar.user0,
        user1: ar.user1,
    });
    if image_at >= 0 {
        gpu_bind_texture(STAGE_FRAGMENT, 0, d.images[image_at].texture, ar.sampler);
    }
    gpu_draw_indexed(mr.index_count);

    d.stats.draws++;
    d.stats.triangles += mr.index_count / 3;
    d.last_error = ERR_NONE;
    return true;
}

// Ends the pass and presents. Returns false when the platform asked the
// program to quit (the window closed, or quit() was called).
fn end_frame(d: Device&) -> bool {
    if !d.frame_open { d.last_error = ERR_NO_FRAME; return false; }
    gpu_end_pass();
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
