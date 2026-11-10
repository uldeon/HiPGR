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

// --- textures and samplers ---------------------------------------------------

fn gpu_texture_rgba8(width: i64, height: i64, pixels: const u8[:]) -> gfx::Texture {
    var desc = gfx::TextureDesc { width: width as i32, height: height as i32 };
    let t = gfx::texture(desc);
    if t.id != 0 && pixels.len != 0 { gfx::update_texture(t, pixels); }
    return t;
}

fn gpu_texture_load(path: const u8[:]) -> gfx::Texture {
    gfx::load_texture(path, 0)
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

// One sampler for one filtering and wrapping. Textures have no mip chain yet,
// so the mip filter never selects anything and is pinned to NEAREST.
fn gpu_sampler(filter: i32, wrap: i32) -> gfx::Sampler {
    let f = gpu_filter(filter);
    let w = gpu_wrap(wrap);
    let desc = gfx::SamplerDesc { min_filter: f, mag_filter: f, mip_filter: gfx::NEAREST,
                                  wrap_u: w, wrap_v: w, wrap_w: w };
    gfx::sampler(desc)
}

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

fn gpu_draw_indexed(indices: i64) { gfx::draw_indexed(indices); }
