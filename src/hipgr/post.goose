// HiPGR: the passes a frame is made of.
//
//   shadow     depth from the light, into a 1024x1024 depth map
//   scene      the renderables, into an RGBA16F target (plus the sky)
//   bloom      bright pass and two blurred halves, at half resolution
//   composite  tone mapping, bloom and gamma, onto the screen
//
// The first two are geometry passes and the last two are full-screen triangles
// with no vertex buffer. Everything here is fixed state owned by the device, so
// a frame allocates nothing.
namespace hipgr;

import vec;
import gfx;
import .state;
import .device;
import .gpu;
import .uniforms;

// Embedded by every program that uses HiPGR, for every backend at once.
let SHADER_FULLSCREEN_VS = embed_shader("shaders/fullscreen.vert");
let SHADER_SKY_FS = embed_shader("shaders/sky.frag");
let SHADER_BRIGHT_FS = embed_shader("shaders/bright.frag");
let SHADER_BLUR_FS = embed_shader("shaders/blur.frag");
let SHADER_COMPOSITE_FS = embed_shader("shaders/composite.frag");
let SHADER_SHADOW_VS = embed_shader("shaders/shadow.vert");
let SHADER_EMPTY_FS = embed_shader("shaders/empty.frag");

// Created on the first frame, then kept: shader compilation is the expensive
// part of pipeline creation, and a frame should not pay it.
fn ensure_pipelines(d: Device&) -> bool {
    if d.pipeline_shadow.id == 0 {
        d.pipeline_shadow = gpu_pipeline_state(SHADER_SHADOW_VS, SHADER_EMPTY_FS,
                                               CULL_BACK, BLEND_NONE, true, true, false);
    }
    if d.pipeline_sky.id == 0 {
        d.pipeline_sky = gpu_pipeline_state(SHADER_FULLSCREEN_VS, SHADER_SKY_FS,
                                            CULL_NONE, BLEND_NONE, false, false, false);
    }
    if d.pipeline_bright.id == 0 {
        d.pipeline_bright = gpu_pipeline_state(SHADER_FULLSCREEN_VS, SHADER_BRIGHT_FS,
                                               CULL_NONE, BLEND_NONE, false, false, false);
    }
    if d.pipeline_blur.id == 0 {
        d.pipeline_blur = gpu_pipeline_state(SHADER_FULLSCREEN_VS, SHADER_BLUR_FS,
                                             CULL_NONE, BLEND_NONE, false, false, false);
    }
    if d.pipeline_composite.id == 0 {
        d.pipeline_composite = gpu_pipeline_state(SHADER_FULLSCREEN_VS, SHADER_COMPOSITE_FS,
                                                  CULL_NONE, BLEND_NONE, false, false, false);
    }
    if d.pipeline_shadow.id == 0 || d.pipeline_sky.id == 0 || d.pipeline_bright.id == 0
       || d.pipeline_blur.id == 0 || d.pipeline_composite.id == 0 {
        d.last_error = ERR_GPU;
        return false;
    }
    return true;
}

// An empty full-screen pass: clear a target, then let the caller draw into it.
fn begin_fullscreen_pass(target: gfx::Texture, clear: float4) -> bool {
    gpu_begin_pass(target, gfx::Texture { 0 }, clear, true, false)
}

// --- shadow pass ---------------------------------------------------------------

// Every mesh casts, whatever its material: a shadow is depth, and depth does not
// care how a surface is shaded. Materials are not consulted, so a custom shader
// cannot break the shadow pass; it can only be wrong about its own lighting.
fn run_shadow_pass(d: Device&, frame: FrameUniform) {
    var nothing = gfx::Texture { 0 };
    if !gpu_begin_pass(nothing, d.targets.shadow, float4 { 0.0, 0.0, 0.0, 1.0 }, false, true) {
        d.last_error = ERR_GPU;
        return;
    }
    gpu_bind_pipeline(d.pipeline_shadow);
    gpu_uniform_block(STAGE_VERTEX, 0, frame);
    for i in d.items.len {
        let item = d.items[i];
        let mi = mesh_index(d, item.mesh);
        if mi < 0 { continue; }
        let mr = d.meshes[mi];
        gpu_bind_vertex_buffer(mr.vertex_buffer);
        gpu_bind_index_buffer(mr.index_buffer, mr.index_size);
        gpu_uniform_block(STAGE_VERTEX, 1, DrawUniform { model: item.model,
                                                         normal: mat4_normal(item.model) });
        gpu_draw_indexed(mr.index_count);
    }
    gpu_end_pass();
}

// --- scene pass -----------------------------------------------------------------

