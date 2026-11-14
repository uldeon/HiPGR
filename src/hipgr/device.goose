// HiPGR: the device, its resource records, and error reporting.
//
// Goose has no destructors and no heap, so ownership is explicit: the Device
// owns every GPU object it created, resource creation returns a generation-
// checked handle, and release() invalidates the handle and frees the GPU
// object immediately. closing the device releases whatever is still live.
namespace hipgr;

import vec;
import gfx;
import .env;
import .handle;
import .camera;
import .math;
import .state;
import .gpu;

// --- errors ------------------------------------------------------------------

let ERR_NONE: i32 = 0;
let ERR_NO_DEVICE: i32 = 1;
let ERR_NOT_OPEN: i32 = 2;
let ERR_ALREADY_OPEN: i32 = 3;
let ERR_NO_FRAME: i32 = 4;
let ERR_FRAME_OPEN: i32 = 5;
let ERR_BAD_HANDLE: i32 = 6;
let ERR_BAD_ARGUMENT: i32 = 7;
let ERR_GPU: i32 = 8;
let ERR_TOO_MANY: i32 = 9;

// What an error code means, for logging. The backend's own last message is
// backend_error().
fn error_text(code: i32) -> u8[:] {
    match code {
        0 => "ok",
        1 => "no GPU device could be opened",
        2 => "the device is not open",
        3 => "the device is already open",
        4 => "no frame is open: call begin_frame first",
        5 => "a frame is already open",
        6 => "invalid or released handle",
        7 => "invalid argument",
        8 => "the graphics backend rejected the call",
        9 => "too many resources: handle index space exhausted",
        _ => "unknown error",
    }
}

// --- public description of what was created -----------------------------------

struct Stats {
    frames: i64 = 0,
    draws: i64 = 0,
    triangles: i64 = 0,
    // Draws the culler removed from the scene pass, draw batches the scene pass
    // was reduced to, and instances those batches covered. All cumulative, like
    // draws: the difference across one frame is what that frame cost.
    culled: i64 = 0,
    batches: i64 = 0,
    instances: i64 = 0,
    // Objects drawn by instanced draws (a subset of draws).
    instanced: i64 = 0,
    // The shadow pass's own counters: casters the light's box excluded, and the
    // draw calls it took to render the rest.
    shadow_culled: i64 = 0,
    shadow_batches: i64 = 0,
    shadow_instances: i64 = 0,
    meshes: i64 = 0,
    images: i64 = 0,
    materials: i64 = 0,
    shaders: i64 = 0,
    // Pipelines and samplers actually created, not materials: materials with
    // the same state share both, so this is the cache size.
    pipelines: i64 = 0,
    samplers: i64 = 0,
}

struct MeshInfo {
    vertices: i64 = 0,
    indices: i64 = 0,
    triangles: i64 = 0,
    vertex_bytes: i64 = 0,
    index_bytes: i64 = 0,
    // 2 or 4 bytes: a mesh with more than 65536 vertices is indexed with 32-bit
    // indices, chosen when it was created.
    index_size: i64 = 0,
}

struct ImageInfo {
    width: i64 = 0,
    height: i64 = 0,
}

// --- internal records ----------------------------------------------------------

// A box in a mesh's own space, transformed by the model matrix to cull it.
struct Bounds {
    min: float3 = float3 { 0.0, 0.0, 0.0 },
    max: float3 = float3 { 0.0, 0.0, 0.0 },
}

struct MeshRec {
    generation: i32 = 0,
    live: bool = false,
    vertex_buffer: gfx::Buffer = gfx::Buffer { 0 },
    index_buffer: gfx::Buffer = gfx::Buffer { 0 },
    vertex_count: i64 = 0,
    index_count: i64 = 0,
    vertex_bytes: i64 = 0,
    index_bytes: i64 = 0,
    // 2 or 4: the width of one index, decided when the mesh was created from
    // its vertex count and needed again on every draw.
    index_size: i64 = 2,
    bounds: Bounds = Bounds {},
}

struct ImageRec {
    generation: i32 = 0,
    live: bool = false,
    texture: gfx::Texture = gfx::Texture { 0 },
    width: i64 = 0,
    height: i64 = 0,
}

struct MaterialRec {
    generation: i32 = 0,
    live: bool = false,
    pipeline: gfx::Pipeline = gfx::Pipeline { 0 },
    // The image is named by its public handle, not a copied backend texture:
    // the handle can be checked, so releasing the image while a material still
    // uses it is an error at draw time instead of a stale texture object.
    image: Image = Image { 0 },
    normal_image: Image = Image { 0 },
    // Sampled with the material's own sampler, shared with every material that
    // asked for the same filtering.
    sampler: gfx::Sampler = gfx::Sampler { 0 },
    tint: float4 = float4 { 1.0, 1.0, 1.0, 1.0 },
    // The images a custom shader samples, in its sampler order. Only the first
    // `texture_count` are bound; an unset slot is a white 1x1 texel.
    textures: Image[4] = [Image { 0 }; 4],
    texture_count: i64 = 0,
    use_shadow_map: bool = false,
    // Two float4s of application data, handed to a custom shader as
    // Material.user0 and Material.user1.
    user0: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    user1: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    emissive: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    // The application's own data, the `v` of the Material block.
    params: float4[8] = [float4_0; 8],
    metallic: f32 = 0.0,
    roughness: f32 = 1.0,
    normal_strength: f32 = 1.0,
    unlit: bool = false,
    // Kept here as well as in the pipeline record: the renderer decides whether
    // a draw is transparent (and so sorted back to front) from the material.
    blend: i32 = BLEND_NONE,
    // The instanced variant of `pipeline`, made the first time a batch needs it.
    pipeline_instanced: gfx::Pipeline = gfx::Pipeline { 0 },
    // True for the built-in shader: only then does the renderer supply HiPGR's
    // own texture bindings, because a custom shader declares its own.
    builtin: bool = true,
}

