# HiPGR — Architecture

HiPGR is a 3D rendering library for Goose. It owns GPU objects, frames and
draw submission. It does not own a scene, a world model, an ECS, physics, or an
application loop.

This document describes the design as implemented in 0.2.0, the invariants it
depends on, and the Goose constraints that force them. Read
[RECONNAISSANCE.md](RECONNAISSANCE.md) first for the evidence behind those
constraints.

---

## 1. Goals and non-goals

**Goals**

* Render real 3D scenes through Goose's `gfx` (SDL3 GPU: Vulkan/D3D12/Metal)
  with a small, explicit API.
* Own GPU resource lifetimes safely in a language with no heap and no
  destructors.
* Keep the backend behind a boundary that can be replaced without rewriting the
  renderer.
* Be usable by an independent Goose application today, and by G3E later,
  without G3E shapes leaking into the API.

**Non-goals for 0.1**

* A game engine, a scene graph, a component system, or a file format pipeline.
* A second graphics backend, or runtime backend selection (see §9).
* Any feature whose value has not been demonstrated by a test or measurement.

## 2. Layers

```
   application (examples/demo_cube.goose, your Goose program)
        │  hipgr::Device, Mesh, Image, Material, Camera, Mat4, Stats
        ▼
┌───────────────────────────────────────────────────────────────────┐
│ renderer   frame lifecycle, draw submission, std140 uniform blocks │
│ material   shader pairs, MaterialDesc, caches, lights              │
│ mesh       Vertex, Mesh, 16/32-bit indices, validation, geometry    │
│ image      RGBA8 textures                                          │
│ camera     view / projection matrices                             │
│ device     Device: records, handles, lifetime, errors, stats      │
│ platform   keys, mouse, clock (facade, not an input system)       │
│ math       Mat4 wrapper, transforms, normal matrix                │
│ state      cull / blend / filter / wrap values, as data           │
│ handle     handle encoding, resource handle types                 │
└───────────────────────────────────────────────────────────────────┘
        │  gpu.goose: the ONLY module that issues gfx calls
        ▼
   Goose gfx  ──►  SDL3 GPU  ──►  Vulkan | Direct3D 12 | Metal
```

| Module | Responsibility | May call `gfx`? |
|---|---|---|
| `hipgr.goose` | package entry: re-exports, `version()` | no |
| `gpu.goose` | the backend boundary: device, passes, pipelines, bindings, draws, read-back | **yes — calls** |
| `device.goose` | `Device`, resource records, validation, lifetime, error codes | yes — **types only** (stores handles) |
| `renderer.goose` | `begin_frame` / `draw` / `end_frame`, uniform blocks | no |
| `material.goose` | shader pairs, `MaterialDesc`, pipeline and sampler caches, lights | no |
| `mesh.goose` | `Vertex`, `Mesh`, 16/32-bit indexing, updates, cube/quad/triangle | no |
| `state.goose` | `CULL_*`, `BLEND_*`, `FILTER_*`, `WRAP_*` and their validation | no |
| `image.goose` | `Image` from RGBA8 bytes, checkerboards, PNG/BMP load | no |
| `camera.goose` | `Camera`, view/projection/view-projection | no |
| `math.goose` | `Mat4` and the transforms applications build | no |
| `handle.goose` | handle encoding and the public handle types | no |
| `platform.goose` | keys, mouse, clock | no |

Only `gpu.goose` *calls* into `gfx`; `device.goose` merely stores opaque `gfx`
handle values in its records, which is what makes them releasable. The public
API names no `gfx` type, and `scripts/test.sh` fails if any example, test or
benchmark imports `gfx`.

## 3. Ownership and lifetime

Goose has no destructors, no heap allocator and no `defer`-based teardown of
resources (its `defer` runs at scope exit, but there is nothing to hang a GPU
free on). Therefore:

> **The device owns every GPU object it creates. Handles name them; the
> device releases them.**

* `open` / `open_headless` create the backend device and the shared sampler.
* `mesh_create`, `image_rgba8`, `material_textured` … create GPU objects and
  return handles.
* `release(dev, handle)` frees the GPU object **immediately** and invalidates
  the handle.
* `close(dev)` releases everything still live, then closes the backend. It is
  safe to call with resources outstanding, and calling it twice is a no-op.
* `defer hipgr::close(dev);` right after opening is the intended pattern for an
  application.

Records live in growable arrays inside the `Device` (a Goose *root struct*, see
§7), so the registry itself needs no allocation strategy: it grows on the data
stack.

Pipelines and samplers are different: they are the device's **caches**, not the
application's resources. An application describes state on a material, and
`material_create` returns the existing pipeline if that exact state already
exists. Nothing above the library can name a pipeline, so all of them are
released by `close` and none by `release`. That is what keeps a scene with
hundreds of materials to a handful of pipelines: a material is a few floats and
a pair of handle references, not a GPU object.