fn run_scene_pass(d: Device&, frame: FrameUniform, clear: float4) {
    let t = d.targets;
    if !gpu_begin_pass(t.hdr, t.depth, clear, true, true) {
        d.last_error = ERR_GPU;
        return;
    }
    // Frame twice: the vertex blocks at set 1, and the copy the fragment
    // shaders read at set 3 (fog colour, shadow parameters).
    gpu_uniform_block(STAGE_VERTEX, 0, frame);
    gpu_uniform_block(STAGE_FRAGMENT, 2, frame);
    gpu_uniform_block(STAGE_FRAGMENT, 1, light_uniform(d));

    if d.sky_enabled && d.sky_cube.id != 0 {
        gpu_bind_pipeline(d.pipeline_sky);
        // The sky shader declares Frame at its own set 3 binding 0, where
        // materials put Material: one push, then the materials overwrite it.
        gpu_uniform_block(STAGE_FRAGMENT, 0, frame);
        gpu_bind_texture(STAGE_FRAGMENT, 0, d.sky_cube, d.sampler_post);
        gpu_draw_fullscreen();
    }

    // The shadow map is the same for every draw in the frame.
    gpu_bind_texture(STAGE_FRAGMENT, 2, t.shadow, d.sampler_shadow);

    for i in d.items.len {
        let item = d.items[i];
        let mi = mesh_index(d, item.mesh);
        let ai = material_index(d, item.material);
        if mi < 0 || ai < 0 { continue; }
        let mr = d.meshes[mi];
        let ar = d.materials[ai];
        gpu_bind_pipeline(ar.pipeline);
        gpu_bind_vertex_buffer(mr.vertex_buffer);
        gpu_bind_index_buffer(mr.index_buffer, mr.index_size);
        gpu_uniform_block(STAGE_VERTEX, 1, DrawUniform { model: item.model,
                                                         normal: mat4_normal(item.model) });
        // A material with no normal map reports zero strength, which is the
        // shader's cue to skip the tangent frame and the extra texture tap.
        let normal_strength = if ar.normal_image.id != 0 { ar.normal_strength } else { 0.0 };
        gpu_uniform_block(STAGE_FRAGMENT, 0,
                          material_uniform(ar.metallic, ar.roughness, normal_strength,
                                           ar.unlit, ar.tint, ar.user0, ar.user1));
        // Only the built-in shader gets HiPGR's own bindings and blocks: a
        // custom shader declares its own, and pushing or binding something a
        // pipeline did not ask for is not something the backend promises.
        if ar.builtin {
            gpu_uniform_block(STAGE_FRAGMENT, 3, surface_uniform(ar.emissive));
            var albedo = d.tex_white;
            if ar.image.id != 0 {
                let at = image_index(d, ar.image);
                if at >= 0 { albedo = d.images[at].texture; }
            }
            var normal_tex = d.tex_flat_normal;
            if ar.normal_image.id != 0 {
                let nt = image_index(d, ar.normal_image);
                if nt >= 0 { normal_tex = d.images[nt].texture; }
            }
            gpu_bind_texture(STAGE_FRAGMENT, 0, albedo, ar.sampler);
            gpu_bind_texture(STAGE_FRAGMENT, 1, normal_tex, ar.sampler);
        }
        gpu_draw_indexed(mr.index_count);
    }
    gpu_end_pass();
}

// --- bloom ------------------------------------------------------------------------

fn run_bloom(d: Device&) {
    if d.bloom_strength <= 0.0 { return; }
    let t = d.targets;
    let half_w = if t.width > 2 { t.width / 2 } else { 1 };
    let half_h = if t.height > 2 { t.height / 2 } else { 1 };

    // What is brighter than the threshold, at half resolution.
    if !begin_fullscreen_pass(t.bloom_a, float4 { 0.0, 0.0, 0.0, 1.0 }) { return; }
    gpu_bind_pipeline(d.pipeline_bright);
    gpu_bind_texture(STAGE_FRAGMENT, 0, t.hdr, d.sampler_post);
    gpu_uniform_block(STAGE_FRAGMENT, 0, post_uniform(d, t.width, t.height, true));
    gpu_draw_fullscreen();
    gpu_end_pass();

    // Horizontal, then vertical: a separable Gaussian.
    if !begin_fullscreen_pass(t.bloom_b, float4 { 0.0, 0.0, 0.0, 1.0 }) { return; }
    gpu_bind_pipeline(d.pipeline_blur);
    gpu_bind_texture(STAGE_FRAGMENT, 0, t.bloom_a, d.sampler_post);
    gpu_uniform_block(STAGE_FRAGMENT, 0, post_uniform(d, half_w, half_h, true));
    gpu_draw_fullscreen();
    gpu_end_pass();

    if !begin_fullscreen_pass(t.bloom_a, float4 { 0.0, 0.0, 0.0, 1.0 }) { return; }
    gpu_bind_pipeline(d.pipeline_blur);
    gpu_bind_texture(STAGE_FRAGMENT, 0, t.bloom_b, d.sampler_post);
    gpu_uniform_block(STAGE_FRAGMENT, 0, post_uniform(d, half_w, half_h, false));
    gpu_draw_fullscreen();
    gpu_end_pass();
}

// --- composite ---------------------------------------------------------------------

fn run_composite(d: Device&, clear: float4) {
    let t = d.targets;
    let size = screen_size(d);
    if !gpu_begin_pass(gpu_screen(), gfx::Texture { 0 }, clear, true, false) {
        d.last_error = ERR_GPU;
        return;
    }
    gpu_bind_pipeline(d.pipeline_composite);
    gpu_bind_texture(STAGE_FRAGMENT, 0, t.hdr, d.sampler_post);
    // Bound even when bloom is off; the strength in the block decides.
    gpu_bind_texture(STAGE_FRAGMENT, 1, t.bloom_a, d.sampler_post);
    gpu_uniform_block(STAGE_FRAGMENT, 0, post_uniform(d, size.x, size.y, true));
    gpu_draw_fullscreen();
    gpu_end_pass();
}