// A vertex + fragment pair, kept so materials and pipelines can name it. The
// bytes are embedded shader code, compiled into the program.
struct ShaderRec {
    generation: i32 = 0,
    live: bool = false,
    vs: const u8[:] = "",
    fs: const u8[:] = "",
}

// One cached pipeline state. Two materials with the same shader and the same
// state share a pipeline; a different cull, blend or depth setting makes a new
// one. This is the cache, not a public handle: applications describe state on
// each material and the renderer deduplicates it.
struct PipelineRec {
    shader: u32 = 0,
    cull: i32 = 0,
    blend: i32 = 0,
    depth_test: bool = false,
    depth_write: bool = false,
    wireframe: bool = false,
    // True for the per-instance variant of the built-in shader, which reads
    // its matrices from vertex buffer 1 instead of the Draw block. Only the
    // built-in pair has one: a custom shader's vertex layout is its own.
    instanced: bool = false,
    pipeline: gfx::Pipeline = gfx::Pipeline { 0 },
}

// One cached sampler, addressed by filtering and wrapping.
struct SamplerRec {
    filter: i32 = 0,
    wrap: i32 = 0,
    sampler: gfx::Sampler = gfx::Sampler { 0 },
}

// How many point lights a device can have at once. The built-in shaders declare
// the same number; a scene that sets more is clamped, not broken.
let MAX_POINT_LIGHTS: i64 = 8;

// A point light: where it is, its colour, and how far it reaches. Light falls
// off smoothly to nothing at `radius`, so a light has finite cost in a shader
// and no cut-off seam.
struct PointLight {
    position: float3 = float3 { 0.0, 0.0, 0.0 },
    color: float3 = float3 { 1.0, 1.0, 1.0 },
    radius: f32 = 1.0,
}

// One submitted renderable. draw() records these; end_frame() executes them,
// because the shadow pass has to run before the scene pass and the scene pass
// before the post chain. Recording also leaves room for sorting and culling in
// 0.4 without changing the API.
struct DrawItem {
    mesh: Mesh = Mesh { 0 },
    material: Material = Material { 0 },
    model: Mat4 = Mat4 { m: gfx::mat4_identity },
}

// One entry of a frame's draw order: the recorded item, the sort keys that
// decide where it goes, and how far it is from the camera (squared, for the
// back-to-front order transparency needs).
struct PlanItem {
    index: i64 = 0,          // into items
    mesh_id: i64 = 0,
    material_id: i64 = 0,
    depth: f32 = 0.0,
    transparent: bool = false,
}

// A run of the plan that one draw call covers. `plan_start`/`count` address the
// plan; `instance_start` addresses the per-frame instance buffer when the run is
// drawn instanced.
struct Batch {
    plan_start: i64 = 0,
    count: i64 = 0,
    instance_start: i64 = 0,
    instanced: bool = false,
}

// The per-instance element the instanced vertex shader reads from vertex buffer
// 1: the model matrix and its normal matrix, exactly what the Draw block holds
// for a non-instanced draw, so both paths do the same arithmetic. 128 bytes,
// eight vec4s, in shader location order.
struct Instance {
    model: Mat4 = Mat4 { m: gfx::mat4_identity },
    normal: Mat4 = Mat4 { m: gfx::mat4_identity },
}

// The shadow pass reads only the model matrix, so its pool is 64 bytes per
// instance instead of 128: the backend derives the stride from the shader.
struct ShadowInstance {
    model: Mat4 = Mat4 { m: gfx::mat4_identity },
}

// Screen-sized render targets and the fixed-size shadow map, owned by the
// device like everything else.
struct Targets {
    hdr: gfx::Texture = gfx::Texture { 0 },        // RGBA16F: the scene, before tone mapping
    // When MSAA is on, the scene is drawn into these two and resolved into hdr.
    // They are zero at 1 sample per pixel, which is the default.
    hdr_ms: gfx::Texture = gfx::Texture { 0 },
    depth_ms: gfx::Texture = gfx::Texture { 0 },
    depth: gfx::Texture = gfx::Texture { 0 },      // the scene's depth buffer
    bloom_a: gfx::Texture = gfx::Texture { 0 },    // half size: bright pass, then blur
    bloom_b: gfx::Texture = gfx::Texture { 0 },    // half size: the other blur direction
    shadow: gfx::Texture = gfx::Texture { 0 },     // depth from the light, near cascade
    // The far cascade. It exists in both modes so the shader can bind one
    // sampler slot unconditionally; in single-box mode nothing writes it.
    shadow_far: gfx::Texture = gfx::Texture { 0 },
    width: i64 = 0,
    height: i64 = 0,
    samples: i64 = 1,
}

