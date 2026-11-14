// HiPGR: the graphics backend boundary.
//
// This is the only module that talks to Goose's `gfx` module for device,
// pass, pipeline and draw state. Everything above it speaks HiPGR types and
// uniform byte blocks, so replacing the backend (a native Vulkan layer, for
// instance) means reimplementing this file, not the renderer.
//
// Anything backend-specific about the contract is recorded here:
//   * vertex inputs come from one packed struct per vertex, in shader
//     location order from buffer slot 0;
//   * uniform blocks are std140, pushed as bytes;
//   * vertex shader bindings are set 1, fragment shader bindings set 3,
//     fragment samplers set 2;
//   * clip space is y-up, depth 0..1, texture v=0 at the top row.
namespace hipgr;

import vec;
import gfx;
import .state;

// Uniform-block sets of the backend. Vertex shaders read set 1, fragment
// shaders read set 3; samplers are set 2 in fragment shaders.
let STAGE_VERTEX: i32 = 0;
let STAGE_FRAGMENT: i32 = 1;

// Texture formats the renderer uses, named so nothing above this file needs a
// backend constant.
let FORMAT_RGBA8: i32 = gfx::RGBA8;
let FORMAT_RGBA16F: i32 = gfx::RGBA16F;

let TEXTURE_SAMPLED: i32 = gfx::SAMPLED;

// --- device and presentation -------------------------------------------------

fn gpu_open(title: const u8[:], width: i64, height: i64) -> bool {
    gfx::open(title, width, height, gfx::WINDOW_RESIZABLE)
}

fn gpu_open_headless(width: i64, height: i64) -> bool {
    gfx::open_headless(width, height)
}

fn gpu_close() { gfx::close(); }

fn gpu_driver() -> u8[>..] { gfx::driver() }

fn gpu_backend_error() -> u8[>..] { gfx::error() }

fn gpu_check() { gfx::check(); }

fn gpu_screen_size() -> int2 { gfx::screen_size() }

fn gpu_begin_screen(clear: float4) -> bool { gfx::begin_screen(clear) }

fn gpu_screen() -> gfx::Texture { gfx::screen() }

// A pass into one target with one depth target, both cleared. Depth { 0 } means
// no depth buffer, which is what a full-screen pass uses.
fn gpu_begin_pass(target: gfx::Texture, depth: gfx::Texture, clear: float4,
                  clear_color: bool, clear_depth: bool) -> bool {
    var desc = gfx::PassDesc { depth: depth, clear_color: clear_color,
                               clear_depth: clear_depth, color_value: clear,
                               depth_value: 1.0 };
    desc.color[0] = target;
    gfx::begin_pass(desc)
}

// The same, resolving a multisampled target into a single-sample one when the
// pass ends. The resolve target must be the same size and format, which is what
// the renderer's target set guarantees.
fn gpu_begin_pass_resolve(target: gfx::Texture, depth: gfx::Texture,
                          resolve: gfx::Texture, clear: float4,
                          clear_color: bool, clear_depth: bool) -> bool {
    var desc = gfx::PassDesc { depth: depth, clear_color: clear_color,
                               clear_depth: clear_depth, color_value: clear,
                               depth_value: 1.0 };
    desc.color[0] = target;
    desc.resolve[0] = resolve;
    gfx::begin_pass(desc)
}

fn gpu_end_pass() { gfx::end_pass(); }

fn gpu_present() -> bool { return gfx::frame(); }

fn gpu_quit() { gfx::quit(); }

fn gpu_read_pixels() -> u8[>..] { gfx::read_pixels(gfx::screen()) }

fn gpu_screenshot(path: const u8[:]) -> bool { gfx::screenshot(path) }

fn gpu_time() -> f64 { gfx::time() }

fn gpu_delta_time() -> f64 { gfx::delta_time() }

fn gpu_key_down(name: const u8[:]) -> bool { gfx::key_down(name) }

fn gpu_key_pressed(name: const u8[:]) -> bool { gfx::key_pressed(name) }