## 4. Handles

A handle is a 32-bit value: **index in the low 24 bits, generation in the top
8**. Zero is never a valid handle.

```goose
struct Mesh { id: u32 }
struct Image { id: u32 }
struct Material { id: u32 }
struct Shader { id: u32 }
```

Resolution is explicit and total:

```
mesh_index(dev, h) -> i64   // -1: zero handle, out of range, dead, or wrong generation
```

Every public operation that takes a handle resolves it first. A stale handle
produces `false` plus `ERR_BAD_HANDLE`; it never reaches the GPU, and it never
crashes. The generation exists so that when 0.4 starts recycling slots, a
handle from before the recycle is still detected as stale.

Two handles of different types with the same index are not interchangeable: the
record arrays are separate and the types are distinct.

**One non-obvious consequence**: a material stores the *image handle*, not a
copy of the backend texture. Releasing an image that a material still uses is
therefore caught at draw time. An earlier version copied the raw texture handle
and the mistake surfaced as a `gfx` misuse abort — the test
`tests/test_handles.goose` is what forced this design.

## 5. The backend boundary

`gpu.goose` is the contract. Its rules are what a replacement backend would
have to satisfy.

### 5.1 Resource kinds

| HiPGR | Backend object |
|---|---|
| `Mesh` | one vertex buffer + one index buffer, 16- or 32-bit |
| `Image` | one `RGBA8`, sampled 2D texture |
| `Material` | a cached pipeline (by state) + tint + user data + unlit flag + image and sampler references |
| `Shader` | a vertex + fragment source pair, compiled into pipelines on demand |
| `Device` | the backend device, a screen with depth, the pipeline and sampler caches |

### 5.2 Vertex layout

```goose
struct Vertex { pos: float3, normal: float3, uv: float2 }   // 32 bytes, packed
```

fed to shader locations 0, 1, 2 in that order, from vertex buffer slot 0. No
per-instance data in 0.1.

### 5.3 Bindings and uniform blocks

Bindings follow SDL_GPU, which `gfx` checks at compile time:

| Shader | Set | Binding | Contents | HiPGR struct | Bytes |
|---|---|---|---|---|---|
| vertex | 1 | 0 | `Frame { mat4 view_proj; }` | `FrameUniform` | 64 |
| vertex | 1 | 1 | `Draw { mat4 model; mat4 normal; }` | `DrawUniform` | 128 |
| fragment | 2 | 0 | `sampler2D u_albedo` (only when the material has an image) | — | — |
| fragment | 3 | 0 | `Material { vec4 tint; vec4 params; vec4 user0; vec4 user1; }` | `MaterialUniform` | 64 |
| fragment | 3 | 1 | `Light { vec4 direction; vec4 color; vec4 points[16]; }` | `LightUniform` | 288 |

* `normal` is the inverse transpose of `model`'s upper 3×3 (`mat4_normal`), so a
  non-uniform scale shades correctly. `tests/test_normals.goose` compares a
  stretched mesh against an equivalent baked one, and fails if the plain model
  matrix is used instead.
* `params.x` is 1 when the material is unlit; `direction.w` carries ambient;
  `color.w` carries the number of point lights, whose `(position, radius)` and
  `(colour, 0)` pairs fill `points`. The block is a fixed 288 bytes so one
  shader serves any number of lights up to `MAX_POINT_LIGHTS` (8).
* Blocks are pushed per frame (frame, light) and per draw (draw, material), in
  program order, which the backend guarantees sits between passes.
* std140 sizes are checked against the shader by the backend; the structs above
  are sized to match exactly, including the 16-byte alignment of `vec4`.

### 5.4 Conventions