// --- the device ------------------------------------------------------------------
//
// A root struct: every growable array is its own storage root, sharing the
// device's lifetime. Fields named gpu_ are backend implementation details and
// change between minor versions; the handle types are the public surface.
root struct Device {
    meshes: MeshRec[>..] = [],
    images: ImageRec[>..] = [],
    materials: MaterialRec[>..] = [],
    shaders: ShaderRec[>..] = [],
    pipelines: PipelineRec[>..] = [],
    samplers: SamplerRec[>..] = [],
    // Point lights for this device, up to MAX_POINT_LIGHTS; they are pushed to
    // every draw as one light block.
    lights: PointLight[>..] = [],
    // The frame being submitted: draw() appends, end_frame() renders and clears.
    items: DrawItem[>..] = [],
    // The frame's draw order and batches, rebuilt by end_frame: culled, opaque
    // first, transparent back to front, then grouped into draw calls.
    plan: PlanItem[>..] = [],
    batches: Batch[>..] = [],
    instances: Instance[>..] = [],
    instance_buffer: gfx::Buffer = gfx::Buffer { 0 },
    instance_capacity: i64 = 0,
    // The same, for the shadow pass: the casters that survive the light's box,
    // in submission order, and their model matrices.
    item_bounds: Bounds[>..] = [],
    shadow_plan: i64[>..] = [],
    shadow_batches: Batch[>..] = [],
    shadow_instances: ShadowInstance[>..] = [],
    shadow_instance_buffer: gfx::Buffer = gfx::Buffer { 0 },
    shadow_instance_capacity: i64 = 0,

    targets: Targets = Targets {},

    // Post and lighting settings. The defaults are QUALITY_MODERN.
    exposure: f32 = 1.0,
    tonemap: i32 = TONEMAP_ACES,
    bloom_strength: f32 = 0.35,
    bloom_threshold: f32 = 1.0,
    shadows: bool = true,
    shadow_center: float3 = float3 { 0.0, 0.0, 0.0 },
    shadow_radius: f32 = 8.0,
    shadow_bias: f32 = 0.0015,
    // One box around a fixed centre (the 0.3 behaviour), or two boxes that
    // follow the camera.
    shadow_mode: i64 = SHADOW_FIXED,
    shadow_near: f32 = 24.0,
    shadow_far: f32 = 72.0,
    sky_enabled: bool = true,
    sky_horizon: float3 = float3 { 0.55, 0.65, 0.80 },
    sky_zenith: float3 = float3 { 0.12, 0.26, 0.55 },
    fog_density: f32 = 0.012,
    // Samples per pixel in the scene pass: 1, 2, 4 or 8. Above 1 the pass draws
    // into a multisampled target and resolves it, which is what turns a stair-
    // stepped edge into a gradient. The shadow map is not multisampled.
    msaa: i64 = 1,
    // Off-screen objects are skipped in the scene pass, and runs of draws that
    // share geometry and material become one instanced draw. Both change no
    // pixels (the tests compare them against the unoptimised path); both can be
    // switched off, which is what that comparison does.
    culling: bool = true,
    batching: bool = true,
    sky_cube: gfx::Texture = gfx::Texture { 0 },
    // Image-based lighting from the sky, and how much of it to add. The cubes
    // are built with the sky cube and kept for the device's lifetime.
    ibl: f32 = 1.0,
    env_irradiance: gfx::Texture = gfx::Texture { 0 },
    env_prefiltered: gfx::Texture = gfx::Texture { 0 },

    // Pipelines and samplers of the fixed passes, created on first frame use.
    pipeline_shadow: gfx::Pipeline = gfx::Pipeline { 0 },
    pipeline_shadow_instanced: gfx::Pipeline = gfx::Pipeline { 0 },
    pipeline_sky: gfx::Pipeline = gfx::Pipeline { 0 },
    pipeline_bright: gfx::Pipeline = gfx::Pipeline { 0 },
    pipeline_blur: gfx::Pipeline = gfx::Pipeline { 0 },
    pipeline_composite: gfx::Pipeline = gfx::Pipeline { 0 },
    sampler_post: gfx::Sampler = gfx::Sampler { 0 },
    sampler_shadow: gfx::Sampler = gfx::Sampler { 0 },
    sampler_mips: gfx::Sampler = gfx::Sampler { 0 },

    // 1x1 defaults so one shader serves every built-in material: white where a
    // material names no albedo, a flat normal where it names no normal map.
    tex_white: gfx::Texture = gfx::Texture { 0 },
    tex_flat_normal: gfx::Texture = gfx::Texture { 0 },

    opened: bool = false,
    headless: bool = false,
    frame_open: bool = false,
    last_error: i32 = 0,
    stats: Stats = Stats {},

    // Light used by the built-in materials: a direction the light travels in,
    // a colour, and an ambient term.
    light_direction: float3 = float3 { -0.4, -0.8, -0.6 },
    light_color: float3 = float3 { 1.0, 1.0, 1.0 },
    ambient: f32 = 0.25,

    // The built-in shader pair, created the first time a material needs it.
    shader_mesh: Shader = Shader { 0 },

    // Frame state recorded by begin_frame and used by end_frame.
    camera: Camera = Camera {},
    clear_color: float4 = float4 { 0.0, 0.0, 0.0, 1.0 },
}

// --- device state --------------------------------------------------------------

fn is_open(d: Device&) -> bool { d.opened }

fn error_code(d: Device&) -> i32 { d.last_error }

fn ok(d: Device&) -> bool { d.last_error == ERR_NONE }

fn clear_error(d: Device&) { d.last_error = ERR_NONE; }

fn stats(d: Device&) -> Stats { d.stats }