fn gpu_mouse_delta() -> float2 { gfx::mouse_delta() }

fn gpu_mouse_pos() -> float2 { gfx::mouse_pos() }

fn gpu_set_mouse_relative(on: bool) -> bool { gfx::set_mouse_relative(on) }

// --- buffers -----------------------------------------------------------------

fn gpu_vertex_buffer(data: const u8[:]) -> gfx::Buffer { gfx::vertex_buffer(data) }

fn gpu_index_buffer(data: const u8[:]) -> gfx::Buffer { gfx::index_buffer(data) }

fn gpu_update_buffer(b: gfx::Buffer, data: const u8[:]) -> bool {
    gfx::update_buffer(b, data)
}

fn gpu_buffer_size(b: gfx::Buffer) -> i64 { gfx::buffer_size(b) }

fn gpu_release_buffer(b: gfx::Buffer) { gfx::release(b); }

// A vertex buffer with room for `bytes` bytes, filled with the data given. The
// per-frame instance buffer is created once per capacity and then rewritten.
fn gpu_empty_vertex_buffer(bytes: i64) -> gfx::Buffer {
    let none: u8[>..] = [];
    gfx::buffer(gfx::BUFFER_VERTEX, bytes, none)
}

// --- textures and samplers ---------------------------------------------------

// A texture to draw into and then sample: the HDR target and the bloom chain.
fn gpu_render_target(width: i64, height: i64, format: i32) -> gfx::Texture {
    gfx::render_target(width, height, format)
}

// A multisampled colour target. It can only be drawn into (it is not sampled:
// the resolve in the same pass is what produces a sampleable texture), so its
// usage is the target alone.
fn gpu_render_target_ms(width: i64, height: i64, format: i32, samples: i64) -> gfx::Texture {
    let desc = gfx::TextureDesc { format: format, usage: gfx::COLOR_TARGET,
                                  width: width as i32, height: height as i32,
                                  mips: 1, samples: samples as i32 };
    gfx::texture(desc)
}

// The same for a depth buffer that is only a target.
fn gpu_depth_only_ms(width: i64, height: i64, samples: i64) -> gfx::Texture {
    let desc = gfx::TextureDesc { format: gfx::DEPTH, usage: gfx::DEPTH_TARGET,
                                  width: width as i32, height: height as i32,
                                  mips: 1, samples: samples as i32 };
    gfx::texture(desc)
}

// A depth buffer that can also be sampled, as a shadow map is.
fn gpu_depth_target(width: i64, height: i64) -> gfx::Texture {
    gfx::depth_target(width, height)
}

// A depth buffer that is only a target: the one the scene is drawn with.
fn gpu_depth_only(width: i64, height: i64) -> gfx::Texture {
    gfx::texture2d(width, height, gfx::DEPTH, gfx::DEPTH_TARGET)
}

// A cube map for the sky, one face at a time.
fn gpu_texture_cube(size: i64, format: i32, usage: i32) -> gfx::Texture {
    gfx::texture_cube(size, format, usage)
}

fn gpu_update_texture_layer(t: gfx::Texture, layer: i32, pixels: const u8[:]) -> bool {
    gfx::update_texture(t, gfx::Region { layer: layer }, pixels)
}

// A cube map with its whole mip chain, for a prefiltered environment: mip n is
// the radiance band the shader reads at roughness n / (mips - 1).
fn gpu_texture_cube_mips(size: i64, format: i32, usage: i32) -> gfx::Texture {
    let desc = gfx::TextureDesc { kind: gfx::TEXTURE_CUBE, format: format, usage: usage,
                                  width: size as i32, height: size as i32, mips: 0 };
    gfx::texture(desc)
}

fn gpu_update_texture_mip(t: gfx::Texture, mip: i32, layer: i32, pixels: const u8[:]) -> bool {
    gfx::update_texture(t, gfx::Region { mip: mip, layer: layer }, pixels)
}

