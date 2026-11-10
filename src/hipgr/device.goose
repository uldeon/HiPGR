// HiPGR: the device, its resource records, and error reporting.
//
// Goose has no destructors and no heap, so ownership is explicit: the Device
// owns every GPU object it created, resource creation returns a generation-
// checked handle, and release() invalidates the handle and frees the GPU
// object immediately. closing the device releases whatever is still live.
namespace hipgr;

import vec;
import gfx;
import .handle;
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
    // Sampled with the material's own sampler, shared with every material that
    // asked for the same filtering.
    sampler: gfx::Sampler = gfx::Sampler { 0 },
    tint: float4 = float4 { 1.0, 1.0, 1.0, 1.0 },
    // Two float4s of application data, handed to a custom shader as
    // Material.user0 and Material.user1.
    user0: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    user1: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    unlit: bool = false,
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

    // The built-in shader pairs, created with the device so materials never
    // have to know whether one exists.
    shader_solid: Shader = Shader { 0 },
    shader_textured: Shader = Shader { 0 },

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
              vertex_count: i64, index_count: i64, index_size: i64) -> Mesh {
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
                  depth_write: bool, wireframe: bool, pipeline: gfx::Pipeline) {
    d.pipelines.push(PipelineRec { shader: shader.id, cull: cull, blend: blend,
                                   depth_test: depth_test, depth_write: depth_write,
                                   wireframe: wireframe, pipeline: pipeline });
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

fn alloc_material(d: Device&, pipeline: gfx::Pipeline, image: Image, sampler: gfx::Sampler,
                  tint: float4, user0: float4, user1: float4, unlit: bool) -> Material {
    let i = d.materials.len;
    if i >= (1 << HANDLE_INDEX_BITS) { d.last_error = ERR_TOO_MANY; return Material { 0 }; }
    d.materials.push(MaterialRec { generation: 1, live: true, pipeline: pipeline,
                                   image: image, sampler: sampler, tint: tint, user0: user0,
                                   user1: user1, unlit: unlit });
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
    d.shader_solid = Shader { 0 };
    d.shader_textured = Shader { 0 };
    d.opened = true;
    d.headless = headless;
    d.frame_open = false;
    d.stats = Stats {};
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
    gpu_close();
    d.opened = false;
    d.frame_open = false;
}