fn driver(d: Device&) -> u8[>..] { gpu_driver() }

// The backend's own message for its last failing call, when error_code() is
// ERR_GPU or ERR_NO_DEVICE.
fn backend_error() -> u8[>..] { gpu_backend_error() }

fn screen_size(d: Device&) -> int2 { gpu_screen_size() }

// --- records -------------------------------------------------------------------

fn mesh_index(d: Device&, h: Mesh) -> i64 {
    if h.id == 0 { return -1; }
    let i = handle_index(h.id);
    if i < 0 || i >= d.meshes.len { return -1; }
    if d.meshes[i].generation != handle_generation(h.id) || !d.meshes[i].live { return -1; }
    return i;
}

fn image_index(d: Device&, h: Image) -> i64 {
    if h.id == 0 { return -1; }
    let i = handle_index(h.id);
    if i < 0 || i >= d.images.len { return -1; }
    if d.images[i].generation != handle_generation(h.id) || !d.images[i].live { return -1; }
    return i;
}

fn material_index(d: Device&, h: Material) -> i64 {
    if h.id == 0 { return -1; }
    let i = handle_index(h.id);
    if i < 0 || i >= d.materials.len { return -1; }
    if d.materials[i].generation != handle_generation(h.id) || !d.materials[i].live { return -1; }
    return i;
}

fn shader_index(d: Device&, h: Shader) -> i64 {
    if h.id == 0 { return -1; }
    let i = handle_index(h.id);
    if i < 0 || i >= d.shaders.len { return -1; }
    if d.shaders[i].generation != handle_generation(h.id) || !d.shaders[i].live { return -1; }
    return i;
}

fn alloc_mesh(d: Device&, vertex_buffer: gfx::Buffer, index_buffer: gfx::Buffer,
              vertex_count: i64, index_count: i64, index_size: i64,
              bounds: Bounds) -> Mesh {
    let i = d.meshes.len;
    if i >= (1 << HANDLE_INDEX_BITS) { d.last_error = ERR_TOO_MANY; return Mesh { 0 }; }
    d.meshes.push(MeshRec {
        generation: 1,
        live: true,
        vertex_buffer: vertex_buffer,
        index_buffer: index_buffer,
        vertex_count: vertex_count,
        index_count: index_count,
        vertex_bytes: gpu_buffer_size(vertex_buffer),
        index_bytes: gpu_buffer_size(index_buffer),
        index_size: index_size,
        bounds: bounds,
    });
    d.stats.meshes++;
    return Mesh { id: handle_make(i, 1) };
}

fn alloc_shader(d: Device&, vs: const u8[:], fs: const u8[:]) -> Shader {
    let i = d.shaders.len;
    if i >= (1 << HANDLE_INDEX_BITS) { d.last_error = ERR_TOO_MANY; return Shader { 0 }; }
    d.shaders.push(ShaderRec { generation: 1, live: true, vs: vs, fs: fs });
    d.stats.shaders++;
    return Shader { id: handle_make(i, 1) };
}

fn alloc_pipeline(d: Device&, shader: Shader, cull: i32, blend: i32, depth_test: bool,
                  depth_write: bool, wireframe: bool, instanced: bool,
                  pipeline: gfx::Pipeline) {
    d.pipelines.push(PipelineRec { shader: shader.id, cull: cull, blend: blend,
                                   depth_test: depth_test, depth_write: depth_write,
                                   wireframe: wireframe, instanced: instanced,
                                   pipeline: pipeline });
    d.stats.pipelines++;
}

fn alloc_sampler(d: Device&, filter: i32, wrap: i32, sampler: gfx::Sampler) {
    d.samplers.push(SamplerRec { filter: filter, wrap: wrap, sampler: sampler });
    d.stats.samplers++;
}

fn alloc_image(d: Device&, texture: gfx::Texture, width: i64, height: i64) -> Image {
    let i = d.images.len;
    if i >= (1 << HANDLE_INDEX_BITS) { d.last_error = ERR_TOO_MANY; return Image { 0 }; }
    d.images.push(ImageRec { generation: 1, live: true, texture: texture,
                             width: width, height: height });
    d.stats.images++;
    return Image { id: handle_make(i, 1) };
}

