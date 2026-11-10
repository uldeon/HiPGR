# HiPGR — Progress

As of 2026-11-10, HiPGR **0.3.0**. The foundation and 0.2's material system are
unchanged; 0.3 added a deferred multi-pass frame, an HDR target with tone
mapping, PBR shading with normal maps and emissive, one shadow map, bloom, a
procedural sky and fog.

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

| Feature | Status | Evidence / gap |
|---|---|---|
| Deferred frame (record, then four passes) | **Verified** | every render test; `draw` returns before anything is rendered, `end_frame` runs shadow → scene → bloom → composite |
| HDR RGBA16F scene target | **Verified** | `test_tonemap`: a 2.0 unlit surface stays above 1.0 long enough to bloom, a 0.5 one reads back exactly 128 with no curve |
| Tone mapping (NONE / Reinhard / ACES) + gamma | **Verified** | `test_tonemap`: 128 / 155 / 205 for a 0.5 grey, each within 2/255 of the curve's value |
| Exposure | **Verified** | `test_tonemap`: ×2 clips to 255, ×0.5 reads 64, 0 is refused |
| PBR metallic/roughness | **Verified** | `test_pbr`: a metal loses its diffuse lobe (247 → <120), a polished metal is brighter head-on than a rough one, out-of-range values refused |
| Normal maps | **Verified** | `test_pbr`: a map pointing at a side light turns a dark surface (>20) bright (>200); strength 0 matches no map within 1/255 |
| Emissive | **Implemented** | `demo_cube` uses it for the glowing props; no test reads a known emissive value back |
| Shadow map (one, PCF, bias) | **Verified** | `test_shadows`: probe <100 in shadow, >20 (ambient kept), 255 with shadows off, 255 outside the shadow, and the shadow follows the light |
| Bloom (threshold, separable blur) | **Verified** | `test_tonemap`: a 2.0 quad glows >20/255 next to it, the glow fades with distance, a 0.8 quad below the threshold does not glow at all |
| Procedural sky (cube, view ray) | **Verified** | `test_environment`: blue at the horizon, darker at the zenith, clear colour when disabled |
| Distance fog | **Verified** | `test_environment`: a white surface at 23 units loses red and gains blue towards the horizon; 0 density leaves it at 255 |
| Quality profiles | **Verified** | 0.1/0.2 assertions still hold exactly under `QUALITY_LINEAR`; the demo runs `QUALITY_MODERN` |
| Image-based lighting / reflections | **Planned** (0.4) | metals have no environment to reflect, so they read dark: visible in `demo_cube` and stated there |
| sRGB texture sampling, mip generation | **Planned** (0.4) | gamma is applied on output, textures are sampled as UNORM at mip 0 |
| MSAA, cascaded shadows, sorted transparency | **Planned** (0.4) | one shadow box, no anti-aliasing, submission order |

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
ok   test_environment
ok   test_handles
ok   test_lights
ok   test_many_draws
ok   test_materials
ok   test_normals
ok   test_pbr
ok   test_shadows
ok   test_tonemap
ok   test_triangle

14 passed, 0 skipped, 0 failed
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
| `test_tonemap` | a 0.5 unlit grey reads 128 with no curve, 155 with Reinhard, 205 with ACES; the curves are ordered; exposure ×2 clips and ×0.5 halves, 0 refused; a 2.0 quad blooms while a 0.8 one below the threshold does not, and the glow fades with distance |
| `test_pbr` | matte white dielectric 247, metal <120 (no diffuse lobe), polished metal brighter head-on, metallic 1.5 and roughness −0.1 refused; a normal map meeting a side light turns a <20 surface into >200; strength 0 matches no map within 1/255 |
| `test_shadows` | under a slanted light spot A is <100 (shadow) while spot B is 255; ambient keeps the shadow above 20; shadows off makes both 255; moving the light swaps A and B |
| `test_environment` | the sky is blue at the horizon and darker at the zenith, and the clear colour shows when it is off; fog darkens a far white quad and tints it blue, and a negative density is refused |

