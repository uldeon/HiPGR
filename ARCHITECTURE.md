# HiPGR — Architecture

HiPGR is a 3D rendering library for Goose. It owns GPU objects, frames and
draw submission. It does not own a scene, a world model, an ECS, physics, or an
application loop.

This document describes the design as implemented in 0.4.0, the invariants it
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
│ renderer   frame lifecycle, draw recording, presentation          │
│ post       the four passes: shadow, scene, bloom, composite       │
│ uniforms   the std140 blocks, one definition shared by all passes  │
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
| `device.goose` | `Device`, resource records, validation, lifetime, error codes, render targets, quality settings | yes — **types only** (stores handles) |
| `uniforms.goose` | `FrameUniform`, `DrawUniform`, `MaterialUniform`, `LightUniform`, `SurfaceUniform`, `PostUniform` and their builders | no |
| `post.goose` | the shadow, scene, bloom and composite passes and their pipelines | no |
| `submit.goose` | the frame's plan: frustum extraction and culling, draw order, batching, the instance buffer | no |
| `env.goose` | image-based lighting: sky radiance as a function, cube face directions, the irradiance and GGX integrals, float → half, the two environment cubes | no |
| `renderer.goose` | `begin_frame` / `draw` / `end_frame` | no |
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
| `Material` | a cached pipeline (by state) + tint, metallic/roughness, emissive, user data, unlit flag + albedo, normal map and sampler references |
| `Shader` | a vertex + fragment source pair, compiled into pipelines on demand |
| `Device` | the backend device, the screen, the HDR/depth/bloom/shadow targets, the fixed pass pipelines, and the pipeline and sampler caches |

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
| vertex | 1 | 0 | `Frame` | `FrameUniform` | 224 |
| vertex | 1 | 1 | `Draw { mat4 model; mat4 normal; }` (not in the instanced vertex shader) | `DrawUniform` | 128 |
| vertex | 1 | — | `mesh_instanced.vert` reads locations 3..10 instead: the same two matrices, per instance from **vertex buffer 1** | `Instance` | 128 |
| vertex | 1 | — | `shadow_instanced.vert` reads locations 3..6: the model matrix only, from its own **vertex buffer 1** | `ShadowInstance` | 64 |
| fragment | 2 | 0–2 | `u_albedo`, `u_normal_map`, `u_shadow` (built-in shader only) | — | — |
| fragment | 2 | 3–4 | `u_irradiance`, `u_prefiltered` (`samplerCube`, built-in shader only) | — | — |
| fragment | 3 | 0 | `Material { vec4 tint; vec4 params; vec4 user0; vec4 user1; }` | `MaterialUniform` | 64 |
| fragment | 3 | 1 | `Light { vec4 direction; vec4 color; vec4 points[16]; }` | `LightUniform` | 288 |
| fragment | 3 | 2 | `Frame`, the same bytes (fog, shadow parameters) | `FrameUniform` | 224 |
| fragment | 3 | 3 | `Surface { vec4 emissive; }` (built-in shader only) | `SurfaceUniform` | 16 |
| fragment | 3 | 0 | `Post { vec4 params; vec4 texel; }` (the post and sky pipelines, whose set 3 binding 0 is unused otherwise) | `PostUniform` | 32 |

* `normal` is the inverse transpose of `model`'s upper 3×3 (`mat4_normal`), so a
  non-uniform scale shades correctly. `tests/test_normals.goose` compares a
  stretched mesh against an equivalent baked one, and fails if the plain model
  matrix is used instead.
* `params.x` is 1 when the material is unlit, `y` metallic, `z` roughness, `w`
  normal-map strength (0 when there is no map, so the shader skips the tangent
  frame and the extra tap); `direction.w` carries ambient; `color.w` carries the
  number of point lights, whose `(position, radius)` and `(colour, 0)` pairs fill
  `points`. The block is a fixed 288 bytes so one shader serves any number of
  lights up to `MAX_POINT_LIGHTS` (8).
* `Material` deliberately stayed 64 bytes: emissive colour went into its own
  `Surface` block instead, so 0.2's custom shaders (and the demo's
  `stripes.frag`) still declare exactly what they declared before. The same
  reason kept `Frame` at 224 bytes in 0.4: the IBL strength went into
  `params.w`, which the mesh shader had never used, instead of a new field.
* The sky and composite shaders reuse set 3 binding 0 for a 32-byte `Post`
  block. Binding state is per pipeline, so a pipeline that declares `Material`
  there and one that declares `Post` do not interfere: the shader's own layout
  decides what a push means, and the backend checks the size against it.
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

No `gfx` types, no storage buffers, no compute, and no way for an application
to name a render target: the HDR, depth, bloom and shadow targets are the
device's own, created from the settings, and drawn into by the fixed passes.
Pipeline state (cull, blend, depth, wireframe) and custom shader pairs are
*data* — a `MaterialDesc` and a `Shader` handle — so an application still never
touches a backend descriptor. Storage buffers, compute and application-owned
render targets arrive only with a concrete use case (see
[ROADMAP.md](ROADMAP.md)).