// Textures have no generated mips, so every other sampler pins the mip filter to
// NEAREST; this one is for a cube map whose mips are levels of detail, read
// three-dimensionally: minification blurs along the mip chain, never between
// approximations of it.
fn gpu_sampler_mips() -> gfx::Sampler {
    let desc = gfx::SamplerDesc { min_filter: gfx::LINEAR, mag_filter: gfx::LINEAR,
                                  mip_filter: gfx::LINEAR, wrap_u: gfx::CLAMP,
                                  wrap_v: gfx::CLAMP, wrap_w: gfx::CLAMP };
    gfx::sampler(desc)
}

fn gpu_texture_rgba8(width: i64, height: i64, pixels: const u8[:]) -> gfx::Texture {
    var desc = gfx::TextureDesc { width: width as i32, height: height as i32 };
    let t = gfx::texture(desc);
    if t.id != 0 && pixels.len != 0 { gfx::update_texture(t, pixels); }
    return t;
}

// An RGBA8 texture with an optional sRGB transfer function on sampling (so the
// shader sees linear values from an image authored in sRGB) and an optional full
// mip chain, generated from level 0 on the GPU. Mips are what a minified texture
// needs: without them a sampling filter reads four texels of one level and the
// result shimmers.
fn gpu_texture_rgba8_ex(width: i64, height: i64, pixels: const u8[:], srgb: bool,
                        mips: bool) -> gfx::Texture {
    let desc = gfx::TextureDesc { format: if srgb { gfx::RGBA8_SRGB } else { gfx::RGBA8 },
                                  usage: gfx::SAMPLED, width: width as i32, height: height as i32,
                                  mips: if mips { 0 } else { 1 } };
    let t = gfx::texture(desc);
    if t.id == 0 { return t; }
    if pixels.len != 0 && !gfx::update_texture(t, pixels) {
        gfx::release(t);
        return gfx::Texture { 0 };
    }
    // Recorded, not run here: the backend puts it in the frame's command buffer,
    // so the chain is filled by the time anything samples it.
    if mips && height > 1 { gfx::generate_mips(t); }
    return t;
}

// The texels of one mip level, for tests that check what generation produced.
fn gpu_read_texture_mip(t: gfx::Texture, mip: i32, out: u8[:]) -> bool {
    gfx::read_texture(t, gfx::Region { mip: mip }, out)
}

fn gpu_texture_load(path: const u8[:]) -> gfx::Texture {
    gfx::load_texture(path, 0)
}

// A file decoded as sRGB with a full mip chain: the usual way an albedo map
// arrives.
fn gpu_texture_load_mips(path: const u8[:]) -> gfx::Texture {
    gfx::load_texture(path, gfx::LOAD_SRGB | gfx::LOAD_MIPS)
}

fn gpu_texture_size(t: gfx::Texture) -> int2 {
    let info = gfx::texture_info(t);
    return int2 { info.width, info.height };
}

fn gpu_release_texture(t: gfx::Texture) { gfx::release(t); }

// HiPGR's filter and wrap values, in the backend's numbering. A match rather
// than a cast, so a backend whose constants move is caught here.
fn gpu_filter(f: i32) -> i32 {
    if f == FILTER_NEAREST { gfx::NEAREST } else { gfx::LINEAR }
}

fn gpu_wrap(w: i32) -> i32 {
    match w {
        1 => gfx::REPEAT,
        _ => gfx::CLAMP,
    }
}

// One sampler for one filtering and wrapping. The mip filter is linear for every
// material: a texture with one level (the default) has nothing to interpolate,
// and a texture with a chain gets the smooth minification that chain exists for.
fn gpu_sampler(filter: i32, wrap: i32) -> gfx::Sampler {
    let f = gpu_filter(filter);
    let w = gpu_wrap(wrap);
    let desc = gfx::SamplerDesc { min_filter: f, mag_filter: f, mip_filter: gfx::LINEAR,
                                  wrap_u: w, wrap_v: w, wrap_w: w };
    gfx::sampler(desc)
}

// The sampler a shadow map is read with: hardware depth comparison, so the
// fragment shader can ask "is this fragment nearer than the light's depth?"
// directly, and a texture tap filters four depths at once.
fn gpu_shadow_sampler() -> gfx::Sampler { gfx::shadow_sampler() }

