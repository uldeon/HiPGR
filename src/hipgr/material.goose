// HiPGR: shaders, materials, and lights.
//
// A material is the shading state a mesh is drawn with: a vertex + fragment
// shader pair, pipeline state, a tint, a metallic/roughness surface, optional
// albedo and normal maps, application data, and emissive colour. Materials that
// ask for the same state share one pipeline and one sampler, both owned by the
// device; an application can hold a material handle, but never a pipeline.
//
// One built-in pair does all of HiPGR's shading: metallic/roughness PBR with a
// directional light, point lights, a shadow map, normal mapping and fog. A
// material with no image samples a white texel; one with no normal map samples
// a flat normal, so the solid and textured cases are the same shader.
namespace hipgr;

import vec;
import math;
import .handle;
import .state;
import .device;
import .image;
import .gpu;

// Embedded when the program is compiled, for every backend at once.
let SHADER_MESH_VS = embed_shader("shaders/mesh.vert");
let SHADER_MESH_FS = embed_shader("shaders/mesh.frag");

// --- shaders -------------------------------------------------------------------

// The blocks a custom shader reads. These are a compatibility promise: changing
// a size is a breaking change and bumps a minor version.
//
//   vertex, set 1 binding 0   Frame    { mat4 view_proj; mat4 light_view_proj;
//                                        vec4 camera_pos; vec4 sky; vec4 params;
//                                        vec4 cam_right; vec4 cam_up; vec4 cam_forward; }
//   vertex, set 1 binding 1   Draw     { mat4 model; mat4 normal; }
//   fragment, set 3 binding 0 Material { vec4 tint; vec4 params; vec4 user0;
//                                        vec4 user1; vec4 emissive; }
//   fragment, set 3 binding 1 Light    { vec4 direction; vec4 color; vec4 points[16]; }
//
// Vertex inputs are the Vertex struct of mesh.goose: location 0 position,
// 1 normal, 2 uv. HiPGR's own shader also reads a second Frame copy at set 3
// binding 2, and samplers at set 2 bindings 0 (albedo), 1 (normal map) and
// 2 (shadow). A custom shader declares only what it needs, and HiPGR binds no
// textures for it.
//
// A pair comes from shader source embedded in the application:
//
//   let vs = embed_shader("shaders/mine.vert");
//   let fs = embed_shader("shaders/mine.frag");
//   let sh = hipgr::shader_create(dev, vs, fs);
fn shader_create(d: Device&, vert: const u8[:], frag: const u8[:]) -> Shader {
    if !d.opened { d.last_error = ERR_NOT_OPEN; return Shader { 0 }; }
    if vert.len == 0 || frag.len == 0 { d.last_error = ERR_BAD_ARGUMENT; return Shader { 0 }; }
    d.last_error = ERR_NONE;
    return alloc_shader(d, vert, frag);
}

// Pipelines already built from the pair stay valid and stay with the device:
// they hold their own compiled copy, and nothing above can name one.
fn release(d: Device&, h: Shader) {
    let i = shader_index(d, h);
    if i < 0 { d.last_error = ERR_BAD_HANDLE; return; }
    d.shaders[i].live = false;
    d.shaders[i].generation = next_generation(d.shaders[i].generation);
    d.stats.shaders = d.stats.shaders - 1;
    d.last_error = ERR_NONE;
}

// The built-in pair, created the first time something needs it.
fn shader_mesh(d: Device&) -> Shader {
    if d.shader_mesh.id == 0 {
        d.shader_mesh = shader_create(d, SHADER_MESH_VS, SHADER_MESH_FS);
    }
    return d.shader_mesh;
}

// --- pipelines and samplers ------------------------------------------------------
//
// Both are caches: a linear scan over a handful of states is cheaper than a
// hash and impossible to get wrong. They are released by close().