## 6. Frames and draw submission

```goose
while hipgr::begin_frame(dev, camera, clear) {
    hipgr::draw(dev, mesh, material, model_matrix);   // once per object
    if !hipgr::end_frame(dev) { break; }              // false = quit requested
}
```

* `begin_frame` validates the device and frame state, sizes the render targets
  to the current screen, ensures the pass pipelines exist, stores the camera and
  the clear colour, and starts recording.
* `draw` validates the mesh, the material and the images it names, appends a
  `DrawItem` to the frame's list, and updates `Stats`. It draws nothing.
* `end_frame` builds the frame's uniform blocks, runs the four passes, presents,
  and returns the backend's "keep going" flag.
* The recorded list is `end_frame`'s input to the plan in `submit.goose`: cull,
  order, batch. `draw` itself does no work beyond validation and appending.

Recording exists because a frame is not one pass any more. The shadow pass has
to see the whole scene before the scene pass starts, and the scene pass has to
finish before bloom can read it. Splitting `draw` from the passes costs one
appended struct per draw and buys an ordering that cannot be got wrong from the
application side; it is also where 0.4's sorting and culling will live.

```
end_frame
  ├─ plan       cull, order (opaque, then transparent back to front), batch;
  │             fill and upload the instance buffer
  ├─ shadow     depth from the light, the casters inside the light's box,
  │             one draw per mesh, 1024² depth target
  ├─ scene      sky (full-screen triangle), then each batch with its material,
  │             into RGBA16F + depth
  ├─ bloom      bright pass (> threshold) → blur H → blur V, at half resolution
  └─ composite  scene + bloom × strength, × exposure, tone curve, sRGB encode →
                screen
```

The plan is built before the first pass so that a pipeline the batcher needs is
created outside one. The shadow pass has a plan of its own, built from the same
item bounds against the light's view-projection instead of the camera's: culling
it with the camera's frustum would delete shadows cast by objects the camera
cannot see. Its batches group by mesh alone, since a depth pass ignores the
material, and its instance pool holds 64-byte records (the model matrix) because
the backend takes the stride from the shader.

The sky and the three post passes draw three vertices with no vertex buffer
(`gl_VertexIndex`), so they cost no state changes beyond one pipeline bind. The
bloom chain is skipped entirely when the strength is 0, and the shadow pass when
shadows are off or nothing was recorded, which is what makes `QUALITY_LINEAR`
cheap.

Image-based lighting adds no pass. Its two cubes are integrated on the **CPU**
by `env.goose`, because the environment is HiPGR's own two-colour sky gradient:
a function, not a captured image, so it can be sampled for a direction directly
rather than rendered and blurred on the GPU. That removes a whole chain (capture
pass, blur mips, readback) and makes the result deterministic and testable on a
machine with no display. The cost is a one-off integral — ~60k samples for the
irradiance and prefiltered cubes together — paid when the device opens and
whenever `set_sky` changes the colours, never per frame. A captured probe or an
HDR environment map would need the GPU path the current sky does not.

A non-batched draw costs: one pipeline bind, two buffer binds, two uniform
pushes, up to five texture binds (albedo, normal map, and the two environment
cubes, bound per built-in material) and one indexed draw. A batched draw costs
the same state plus one draw for however many instances the run covers: the
per-object cost disappears, which is why 10,000 cubes fall from 10,000 draw calls
to 2 in `bench_10k`. The frame, light, surface and post blocks are pushed once
per frame. On a CPU rasterizer at 1280×720, 256 cubes measure 9.9–10.1 ms/frame
under `QUALITY_LINEAR` and 25.0–25.6 ms/frame under `QUALITY_MODERN` across runs
(see [PROGRESS.md](PROGRESS.md)) — the gap is the shadow pass and the three post
passes, and it is a software rasterizer's gap, not a GPU's. IBL's share of the
modern frame, measured by switching it off in the demo at 960×540, is about 11%
on the same device.

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
| Application-owned render targets, render-to-texture | the four targets HiPGR needs are the device's; nothing has asked for a caller's | a UI layer, a portal, or a second camera sharing a frame |
| Multi-sample anti-aliasing | not yet measured against the cost of a bigger target | visible edge crawling in a real scene, and a measurement to justify the memory |
| Cascaded shadow maps | one 1024² box covers the demo's scene at no visible cost | a scene larger than one box, measured |
| Instancing / batching / culling | must be justified by benchmarks (0.4) | a scene that needs them, measured |
| Runtime backend selection | Goose has no runtime polymorphism | never, within Goose's current model |
| Shader hot reload | `embed_shader` is compile-time | shader iteration becoming the bottleneck; would need a file-watch + runtime-compile path outside `gfx` |

The largest structural risk is the opposite of over-engineering: if `gfx` turns
out to be the bottleneck on real hardware, the replacement is a native C layer
behind `gpu.goose`, and the renderer above it should not need to change. That
is the test of whether this boundary was drawn correctly.