* Right-handed, camera looks down **-Z**; clip depth **0..1** (SDL_GPU's clip
  space, not OpenGL's -1..1).
* Texture coordinate `v = 0` is the **top** row.
* Front faces are counter-clockwise; the default material culls back faces,
  tests and writes depth. Culling, blending, depth and wireframe are per
  material, and the pipeline for that combination is cached by the device.

### 5.5 What the boundary deliberately does not expose

No `gfx` types, no storage buffers, no compute, no render targets other than
the screen. Pipeline state (cull, blend, depth, wireframe) and custom shader
pairs arrived in 0.2 as *data* — a `MaterialDesc` and a `Shader` handle — so an
application still never touches a backend descriptor. Storage buffers, compute
and off-screen passes arrive only with a concrete use case (see
[ROADMAP.md](ROADMAP.md)).

## 6. Frames and draw submission

```goose
while hipgr::begin_frame(dev, camera, clear) {
    hipgr::draw(dev, mesh, material, model_matrix);   // once per object
    if !hipgr::end_frame(dev) { break; }              // false = quit requested
}
```

* `begin_frame` validates the device and frame state, computes the
  view-projection matrix from the camera and the *current* screen aspect,
  opens the screen pass, and pushes the frame and light blocks.
* `draw` binds the material's pipeline, the mesh buffers, the draw and material
  blocks, the texture when the material has one, and issues an indexed draw.
  It updates `Stats`.
* `end_frame` closes the pass, presents, and returns the backend's "keep going"
  flag.
* There is no implicit batching, sorting, culling or instancing. Objects are
  drawn in submission order. That is deliberate: 0.4 adds those systems *with*
  benchmarks, not by default.

A frame costs, per draw: one pipeline bind, two buffer binds, two uniform
pushes, one texture bind, one indexed draw. Everything else — the frame and
light blocks — is pushed once per frame. 256 cubes measured 7.5 ms/frame and
1024 cubes 25.0 ms/frame on a CPU rasterizer (see [PROGRESS.md](PROGRESS.md)).

## 7. Why `Device` is a `root struct`

Goose allows an ordinary struct **one** growable array, on its tail. `Device`
needs several independent registries (meshes, images, materials, shaders,
pipeline and sampler caches, lights) plus scalar state, so it is a `root
struct`:

```goose
root struct Device {
    meshes: MeshRec[>..] = [],
    images: ImageRec[>..] = [],
    materials: MaterialRec[>..] = [],
    shaders: ShaderRec[>..] = [],
    pipelines: PipelineRec[>..] = [],
    samplers: SamplerRec[>..] = [],
    lights: PointLight[>..] = [],
    opened: bool = false,
    …
}
```

Consequences, all of which the API is built around:

* root values cannot be copied, assigned wholesale, passed or returned by value
  — hence `Device&` in every signature, and `var dev = hipgr::Device { .. };` in
  the application;
* each field is its own storage root and shares the device's lifetime;
* `Device` cannot be a field of another struct, so there is exactly one device
  per application — which is also the backend's rule.

## 8. Errors

Two layers, deliberately separated:

| Layer | Mechanism |
|---|---|
| HiPGR | `false` / zero handle + a code in `Device.last_error`; `error_code(dev)`, `error_text(code)` |
| backend | `backend_error()` returns `gfx`'s own last message (`no GPU device`, missing file, …) |

The codes are stable constants (`ERR_BAD_HANDLE`, `ERR_NO_FRAME`, …). The
library never calls `abort` on the application's behalf, because a library that
kills its host is not a library. `gfx` itself aborts on misuse at the next
frame/read-back/close; HiPGR validates first so application mistakes do not
reach it.

Geometry is validated before upload: empty meshes, non-triangle index counts,
and **any index past the end of the vertex array** are rejected
(`ERR_BAD_ARGUMENT`). That last check is what keeps a bad asset from turning
into an out-of-bounds vertex fetch.

## 9. Threading

* Rendering is **main-thread only**: `gfx` is a compile error from a
  `thread_fn`.
* Goose's threading model has no shared memory; workers are separate programs
  that exchange flat values through typed queues.
* Therefore the intended pattern for 0.2+ asset work is: decode/prepare on a
  worker, pass a flat byte buffer through a queue, upload on the main thread
  inside the frame. Nothing in 0.1 does this yet.

## 10. Integration with G3E

HiPGR exposes rendering primitives, not a world:

* Submit a mesh, a material and a model matrix. G3E keeps its ECS, hierarchy,
  assets, physics and gameplay.
* No G3E types, includes or conventions exist in this repository, and none
  should be added.
* The stable-API milestone (0.5) is where versioning and compatibility promises
  start; until then treat the API as a 0.x draft.
* Two known integration gaps to plan for: attaching to a caller-owned window
  (§9 of the reconnaissance) and custom material/shader parameters. Both are
  roadmap items, not accidents.

## 11. Deliberate omissions, and what would change the design

| Omitted | Why | What would force it |
|---|---|---|
| Render graph | no evidence it is needed at this scale; `gfx` handles barriers | multi-pass effects in 0.3 (shadows, bloom) if pass setup becomes error-prone |
| Second backend | none of the measurements that would justify bypassing `gfx` can be taken on a CPU rasterizer | profiling on real hardware showing uniform-push or draw-call overhead dominating |
| Render targets, HDR, post-processing | needs a measurement or a feature that requires it | 0.3's shadows and bloom |
| Instancing / batching / culling | must be justified by benchmarks (0.4) | a scene that needs them, measured |
| Runtime backend selection | Goose has no runtime polymorphism | never, within Goose's current model |
| Shader hot reload | `embed_shader` is compile-time | shader iteration becoming the bottleneck; would need a file-watch + runtime-compile path outside `gfx` |

The largest structural risk is the opposite of over-engineering: if `gfx` turns
out to be the bottleneck on real hardware, the replacement is a native C layer
behind `gpu.goose`, and the renderer above it should not need to change. That
is the test of whether this boundary was drawn correctly.
