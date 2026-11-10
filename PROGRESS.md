# HiPGR — Progress

As of 2026-11-10, HiPGR **0.2.0**. 0.1's foundation is unchanged; 0.2 added
materials as data, custom shaders, point lights, the normal matrix, 32-bit
indices and geometry updates.

Status vocabulary, used strictly:

| Status | Meaning |
|---|---|
| **Verified** | implemented, compiled, executed, and the rendered result was checked by reading pixels back |
| **Tested (CPU)** | logic implemented and tested without a GPU |
| **Implemented** | code exists and runs, but no test inspects its result |
| **Partial** | works for a subset, with the gaps listed |
| **Planned** | designed, not written |
| **Blocked** | needs something this environment does not have |

Nothing here is called "done" because it compiles.

---

## Feature status

### Foundation

| Feature | Status | Evidence / gap |
|---|---|---|
| Device creation, windowed | **Implemented** | `examples/demo_cube` opens a window; this container has no display, so windowed mode was never observed here |
| Device creation, headless | **Verified** | every test; `gfx`'s offscreen path |
| Frame lifecycle (`begin_frame`/`draw`/`end_frame`) | **Verified** | all rendering tests |
| Screen + depth buffer | **Verified** | `test_depth` distinguishes draw order from depth order |
| Vertex / index buffers | **Verified** | `test_triangle`, `test_cube_textured` |
| 32-bit index buffers | **Verified** | `test_big_mesh` (66049 vertices, `index_size == 4`, renders) |
| Geometry updates (grow and shrink) | **Verified** | `test_big_mesh` (`mesh_update` on the same handle) |
| RGBA8 textures, upload from bytes | **Verified** | `test_cube_textured` (both checker colours counted) |
| Samplers, per material | **Verified** | chosen by `MaterialDesc.filter`/`wrap`, cached per combination |
| Shader compilation (`embed_shader`, library and application shaders) | **Verified** | built-in pairs and `test_materials`' custom pair |
| Custom shader pairs | **Verified** | `test_materials`: a pair embedded by the test, reading `Material.user0` |
| Pipelines, cached by state | **Verified** | `test_materials` asserts that identical state shares one and different state makes another |
| Depth test + write, per material | **Verified** | `test_depth`; `test_materials` uses `depth_write: false` for blending |
| Back-face / front-face culling | **Verified** | `test_materials`: `CULL_FRONT` removes a quad, `CULL_BACK` keeps it |
| Wireframe | **Verified** | `test_materials`: far fewer pixels than the filled cube |
| Alpha blending | **Verified** | `test_materials`: 50% blue over red reads back as 128,0,128 |
| Viewport / scissor | **Planned** | not exposed yet |
| Present / quit handling | **Verified** | demo `--frames`, window close path (`end_frame` false) |

### Resources

| Feature | Status | Evidence / gap |
|---|---|---|
| Generation-checked handles | **Verified** | `test_handles`: stale, zero, double-release all rejected |
| Immediate release of GPU objects | **Verified** | `test_handles`; `gfx` would report a released handle, and does not, because HiPGR rejects first |
| Device-owned sweep on `close` | **Verified** | `test_handles` closes with live resources and exits cleanly |
| Index validation before upload | **Verified** | `test_handles`, `test_big_mesh` (out-of-range index rejected, mesh unchanged) |
| Material → image lifetime check | **Verified** | `test_handles` (released image caught at draw) |
| Pipeline / sampler caching | **Verified** | `test_materials` (`Stats.pipelines` before and after) |
| State validation | **Verified** | `test_materials` (cull 7 → `ERR_BAD_ARGUMENT`) |
| Slot recycling / compaction | **Planned** | records are append-only; handles already carry generations |
| Texture mipmaps / sRGB | **Planned** | deferred to 0.3, with output encoding (see ROADMAP) |

### 3D rendering