fn gpu_release_sampler(s: gfx::Sampler) { gfx::release(s); }

// --- pipelines ---------------------------------------------------------------

fn gpu_cull(c: i32) -> i32 {
    match c {
        1 => gfx::CULL_BACK,
        2 => gfx::CULL_FRONT,
        _ => gfx::CULL_NONE,
    }
}

fn gpu_blend(b: i32) -> i32 {
    match b {
        1 => gfx::BLEND_ALPHA,
        2 => gfx::BLEND_ADD,
        _ => gfx::BLEND_NONE,
    }
}

// A pipeline for a vertex + fragment pair and one state. It is not tied to the
// targets it draws into: the backend makes that variant for the pass it is
// first bound in.
fn gpu_pipeline_state(vs: const u8[:], fs: const u8[:], cull: i32, blend: i32,
                      depth_test: bool, depth_write: bool, wireframe: bool) -> gfx::Pipeline {
    let desc = gfx::PipelineDesc { cull: gpu_cull(cull), blend: gpu_blend(blend),
                                   depth_test: depth_test, depth_write: depth_write,
                                   wireframe: wireframe };
    gfx::pipeline(vs, fs, desc)
}

// The same, with the shader's inputs from `instance_location` on read per
// instance from vertex buffer 1. The backend derives the layout, and so the
// stride, from the shader's declarations in location order.
fn gpu_pipeline_state_instanced(vs: const u8[:], fs: const u8[:], cull: i32, blend: i32,
                                depth_test: bool, depth_write: bool, wireframe: bool,
                                instance_location: i32) -> gfx::Pipeline {
    let desc = gfx::PipelineDesc { cull: gpu_cull(cull), blend: gpu_blend(blend),
                                   depth_test: depth_test, depth_write: depth_write,
                                   wireframe: wireframe,
                                   instance_location: instance_location };
    gfx::pipeline(vs, fs, desc)
}

fn gpu_release_pipeline(p: gfx::Pipeline) { gfx::release(p); }

// --- draw state --------------------------------------------------------------

fn gpu_bind_pipeline(p: gfx::Pipeline) { gfx::bind(p); }

fn gpu_bind_vertex_buffer(b: gfx::Buffer) { gfx::bind_vertex_buffer(b); }

// index_size is the width of one index in bytes: 2 or 4.
fn gpu_bind_index_buffer(b: gfx::Buffer, index_size: i64) {
    gfx::bind_index_buffer(b, index_size);
}

fn gpu_bind_texture(stage: i32, slot: i64, t: gfx::Texture, s: gfx::Sampler) {
    gfx::bind_texture(stage, slot, t, s);
}

// Any flat struct as a uniform block, in bytes, exactly as the shader's
// std140 block lays it out.
fn gpu_uniform_block<T>(stage: i32, slot: i64, u: T) {
    let one: T[1] = [u];
    gfx::push_uniforms(stage, slot, bytes_of(one));
}

// The per-instance element buffer: vertex buffer 1.
fn gpu_bind_instance_buffer(b: gfx::Buffer) { gfx::bind_vertex_buffer(1, b, 0); }

fn gpu_draw_indexed(indices: i64) { gfx::draw_indexed(indices); }

// One geometry, `instances` transforms starting at `first_instance` in vertex
// buffer 1. The shaders never read gl_InstanceIndex, which is the one thing a
// first instance that is not zero breaks on Direct3D 12.
fn gpu_draw_indexed_instanced(indices: i64, instances: i64, first_instance: i64) {
    gfx::draw_indexed(indices, instances, 0, 0, first_instance)
}

// Three vertices and no vertex buffer: the full-screen triangle the post
// passes draw, with positions from gl_VertexIndex in the shader.
fn gpu_draw_fullscreen() { gfx::draw(3); }

fn gpu_viewport(x: f32, y: f32, w: f32, h: f32) { gfx::viewport(x, y, w, h); }