fn pipeline_get(d: Device&, sh: Shader, cull: i32, blend: i32, depth_test: bool,
                depth_write: bool, wireframe: bool) -> gfx::Pipeline {
    for i in d.pipelines.len {
        let r = d.pipelines[i];
        if r.shader == sh.id && r.cull == cull && r.blend == blend
           && r.depth_test == depth_test && r.depth_write == depth_write
           && r.wireframe == wireframe {
            return r.pipeline;
        }
    }
    let si = shader_index(d, sh);
    if si < 0 { return gfx::Pipeline { 0 }; }
    let p = gpu_pipeline_state(d.shaders[si].vs, d.shaders[si].fs, cull, blend,
                               depth_test, depth_write, wireframe);
    if p.id == 0 { return gfx::Pipeline { 0 }; }
    alloc_pipeline(d, sh, cull, blend, depth_test, depth_write, wireframe, p);
    return p;
}

fn sampler_get(d: Device&, filter: i32, wrap: i32) -> gfx::Sampler {
    for i in d.samplers.len {
        if d.samplers[i].filter == filter && d.samplers[i].wrap == wrap {
            return d.samplers[i].sampler;
        }
    }
    let s = gpu_sampler(filter, wrap);
    if s.id == 0 { return gfx::Sampler { 0 }; }
    alloc_sampler(d, filter, wrap, s);
    return s;
}

// --- materials -------------------------------------------------------------------

// Everything a material is made of. The defaults are a matte dielectric: a
// white surface with roughness 0.5, no texture, lit by the scene's lights.
struct MaterialDesc {
    shader: Shader = Shader { 0 },   // 0: the built-in PBR pair
    image: Image = Image { 0 },      // albedo texture; 0: tint only
    normal_map: Image = Image { 0 }, // tangent-space normal map; 0: flat
    tint: float4 = float4 { 1.0, 1.0, 1.0, 1.0 },
    user0: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },   // Material.user0, for custom shaders
    user1: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },   // Material.user1
    emissive: float3 = float3 { 0.0, 0.0, 0.0 },     // emitted, independent of light
    unlit: bool = false,
    metallic: f32 = 0.0,             // 0 dielectric, 1 metal
    // 0 is a mirror, 1 fully rough. The default is fully rough, so a plain
    // coloured surface shades like matte paint and only a material that asks
    // for it shows a highlight.
    roughness: f32 = 1.0,
    normal_strength: f32 = 1.0,      // 0 ignores the normal map
    cull: i32 = CULL_BACK,
    blend: i32 = BLEND_NONE,
    depth_test: bool = true,
    depth_write: bool = true,        // turn off with BLEND_ALPHA in most cases
    wireframe: bool = false,
    filter: i32 = FILTER_LINEAR,
    wrap: i32 = WRAP_CLAMP,
}