// The targets a frame renders into, rebuilt when the screen size changes.
fn ensure_targets(d: Device&, width: i64, height: i64) -> bool {
    if d.targets.width == width && d.targets.height == height
       && d.targets.samples == d.msaa && d.targets.hdr.id != 0 { return true; }
    // The shadow maps are a fixed size and outlive a resize, so they are taken
    // out of the struct before the rest is released and put back afterwards.
    let shadow = d.targets.shadow;
    let shadow_far = d.targets.shadow_far;
    d.targets.shadow = gfx::Texture { 0 };
    d.targets.shadow_far = gfx::Texture { 0 };
    release_targets(d);
    let hdr = gpu_render_target(width, height, FORMAT_RGBA16F);
    if hdr.id == 0 { d.last_error = ERR_GPU; return false; }
    // With MSAA the scene goes into the multisampled pair and is resolved into
    // hdr; without it, straight into hdr with a single-sample depth buffer.
    var hdr_ms = gfx::Texture { 0 };
    var depth_ms = gfx::Texture { 0 };
    var depth = gfx::Texture { 0 };
    if d.msaa > 1 {
        hdr_ms = gpu_render_target_ms(width, height, FORMAT_RGBA16F, d.msaa);
        depth_ms = gpu_depth_only_ms(width, height, d.msaa);
        if hdr_ms.id == 0 || depth_ms.id == 0 {
            gpu_release_texture(hdr);
            if hdr_ms.id != 0 { gpu_release_texture(hdr_ms); }
            if depth_ms.id != 0 { gpu_release_texture(depth_ms); }
            d.last_error = ERR_GPU;
            return false;
        }
    } else {
        depth = gpu_depth_only(width, height);
        if depth.id == 0 { gpu_release_texture(hdr); d.last_error = ERR_GPU; return false; }
    }
    // Bloom works at half resolution: the blur is cheaper and the result is
    // smooth, which is what a glow wants anyway.
    let half_w = if width > 2 { width / 2 } else { 1 };
    let half_h = if height > 2 { height / 2 } else { 1 };
    let a = gpu_render_target(half_w, half_h, FORMAT_RGBA16F);
    let b = gpu_render_target(half_w, half_h, FORMAT_RGBA16F);
    if a.id == 0 || b.id == 0 {
        gpu_release_texture(hdr);
        if depth.id != 0 { gpu_release_texture(depth); }
        if hdr_ms.id != 0 { gpu_release_texture(hdr_ms); }
        if depth_ms.id != 0 { gpu_release_texture(depth_ms); }
        if a.id != 0 { gpu_release_texture(a); }
        if b.id != 0 { gpu_release_texture(b); }
        d.last_error = ERR_GPU;
        return false;
    }
    d.targets = Targets { hdr: hdr, hdr_ms: hdr_ms, depth_ms: depth_ms, depth: depth,
                          bloom_a: a, bloom_b: b, shadow: shadow, shadow_far: shadow_far,
                          width: width, height: height, samples: d.msaa };
    return true;
}

fn release_targets(d: Device&) {
    let t = d.targets;
    if t.hdr.id != 0 { gpu_release_texture(t.hdr); }
    if t.hdr_ms.id != 0 { gpu_release_texture(t.hdr_ms); }
    if t.depth_ms.id != 0 { gpu_release_texture(t.depth_ms); }
    if t.depth.id != 0 { gpu_release_texture(t.depth); }
    if t.bloom_a.id != 0 { gpu_release_texture(t.bloom_a); }
    if t.bloom_b.id != 0 { gpu_release_texture(t.bloom_b); }
    if t.shadow.id != 0 { gpu_release_texture(t.shadow); }
    if t.shadow_far.id != 0 { gpu_release_texture(t.shadow_far); }
    d.targets = Targets {};
}

// --- settings ---------------------------------------------------------------------

// One preset for the whole post pipeline, so an application does not have to
// know which switches add up to a modern renderer.
fn quality(d: Device&, profile: i32) -> bool {
    if !d.opened { d.last_error = ERR_NOT_OPEN; return false; }
    if profile == QUALITY_LINEAR {
        d.tonemap = TONEMAP_NONE;
        d.bloom_strength = 0.0;
        d.shadows = false;
        d.sky_enabled = false;
        d.ibl = 0.0;
        d.fog_density = 0.0;
    } else if profile == QUALITY_MODERN {
        if d.sky_cube.id == 0 && !build_sky_cube(d) { return false; }
        if d.env_irradiance.id == 0 && !build_env_cubes(d) { return false; }
        d.tonemap = TONEMAP_ACES;
        d.bloom_strength = 0.35;
        d.shadows = true;
        d.sky_enabled = true;
        d.ibl = 1.0;
        d.fog_density = 0.012;
    } else {
        d.last_error = ERR_BAD_ARGUMENT;
        return false;
    }
    d.last_error = ERR_NONE;
    return true;
}

fn set_exposure(d: Device&, exposure: f32) -> bool {
    if exposure <= 0.0 || exposure > 64.0 { d.last_error = ERR_BAD_ARGUMENT; return false; }
    d.exposure = exposure;
    d.last_error = ERR_NONE;
    return true;
}

fn set_tonemap(d: Device&, mode: i32) -> bool {
    if !tonemap_valid(mode) { d.last_error = ERR_BAD_ARGUMENT; return false; }
    d.tonemap = mode;
    d.last_error = ERR_NONE;
    return true;
}

fn set_bloom(d: Device&, strength: f32, threshold: f32) -> bool {
    if strength < 0.0 || strength > 4.0 || threshold < 0.0 {
        d.last_error = ERR_BAD_ARGUMENT;
        return false;
    }
    d.bloom_strength = strength;
    d.bloom_threshold = threshold;
    d.last_error = ERR_NONE;
    return true;
}

fn set_shadows(d: Device&, enabled: bool) -> bool {
    if !d.opened { d.last_error = ERR_NOT_OPEN; return false; }
    d.shadows = enabled;
    d.last_error = ERR_NONE;
    return true;
}

// The world-space box the single shadow map covers: everything inside casts and
// receives, and everything outside is unshadowed.
// This selects single-box mode, which ignores the camera: a scene that moves
// away from the centre loses its shadows, which is what `set_shadow_cascades`
// exists for.
fn set_shadow_area(d: Device&, center: float3, radius: f32) -> bool {
    if radius <= 0.0 { d.last_error = ERR_BAD_ARGUMENT; return false; }
    d.shadow_center = center;
    d.shadow_radius = radius;
    d.shadow_mode = SHADOW_FIXED;
    d.last_error = ERR_NONE;
    return true;
}

