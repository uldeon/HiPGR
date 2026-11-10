// HiPGR: materials.
//
// A material is the shading state a mesh is drawn with: one backend pipeline
// shared with every other material of the same kind, a tint, an unlit flag,
// and for textured materials the image to sample. The pipelines are created on
// first use and belong to the device.
//
// 0.1 offers the two built-in shader pairs. Custom shaders need a uniform
// layout contract for applications, which is 0.2 work: they would have to
// declare exactly these blocks, and that is not a public promise yet.
namespace hipgr;

import vec;
import math;
import .handle;
import .device;
import .image;
import .gpu;

// Embedded when the program is compiled, for every backend at once.
let SHADER_MESH_VS = embed_shader("shaders/mesh.vert");
let SHADER_TEXTURED_FS = embed_shader("shaders/mesh_textured.frag");
let SHADER_SOLID_FS = embed_shader("shaders/mesh_solid.frag");

// One colour, no texture. Lit unless `unlit`.
fn material_solid(d: Device&, tint: float4, unlit: bool) -> Material {
    if d.gpu_pipeline_solid.id == 0 {
        d.gpu_pipeline_solid = gpu_pipeline(SHADER_MESH_VS, SHADER_SOLID_FS);
        if d.gpu_pipeline_solid.id == 0 { d.last_error = ERR_GPU; return Material { 0 }; }
    }
    d.last_error = ERR_NONE;
    return alloc_material(d, MAT_SOLID, d.gpu_pipeline_solid, Image { 0 }, tint, unlit);
}

// An image sampled over the mesh's UVs, multiplied by `tint`. Lit unless
// `unlit`. The image must outlive the material's use of it.
fn material_textured(d: Device&, img: Image, tint: float4, unlit: bool) -> Material {
    let i = image_index(d, img);
    if i < 0 { d.last_error = ERR_BAD_HANDLE; return Material { 0 }; }
    if d.gpu_pipeline_textured.id == 0 {
        d.gpu_pipeline_textured = gpu_pipeline(SHADER_MESH_VS, SHADER_TEXTURED_FS);
        if d.gpu_pipeline_textured.id == 0 { d.last_error = ERR_GPU; return Material { 0 }; }
    }
    d.last_error = ERR_NONE;
    return alloc_material(d, MAT_TEXTURED, d.gpu_pipeline_textured, img, tint, unlit);
}

fn release(d: Device&, h: Material) {
    let i = material_index(d, h);
    if i < 0 { d.last_error = ERR_BAD_HANDLE; return; }
    // The pipeline is shared and stays with the device.
    d.materials[i].live = false;
    d.materials[i].generation = next_generation(d.materials[i].generation);
    d.stats.materials = d.stats.materials - 1;
}

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