fn material_create(d: Device&, desc: MaterialDesc) -> Material {
    if !d.opened { d.last_error = ERR_NOT_OPEN; return Material { 0 }; }
    if !cull_valid(desc.cull) || !blend_valid(desc.blend)
       || !filter_valid(desc.filter) || !wrap_valid(desc.wrap) {
        d.last_error = ERR_BAD_ARGUMENT;
        return Material { 0 };
    }
    if desc.metallic < 0.0 || desc.metallic > 1.0
       || desc.roughness < 0.0 || desc.roughness > 1.0
       || desc.normal_strength < 0.0 || desc.normal_strength > 4.0 {
        d.last_error = ERR_BAD_ARGUMENT;
        return Material { 0 };
    }
    // Images are checked now and again on every draw, so releasing one early
    // is an error rather than a stale texture object.
    if desc.image.id != 0 && image_index(d, desc.image) < 0 {
        d.last_error = ERR_BAD_HANDLE;
        return Material { 0 };
    }
    if desc.normal_map.id != 0 && image_index(d, desc.normal_map) < 0 {
        d.last_error = ERR_BAD_HANDLE;
        return Material { 0 };
    }
    var sh = desc.shader;
    if sh.id == 0 { sh = shader_mesh(d); }
    if sh.id == 0 { return Material { 0 }; }   // shader_create set the error
    if shader_index(d, sh) < 0 { d.last_error = ERR_BAD_HANDLE; return Material { 0 }; }

    let pipe = pipeline_get(d, sh, desc.cull, desc.blend, desc.depth_test,
                            desc.depth_write, desc.wireframe);
    if pipe.id == 0 { d.last_error = ERR_GPU; return Material { 0 }; }
    let samp = sampler_get(d, desc.filter, desc.wrap);
    if samp.id == 0 { d.last_error = ERR_GPU; return Material { 0 }; }
    d.last_error = ERR_NONE;
    return alloc_material(d, MaterialRec {
        pipeline: pipe,
        image: desc.image,
        normal_image: desc.normal_map,
        sampler: samp,
        tint: desc.tint,
        user0: desc.user0,
        user1: desc.user1,
        emissive: float4 { desc.emissive.x, desc.emissive.y, desc.emissive.z, 0.0 },
        metallic: desc.metallic,
        roughness: desc.roughness,
        normal_strength: desc.normal_strength,
        unlit: desc.unlit,
        builtin: desc.shader.id == 0,
    });
}

// One colour, no texture, no normal map. Lit unless `unlit`.
fn material_solid(d: Device&, tint: float4, unlit: bool) -> Material {
    return material_create(d, MaterialDesc { tint: tint, unlit: unlit });
}

// An image sampled over the mesh's UVs, multiplied by `tint`. Lit unless
// `unlit`. The image must outlive the material's use of it.
fn material_textured(d: Device&, img: Image, tint: float4, unlit: bool) -> Material {
    return material_create(d, MaterialDesc { image: img, tint: tint, unlit: unlit });
}

fn release(d: Device&, h: Material) {
    let i = material_index(d, h);
    if i < 0 { d.last_error = ERR_BAD_HANDLE; return; }
    // The pipeline and sampler are shared and stay with the device.
    d.materials[i].live = false;
    d.materials[i].generation = next_generation(d.materials[i].generation);
    d.stats.materials = d.stats.materials - 1;
    d.last_error = ERR_NONE;
}

// --- lights ----------------------------------------------------------------------

// The one directional light the built-in materials use: the direction it
// travels in, its colour, and an ambient fraction from 0 to 1.
fn set_light(d: Device&, direction: float3, color: float3, ambient: f32) -> bool {
    let len = length(direction);
    if len <= 0.000001 { d.last_error = ERR_BAD_ARGUMENT; return false; }
    if ambient < 0.0 || ambient > 1.0 { d.last_error = ERR_BAD_ARGUMENT; return false; }
    d.light_direction = direction / float3 { len, len, len };
    d.light_color = color;
    d.ambient = ambient;
    d.last_error = ERR_NONE;
    return true;
}

// A point light at `position` reaching `radius` world units, after which it
// contributes nothing. Slots are addressed by index so a test or a scene can
// update one light without rebuilding the list; setting a later index first
// leaves the ones before it black, which contributes no light.
fn set_point_light(d: Device&, index: i64, position: float3, color: float3,
                   radius: f32) -> bool {
    if !d.opened { d.last_error = ERR_NOT_OPEN; return false; }
    if index < 0 || index >= MAX_POINT_LIGHTS || radius <= 0.0 {
        d.last_error = ERR_BAD_ARGUMENT;
        return false;
    }
    while d.lights.len <= index {
        d.lights.push(PointLight { color: float3 { 0.0, 0.0, 0.0 }, radius: 1.0 });
    }
    d.lights[index] = PointLight { position: position, color: color, radius: radius };
    d.last_error = ERR_NONE;
    return true;
}

fn clear_point_lights(d: Device&) { d.lights.clear(); }

fn point_light_count(d: Device&) -> i64 { d.lights.len }