// Two shadow maps that follow the camera: the first covers everything up to
// `near_range` units in front of it, the second everything up to `far_range`.
// Both are 1024², so the near map has far smaller texels and the far map keeps
// shadows where a single box would have run out.
//
// The near map is what a surface in the first `near_range` units is shadowed
// by; past that the far map takes over, in one switch at the range boundary.
// Casters are culled against the box they belong to, so a caster beyond the far
// range costs nothing.
fn set_shadow_cascades(d: Device&, near_range: f32, far_range: f32) -> bool {
    if near_range <= 0.0 || far_range <= near_range || far_range > 512.0 {
        d.last_error = ERR_BAD_ARGUMENT;
        return false;
    }
    d.shadow_near = near_range;
    d.shadow_far = far_range;
    d.shadow_mode = SHADOW_CASCADES;
    d.last_error = ERR_NONE;
    return true;
}

// SHADOW_FIXED or SHADOW_CASCADES: which of the two above is in effect.
fn shadow_mode(d: Device&) -> i64 { d.shadow_mode }

fn shadow_near_range(d: Device&) -> f32 { d.shadow_near }
fn shadow_far_range(d: Device&) -> f32 { d.shadow_far }

fn set_fog(d: Device&, density: f32) -> bool {
    if density < 0.0 { d.last_error = ERR_BAD_ARGUMENT; return false; }
    d.fog_density = density;
    d.last_error = ERR_NONE;
    return true;
}

// The sky and the fog colour, which are the same colour on purpose: distance
// fades into the horizon. Both are linear values, as everything before tone
// mapping is.
fn set_sky(d: Device&, horizon: float3, zenith: float3) -> bool {
    if !d.opened { d.last_error = ERR_NOT_OPEN; return false; }
    d.sky_horizon = horizon;
    d.sky_zenith = zenith;
    d.last_error = ERR_NONE;
    if !build_sky_cube(d) { return false; }
    return build_env_cubes(d);
}

// How much image-based lighting contributes, 0..4. At 1.0 (the default, and
// what QUALITY_MODERN sets) the sky lights every surface the way a real sky
// would; metals reflect it instead of showing a flat tint. At 0.0 the shader
// falls back to the constant ambient term, which is what 0.2 rendered.
fn set_ibl(d: Device&, strength: f32) -> bool {
    if strength < 0.0 || strength > 4.0 { d.last_error = ERR_BAD_ARGUMENT; return false; }
    d.ibl = strength;
    d.last_error = ERR_NONE;
    return true;
}

fn ibl_strength(d: Device&) -> f32 { d.ibl }

// Samples per pixel in the scene pass: 1 (off) or 4. Above 1 the scene renders
// into a multisampled target that is resolved at the end of the pass, so edges
// become gradients instead of stair steps. The cost is fill-rate proportional on
// a fill-bound device, which is why the default is 1 and no profile changes it:
// an application decides, after measuring.
//
// 4 is the only count offered, and that is a measured decision. The backend
// accepts 2 and 8, creates the targets, and reports no error — but on the only
// device this could be tested on (software Vulkan) a pass into a 2- or 8-sample
// target resolves to nothing at all, leaving the frame black. There is no way to
// ask the backend whether a sample count is supported, so offering 2 and 8 would
// mean offering a switch that silently renders nothing on some machines. When a
// device that supports more samples is available, adding them is a patch.
fn set_msaa(d: Device&, samples: i64) -> bool {
    if samples != 1 && samples != 4 {
        d.last_error = ERR_BAD_ARGUMENT;
        return false;
    }
    if d.msaa == samples { d.last_error = ERR_NONE; return true; }
    d.msaa = samples;
    // The targets are built for a sample count, so they are rebuilt on the next
    // frame:
    d.targets.width = 0;
    d.last_error = ERR_NONE;
    return true;
}

fn msaa_samples(d: Device&) -> i64 { d.msaa }

// Whether objects outside the camera frustum are skipped in the scene pass.
// The shadow pass still draws everything: an object off screen can still cast a
// shadow into it, and a shadow map has no camera frustum to cull against.
fn set_culling(d: Device&, on: bool) -> bool {
    d.culling = on;
    d.last_error = ERR_NONE;
    return true;
}

fn culling_enabled(d: Device&) -> bool { d.culling }

// Whether runs of draws that share geometry and material are merged into one
// instanced draw. Off draws every item on its own, which is the path the
// batching test compares against.
fn set_batching(d: Device&, on: bool) -> bool {
    d.batching = on;
    d.last_error = ERR_NONE;
    return true;
}

fn batching_enabled(d: Device&) -> bool { d.batching }

fn sky_horizon(d: Device&) -> float3 { d.sky_horizon }

fn sky_zenith(d: Device&) -> float3 { d.sky_zenith }

fn set_sky_enabled(d: Device&, on: bool) -> bool {
    d.sky_enabled = on;
    d.last_error = ERR_NONE;
    return true;
}

// --- the sky cube ------------------------------------------------------------------

fn color_byte(v: f32) -> u8 {
    let c = if v < 0.0 { 0.0 } else if v > 1.0 { 1.0 } else { v };
    return (c * 255.0 + 0.5) as u8;
}