Checks that the tests have teeth, done by breaking the code on purpose:

* Replacing `mat4_normal(model)` with `model` in `renderer.goose` makes
  `test_normals` fail (`a stretched mesh shades like the equivalent baked one`),
  and the failure disappears when it is restored.
* Pushing casters towards the light in `shadow.vert` (a normal offset) made the
  *receiving* wall offset itself too, so the whole scene was shadowed while the
  occluders read as lit. `test_shadows` caught it; the offset was removed and
  the bias stays in the fragment shader only.
* Dropping the sign of the UV Jacobian in the tangent frame rotated the normal
  map by 180°: `test_pbr`'s mapped surface turned *away* from the light. The
  sign is part of the frame's construction now.
* An earlier version of the blend test drew the transparent quad at the same
  depth as its background; it read back pure red, which is exactly the failure
  the test is meant to catch. The test now offsets the quad.

Benchmark on this machine (llvmpipe, **not** a hardware number):

```
HiPGR 0.3.0 benchmark: 256 cubes, 40 frames, driver vulkan
linear: 13.59 ms/frame, 74 fps        (1280x720, PBR, no post chain)
modern: 29.14 ms/frame, 34 fps        (1280x720, + shadow pass, sky, bloom,
                                       tone mapping at 1280x720)
```

The same scene under 0.2 measured 7.5 ms/frame at 256 cubes. The difference is
not the draw submission (unchanged) but the shading and the targets: PBR costs
more per pixel than Lambert, the scene pass writes 8-byte RGBA16F instead of
4-byte RGBA8, and every frame pays one full-screen composite pass. The `modern`
line adds a 1024² shadow pass, a full-screen sky and three more full-screen
passes, which on a CPU rasterizer is where half the frame goes. On hardware
these are bandwidth-bound and should be a fraction of this; **that is a
prediction, not a measurement**, and it is why 0.4's numbers need a real GPU.

Demo (960×540, 34 draws, shadows + bloom + sky + fog): ~40 ms/frame.

## Known gaps and risks

1. **No hardware GPU.** Correctness is verified; performance is not meaningful.
2. **No Windows verification**, and no D3D12/Metal run. The uniform layout and
   shaders are backend-neutral, but that is an argument, not a test.
3. **Windowed mode unverified here** (no display). The input code path is
   exercised only in headless form.
4. **`image_load` is untested** against a real PNG on disk.
5. **No sRGB texture sampling or mipmaps.** Output is gamma-encoded by the
   composite pass, but textures are sampled as plain UNORM at mip 0, so a
   minified texture aliases and a texture authored in sRGB is slightly wrong. 0.4.
6. **No image-based lighting.** Metals have no environment to reflect, so they
   read dark except where a light hits them. An irradiance term and a
   prefiltered probe are 0.4.
7. **One shadow map, one box, no cascades.** A scene larger than the
   `shadow_area` box loses shadows outside it, and a low sun stretches the
   texels. Stated in the API docs; cascades are 0.4.
8. **Records are append-only**; a workload that creates and destroys resources
   every frame would grow the registry.
9. **Transparency is unsorted.** A blended material must be drawn after the
   opaque ones by the application until 0.4 adds sorting.
10. **`mesh_update` is 16-bit only**, and only for meshes created that way.
11. **`gfx` is young**; the API may change between Goose releases. Pin v2026.4.

## Next three tasks

1. **Image-based lighting** — an irradiance term for diffuse and a prefiltered
   environment probe for specular, from the same sky cube. Without it metals
   reflect nothing, which is the largest quality gap 0.3 leaves open.
2. **Texture completeness** — sRGB sampling, mip generation, and an `image_load`
   test against a real file on disk.
3. **Windows verification run** — build, run the demo and the tests on a Windows
   machine with a real GPU, and record driver and frame times here.