| Feature | Status | Evidence / gap |
|---|---|---|
| Perspective camera, look-at, view-projection | **Verified** | `test_camera` (CPU) + every 3D render test |
| Orthographic camera | **Tested (CPU)** | `test_camera`; no ortho render test yet |
| Free camera in the demo | **Implemented** | WASD/mouse; not exercised (no display) |
| Meshes: triangle, quad, cube | **Verified** | tests |
| Large meshes (66049 vertices) | **Verified** | `test_big_mesh` |
| Multiple objects | **Verified** | `test_many_draws` (256 cubes) |
| Transform matrices, TRS | **Verified** | `test_camera`, `test_many_draws` |
| Textured materials | **Verified** | `test_cube_textured` |
| Solid (tint) materials | **Verified** | `test_triangle`, `test_depth` |
| Three materials + two light kinds in one frame | **Verified** | `test_materials`; demo uses four materials |
| Custom shader material with own data | **Verified** | `test_materials` (`user0` reaches the shader exactly) |
| Wireframe, blended, culled materials | **Verified** | `test_materials` |
| Directional light | **Verified** | `test_lights` (head-on light is full brightness; black colour contributes nothing) |
| Point lights | **Verified** | `test_lights` (falloff value, two lights add, radius clips, `MAX_POINT_LIGHTS` enforced) |
| Non-uniform scale with a normal matrix | **Verified** | `test_normals`, checked against a deliberate regression |
| Unlit materials | **Verified** | `test_triangle`, `test_cube_textured`, `test_materials` |
| Mesh animation / skinning | **Planned** | geometry updates exist; no skinning |
| Sorted transparency | **Planned** | 0.4, with the benchmark that justifies it |

### Modern rendering

| Feature | Status |
|---|---|
| PBR, normal maps, emissive | **Planned** (0.3) |
| HDR render target, tone mapping, sRGB output | **Planned** (0.3) |
| Shadow maps | **Planned** (0.3) |
| Skybox, environment lighting | **Planned** (0.3) |
| Bloom, anti-aliasing, fog | **Planned** (0.3) |

None of these exists. The repository contains no shader that pretends to.

### Performance

| Feature | Status | Evidence / gap |
|---|---|---|
| Stats (frames/draws/triangles/resources/caches) | **Verified** | asserted in every render test |
| Frame benchmark | **Implemented** | `bench/bench_scene.goose`, `scripts/bench.sh` |
| Meaningful performance numbers | **Blocked** | only a CPU Vulkan device (llvmpipe) is available |
| Frustum culling, instancing, batching, render graph, profiling | **Planned** (0.4) | gated on real GPU measurement |

### Assets and formats

| Feature | Status | Evidence / gap |
|---|---|---|
| RGBA8 texture from bytes | **Verified** | tests |
| Procedural checkerboard | **Verified** | tests |
| PNG/BMP load through the backend | **Implemented** | `image_load`; **no test** with a real file on disk yet |
| glTF / GLB, KTX2, HDR environment maps | **Planned** | no importer exists; `gfx` loads PNG/BMP only |
| Shader files in the library | **Verified** | `src/hipgr/shaders/*.vert|.frag` |
| Application shader files | **Verified** | `tests/shaders/*`, `examples/shaders/*` |

### Platform and tooling

| Feature | Status | Evidence / gap |
|---|---|---|
| Linux x64 | **Verified** | this environment, software Vulkan |
| Windows x64 | **Untested** | no machine; steps in RECONNAISSANCE §9 |
| Direct3D 12 / Metal backends | **Untested** | Vulkan only here; shaders are compiled for all backends at build time |
| Test runner with SKIP reporting | **Implemented** | `scripts/test.sh` |
| Zero-warning build | **Verified** | the runner fails on any compiler warning in any root program |
| API-isolation guard | **Verified** | `test.sh` fails on `import gfx;` in examples/tests/bench |

## Verification evidence

```
$ ./scripts/test.sh
ok   test_big_mesh
ok   test_camera
ok   test_cube_textured
ok   test_depth
ok   test_handles
ok   test_lights
ok   test_many_draws
ok   test_materials
ok   test_normals
ok   test_triangle

10 passed, 0 skipped, 0 failed
```

Test-by-test, what was actually checked:

| Test | Checks |
|---|---|
| `test_triangle` | centre and upper-centre pixels are the tint; three corners are the clear colour; stats; screen size |
| `test_cube_textured` | both checker texels present in quantity, background corner intact, centre is cube not background, yaw rotation changes >500 pixels, stats |
| `test_depth` | near-first and near-last both keep the near quad; far quad alone is visible |
| `test_handles` | released mesh: no info, draw rejected with `ERR_BAD_HANDLE`, double release rejected, zero handle rejected, released image caught, nested frame rejected, no-frame rejected, bad index rejected, close with live resources, closed device rejected |
| `test_camera` | forward/right vectors, view-space position, NDC centre and depth range, behind-camera sign, aspect effect, ortho centre, TRS composition |
| `test_many_draws` | 256 draws × 3 frames counted, 12 triangles each, scene not blank, background partly visible |
| `test_materials` | three materials (textured, solid, custom shader) + directional and point light in one frame; `user0` arrives exactly; identical state shares a pipeline; different state makes one; wireframe draws ≪ the filled cube but > 0; `CULL_FRONT` erases a quad; alpha blend reads back 128,0,128; cull 7 rejected |
| `test_normals` | `mat4_normal` columns for scale(2,1,1); a model-scaled mesh shades the same as an equivalent baked mesh (within 3/255); full brightness at the expected ndl |
| `test_lights` | directional head-on is full brightness; black directional contributes nothing; one point light ≈ 235 with radius 10 at distance 2; two lights brighter than one; clearing darkens; beyond radius contributes nothing; bad radius, bad index and zero direction rejected |
| `test_big_mesh` | 66049 vertices with `index_size == 4` renders; growth to 1089 vertices and shrink back to 3 on one handle; a 32-bit mesh refuses 16-bit updates; out-of-range index refused without changing the mesh; 16-bit `mesh_create` refuses >65536 vertices |

Two checks that the tests have teeth, done by breaking the code on purpose:

* Replacing `mat4_normal(model)` with `model` in `renderer.goose` makes
  `test_normals` fail (`a stretched mesh shades like the equivalent baked one`),
  and the failure disappears when it is restored.
* An earlier version of the blend test drew the transparent quad at the same
  depth as its background; it read back pure red, which is exactly the failure
  the test is meant to catch. The test now offsets the quad.

Benchmark on this machine (llvmpipe, **not** a hardware number):

```
HiPGR 0.2.0 benchmark: 256 cubes, 60 frames, driver vulkan
frames 60, draws 15360, triangles 184320
elapsed 0.452 s, 7.53 ms/frame, 133 fps      (1280x720, textured + lit)

HiPGR 0.2.0 benchmark: 1024 cubes, 60 frames, driver vulkan
frames 60, draws 61440, triangles 737280
elapsed 1.497 s, 24.95 ms/frame, 40 fps      (1280x720, textured + lit)
```

The 0.1 baseline was 7.54 ms/frame at 256 cubes, so the larger draw block
(64 → 128 bytes) is inside the noise on this device. That is not evidence that
it is free on hardware; it is evidence that nothing regressed measurably here.

Demo (960×540, 55 cubes, one point light, translucent shell): 6.4 ms/frame.

## Known gaps and risks

1. **No hardware GPU.** Correctness is verified; performance is not meaningful.
2. **No Windows verification**, and no D3D12/Metal run. The uniform layout and
   shaders are backend-neutral, but that is an argument, not a test.
3. **Windowed mode unverified here** (no display). The input code path is
   exercised only in headless form.
4. **`image_load` is untested** against a real PNG on disk.
5. **No sRGB or mipmaps.** Textures are sampled linearly at mip 0, so a minified
   texture aliases. Deferred with output encoding (0.3), because doing one
   without the other would shift every colour.
6. **Records are append-only**; a workload that creates and destroys resources
   every frame would grow the registry.
7. **Transparency is unsorted.** A blended material must be drawn after the
   opaque ones by the application until 0.4 adds sorting.
8. **`mesh_update` is 16-bit only**, and only for meshes created that way.
9. **`gfx` is young**; the API may change between Goose releases. Pin v2026.4.

## Next three tasks

1. **0.3: modern rendering** — PBR, a normal map, an HDR target with tone
   mapping and sRGB output, shadows, a skybox, bloom. Each with a read-back test
   and a measured cost.
2. **Texture completeness** — mip generation and sRGB with output encoding, and
   an `image_load` test against a real file on disk.
3. **Windows verification run** — build, run the demo and the tests on a Windows
   machine with a real GPU, and record driver and frame times here.