// A six-face gradient cube from the two sky colours. A gradient only depends on
// the direction's height, so the usual cube-face orientation subtleties do not
// matter here; the faces are laid out the way the backend samples them.
fn build_sky_cube(d: Device&) -> bool {
    if d.sky_cube.id != 0 {
        gpu_release_texture(d.sky_cube);
        d.sky_cube = gfx::Texture { 0 };
    }
    let size: i64 = 64;
    let cube = gpu_texture_cube(size, FORMAT_RGBA8, TEXTURE_SAMPLED);
    if cube.id == 0 { d.last_error = ERR_GPU; return false; }
    var px: u8[>..] = [];
    for face in 6 {
        px.clear();
        px.resize(size * size * 4, 0);
        for y in size {
            for x in size {
                // The same direction and the same gradient the irradiance and
                // prefiltered cubes integrate, so the visible sky and the light
                // it casts cannot disagree.
                let dir = cube_direction(face, x, y, size);
                let c = sky_radiance(d.sky_horizon, d.sky_zenith, dir);
                let o = (y * size + x) * 4;
                px[o] = color_byte(c.x);
                px[o + 1] = color_byte(c.y);
                px[o + 2] = color_byte(c.z);
                px[o + 3] = 255;
            }
        }
        let bytes = px[..];
        if !gpu_update_texture_layer(cube, face as i32, bytes) {
            gpu_release_texture(cube);
            d.last_error = ERR_GPU;
            return false;
        }
    }
    d.sky_cube = cube;
    return true;
}

// --- image-based lighting ------------------------------------------------------------

fn release_env_cubes(d: Device&) {
    if d.env_irradiance.id != 0 {
        gpu_release_texture(d.env_irradiance);
        d.env_irradiance = gfx::Texture { 0 };
    }
    if d.env_prefiltered.id != 0 {
        gpu_release_texture(d.env_prefiltered);
        d.env_prefiltered = gfx::Texture { 0 };
    }
}

// The irradiance and prefiltered radiance cubes for the current sky colours. They
// depend on nothing else, so they are built when a device opens and again when
// set_sky() changes the sky: a few tens of thousands of samples, paid once, not
// once a frame. Built even when IBL is off, so the fragment shader always has a
// valid cube bound and the switch is a single uniform value.
fn build_env_cubes(d: Device&) -> bool {
    release_env_cubes(d);
    let cubes = env_build(d.sky_horizon, d.sky_zenith);
    if cubes.irradiance.id == 0 || cubes.prefiltered.id == 0 {
        if cubes.irradiance.id != 0 { gpu_release_texture(cubes.irradiance); }
        if cubes.prefiltered.id != 0 { gpu_release_texture(cubes.prefiltered); }
        d.last_error = ERR_GPU;
        return false;
    }
    d.env_irradiance = cubes.irradiance;
    d.env_prefiltered = cubes.prefiltered;
    return true;
}

fn alloc_material(d: Device&, rec: MaterialRec) -> Material {
    let i = d.materials.len;
    if i >= (1 << HANDLE_INDEX_BITS) { d.last_error = ERR_TOO_MANY; return Material { 0 }; }
    var r = rec;
    r.generation = 1;
    r.live = true;
    d.materials.push(r);
    d.stats.materials++;
    return Material { id: handle_make(i, 1) };
}

// --- lifetime -------------------------------------------------------------------

fn open(d: Device&, title: const u8[:], width: i64, height: i64) -> bool {
    return open_impl(d, title, width, height, false);
}

// A device with no window, drawing into a screen no one shows: for tests,
// tools, and off-screen rendering.
fn open_headless(d: Device&, width: i64, height: i64) -> bool {
    return open_impl(d, "", width, height, true);
}

fn open_impl(d: Device&, title: const u8[:], width: i64, height: i64, headless: bool) -> bool {
    if d.opened { d.last_error = ERR_ALREADY_OPEN; return false; }
    if width <= 0 || height <= 0 { d.last_error = ERR_BAD_ARGUMENT; return false; }
    d.last_error = ERR_NONE;
    let started = if headless { gpu_open_headless(width, height) }
                  else { gpu_open(title, width, height) };
    if !started { d.last_error = ERR_NO_DEVICE; return false; }

    d.meshes.clear();
    d.images.clear();
    d.materials.clear();
    d.shaders.clear();
    d.pipelines.clear();
    d.samplers.clear();
    d.lights.clear();
    d.items.clear();
    d.plan.clear();
    d.batches.clear();
    d.instances.clear();
    d.item_bounds.clear();
    d.shadow_plan.clear();
    d.shadow_batches.clear();
    d.shadow_instances.clear();
    d.instance_capacity = 0;
    d.shadow_instance_capacity = 0;
    d.culling = true;
    d.batching = true;
    d.shader_mesh = Shader { 0 };
    d.opened = true;
    d.headless = headless;
    d.frame_open = false;
    d.stats = Stats {};
    d.tonemap = TONEMAP_ACES;
    d.exposure = 1.0;
    d.bloom_strength = 0.35;
    d.bloom_threshold = 1.0;
    d.shadows = true;
    d.shadow_center = float3 { 0.0, 0.0, 0.0 };
    d.shadow_radius = 8.0;
    d.shadow_bias = 0.0015;
    d.shadow_mode = SHADOW_FIXED;
    d.shadow_near = 24.0;
    d.shadow_far = 72.0;
    d.msaa = 1;
    d.sky_enabled = true;
    d.ibl = 1.0;
    d.fog_density = 0.012;
    // The shadow map is fixed size: a shadow does not need screen resolution,
    // and a fixed size keeps one pipeline valid across window resizes.
    let shadow = gpu_depth_target(1024, 1024);
    if shadow.id == 0 { close(d); d.last_error = ERR_GPU; return false; }
    // The far cascade is allocated even in single-box mode: the built-in shader
    // declares both samplers, and binding an unused one is cheaper than making
    // the shader's declarations depend on the mode.
    let shadow_far = gpu_depth_target(1024, 1024);
    if shadow_far.id == 0 {
        gpu_release_texture(shadow);
        close(d);
        d.last_error = ERR_GPU;
        return false;
    }
    d.targets = Targets { shadow: shadow, shadow_far: shadow_far };
    d.sampler_shadow = gpu_shadow_sampler();
    d.sampler_post = gpu_sampler(FILTER_LINEAR, WRAP_CLAMP);
    d.sampler_mips = gpu_sampler_mips();
    let white: u8[4] = [255, 255, 255, 255];
    let flat: u8[4] = [128, 128, 255, 255];
    d.tex_white = gpu_texture_rgba8(1, 1, white[..]);
    d.tex_flat_normal = gpu_texture_rgba8(1, 1, flat[..]);
    if d.sampler_shadow.id == 0 || d.sampler_post.id == 0 || d.sampler_mips.id == 0
       || d.tex_white.id == 0 || d.tex_flat_normal.id == 0 {
        close(d);
        d.last_error = ERR_GPU;
        return false;
    }
    if !build_sky_cube(d) { close(d); d.last_error = ERR_GPU; return false; }
    if !build_env_cubes(d) { close(d); d.last_error = ERR_GPU; return false; }
    return true;
}

fn close(d: Device&) {
    if !d.opened { return; }
    var i = d.meshes.len;
    while i > 0 { i--; if d.meshes[i].live { release(d, Mesh { id: handle_make(i, d.meshes[i].generation) }); } }
    i = d.images.len;
    while i > 0 { i--; if d.images[i].live { release(d, Image { id: handle_make(i, d.images[i].generation) }); } }
    i = d.materials.len;
    while i > 0 { i--; if d.materials[i].live { release(d, Material { id: handle_make(i, d.materials[i].generation) }); } }
    // Pipelines and samplers are the device's caches, not the application's
    // resources: nothing can hold one, so they all go here.
    for k in d.pipelines.len {
        if d.pipelines[k].pipeline.id != 0 { gpu_release_pipeline(d.pipelines[k].pipeline); }
    }
    for k in d.samplers.len {
        if d.samplers[k].sampler.id != 0 { gpu_release_sampler(d.samplers[k].sampler); }
    }
    d.pipelines.clear();
    d.samplers.clear();
    d.shaders.clear();
    d.lights.clear();
    d.items.clear();
    d.plan.clear();
    d.batches.clear();
    d.instances.clear();
    d.item_bounds.clear();
    d.shadow_plan.clear();
    d.shadow_batches.clear();
    d.shadow_instances.clear();
    d.instance_capacity = 0;
    d.shadow_instance_capacity = 0;
    if d.instance_buffer.id != 0 {
        gpu_release_buffer(d.instance_buffer);
        d.instance_buffer = gfx::Buffer { 0 };
    }
    if d.shadow_instance_buffer.id != 0 {
        gpu_release_buffer(d.shadow_instance_buffer);
        d.shadow_instance_buffer = gfx::Buffer { 0 };
    }
    // Pass pipelines and the sky cube belong to the device too.
    if d.pipeline_shadow.id != 0 { gpu_release_pipeline(d.pipeline_shadow); }
    if d.pipeline_shadow_instanced.id != 0 { gpu_release_pipeline(d.pipeline_shadow_instanced); }
    d.pipeline_shadow_instanced = gfx::Pipeline { 0 };
    if d.pipeline_sky.id != 0 { gpu_release_pipeline(d.pipeline_sky); }
    if d.pipeline_bright.id != 0 { gpu_release_pipeline(d.pipeline_bright); }
    if d.pipeline_blur.id != 0 { gpu_release_pipeline(d.pipeline_blur); }
    if d.pipeline_composite.id != 0 { gpu_release_pipeline(d.pipeline_composite); }
    d.pipeline_shadow = gfx::Pipeline { 0 };
    d.pipeline_sky = gfx::Pipeline { 0 };
    d.pipeline_bright = gfx::Pipeline { 0 };
    d.pipeline_blur = gfx::Pipeline { 0 };
    d.pipeline_composite = gfx::Pipeline { 0 };
    if d.sampler_shadow.id != 0 { gpu_release_sampler(d.sampler_shadow); }
    if d.sampler_post.id != 0 { gpu_release_sampler(d.sampler_post); }
    if d.sampler_mips.id != 0 { gpu_release_sampler(d.sampler_mips); }
    d.sampler_shadow = gfx::Sampler { 0 };
    d.sampler_post = gfx::Sampler { 0 };
    d.sampler_mips = gfx::Sampler { 0 };
    if d.tex_white.id != 0 { gpu_release_texture(d.tex_white); d.tex_white = gfx::Texture { 0 }; }
    if d.tex_flat_normal.id != 0 {
        gpu_release_texture(d.tex_flat_normal);
        d.tex_flat_normal = gfx::Texture { 0 };
    }
    if d.sky_cube.id != 0 { gpu_release_texture(d.sky_cube); d.sky_cube = gfx::Texture { 0 }; }
    release_env_cubes(d);
    release_targets(d);
    gpu_close();
    d.opened = false;
    d.frame_open = false;
}
