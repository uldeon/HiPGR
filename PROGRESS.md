# HiPGR — Progress

As of 2026-11-14, HiPGR **0.5.0**. 0.3 added a deferred multi-pass
frame, an HDR target with tone mapping, PBR shading with normal maps and
emissive, one shadow map, bloom, a procedural sky and fog. 0.4 added
**image-based lighting from the sky** (an irradiance cube and a prefiltered
radiance cube, so metals reflect the sky), **frustum culling, sorted transparency
and instanced draw batching**, and **sRGB texture decode with generated mips**.
0.5 adds **culling and instancing for the shadow pass** (measurably 2–3× cheaper
at 10k objects), **sRGB output encoding**, and a **recorded, gated public API**
with an out-of-package consumer built from a clean copy of the tree. The
optimisations are on by default because they won on a measured scene, and each
has a test that its output is pixel-identical to the path it replaces.

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
| Texture mips (generated) | **Verified** | `test_texture_mips`: reads levels 1 and 2 back from the GPU; level 2 is the image's average |
| sRGB texture decode | **Verified** | `test_texture_mips`: a 128 grey reads 55 through the sRGB path and 128 through the linear one |
| sRGB *output* encoding | **Verified** | `test_tonemap`: the tone-curve values were recomputed from the piecewise sRGB curve (Reinhard 156, ACES 206) and match within 2/255; `TONEMAP_NONE` still writes the linear value unchanged |

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
| Sorted transparency | **Verified** | `test_transparency`: near-first and far-first submission produce the same pixels, and the result is the arithmetically correct composite (64,0,128), not the swapped one |

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
| Quality profiles | **Verified** | 0.1/0.2 assertions still hold exactly under `QUALITY_LINEAR` (which now also sets IBL off); the demo runs `QUALITY_MODERN` |
| Image-based lighting (irradiance + prefiltered sky) | **Verified** | `test_ibl`: a mirror reflects blue/red/zenith sky exactly as the sky is coloured, a constant 0.8 sky lights a matte surface to 225/255, a green sky lights it green, a rough metal gathers the horizon a mirror misses, an unlit surface is black with IBL off |
| IBL off reproduces 0.2's ambient | **Verified** | `test_ibl`: with IBL off and the modern extras off, the pixel equals `QUALITY_LINEAR` exactly (tolerance 0) |
| Prefiltered specular (roughness → mip, split-sum BRDF) | **Verified** | `test_ibl`: rough 0.04 metal reads 16/0/227 towards the zenith, rough 1.0 reads 119/0/168 from the same direction |
| sRGB texture sampling, mip generation | **Verified** | `test_texture_mips` (decode and levels, above) |
| Screen-space / occluded reflections | **Planned** | IBL reflections are unoccluded: a metal reflects the sky even indoors |
| MSAA, cascaded shadows | **Planned** | one shadow box, no anti-aliasing |

### Performance

| Feature | Status | Evidence / gap |
|---|---|---|
| Stats (frames/draws/triangles/resources/caches/culled/batches/instances) | **Verified** | asserted in every render test; the plan counters in `test_culling` and `test_batching` |
| Frame benchmark | **Implemented** | `bench/bench_scene.goose` (256 cubes, linear vs modern), `bench/bench_10k.goose` (10k objects, four configurations) |
| Meaningful performance numbers | **Blocked** | only a CPU Vulkan device (llvmpipe) is available; ratios are usable, absolute times are not |
| Frustum culling | **Verified** | `test_culling`: 18 of 44 objects culled, pixel-identical to the unculled frame, an object straddling the edge kept, a huge quad covering the view kept |
| Draw batching and instancing | **Verified** | `test_batching`: 240 objects with 3 materials become 3 instanced draws (from 240), pixel-identical to the unbatched frame, and the draw count is unchanged |
| Instancing and culling the shadow pass | **Verified** | `test_shadow_batches`: 50 casters → one draw per mesh, exactly the 8 outside the light's box skipped, pixel-identical to the unoptimised path; the off-screen caster's shadow survives |
| Shadow pass cost | **Measured** | `bench/bench_shadow` at 10k objects: 39.4 ms/frame at 0.4, 12.3 ms/frame now (best of the trials; 41.5 → 20.4 in the matched repeat pair) |
| Render graph, profiling counters | **Planned** | pass order is fixed in code; the counters above are what exists |

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
| Public API surface recorded and gated | **Verified** | `docs/api-surface.txt` + `scripts/api_surface.sh` in `scripts/test.sh`: a removed or changed declaration fails, an unrecorded new one fails until recorded. Checked by breaking the code on purpose in both directions |
| An out-of-package consumer builds and renders | **Verified** | `scripts/consumer.sh` builds `integration/consumer.goose` from a clean copy of the tree (tracked + untracked non-ignored files, no artifacts) and runs it headless |
| An independent demo in another repository | **Blocked** | needs a second remote; the clean-copy consumer is the closest check this repository can run |
| Windows x64 | **Untested** | no machine; steps in RECONNAISSANCE §9 |
| Direct3D 12 / Metal backends | **Untested** | Vulkan only here; shaders are compiled for all backends at build time |
| Test runner with SKIP reporting | **Implemented** | `scripts/test.sh` |
| Zero-warning build | **Verified** | the runner fails on any compiler warning in any root program |
| API-isolation guard | **Verified** | `test.sh` fails on `import gfx;` in examples/tests/bench |

## Verification evidence

```
$ ./scripts/test.sh
ok   api-surface
ok   test_batching
ok   test_big_mesh
ok   test_camera
ok   test_cube_textured
ok   test_depth
ok   test_environment
ok   test_handles
ok   test_ibl
ok   test_lights
ok   test_many_draws
ok   test_materials
ok   test_normals
ok   test_batching
ok   test_culling
ok   test_pbr
ok   test_shadow_batches
ok   test_shadows
ok   test_texture_mips
ok   test_tonemap
ok   test_transparency
ok   test_triangle

21 passed, 0 skipped, 0 failed
```

The 21st is the API-surface check; the twenty after it are GPU tests. From a
clean copy of the tree, `./scripts/consumer.sh` additionally builds and runs the
out-of-package consumer.

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
| `test_ibl` | with no direct light and no ambient: a mirror metal reflects a blue sky as blue (B > 190, R/G < 10) and a red sky as red; a matte surface under a constant 0.8 sky reads 225 (the ACES value for 0.8, within 8 of it) and is grey, but black with IBL off; a green sky turns it green; a mirror pointing at a red-horizon/blue-zenith sky reads 16/0/227 and the same surface at roughness 1.0 reads 119/0/168; IBL off matches `QUALITY_LINEAR` exactly |
| `test_shadow_batches` | the receiver and 50 casters, eight of them outside the light's box and one the camera cannot see: unbatched the shadow pass submits 50 draws and culls none, optimised it submits 2 (one per mesh) and skips exactly 8, and the frames are pixel-identical; the camera culls 9 of the objects; turning shadows off changes >400 pixels, identically whether the culling switches are on or off |
| `test_culling` | 44 objects, 18 of them outside the frustum: with culling off none are culled, with it on exactly those 18 are, and the two frames are pixel-identical; an object straddling the left edge of the view is drawn; a quad covering the whole view is never culled (all 9216 pixels) |
| `test_batching` | 240 cubes, 3 materials interleaved: batching off gives 240 batches and no instanced draw, on gives 3 batches and 3 instanced draws over 240 instances, and the images are pixel-identical; all three materials are on screen; the draw count is unchanged; the same holds with culling on |
| `test_transparency` | two overlapping 50% quads submitted near-first and far-first produce identical pixels, and the composited value is 64,0,128 (far first), not 128,0,64; an opaque quad submitted after a transparent one is still drawn first |
| `test_texture_mips` | a 128 grey reads 55 through `image_rgba8_srgb` and 128 through `image_rgba8`; levels 0, 1 and 2 of a generated chain are read back from the GPU and level 2 is the image's average (128,0,128); a magnified mipmapped texture matches the same texture without mips |

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
HiPGR 0.4.0 benchmark: 256 cubes, 40 frames, driver vulkan
linear:  9.9–10.1 ms/frame           (1280x720, PBR, no post chain)
modern: 25.0–25.6 ms/frame           (1280x720, + shadow pass, sky, IBL, bloom,
                                      tone mapping)
```

Three runs of the same binary. 0.3 measured 13.6 and 29.1 ms on this scene; the
improvement is culling and batching, not a faster device, and llvmpipe's frame
times still move by 25% or more between runs on a shared container — the ranges
are the honest form.

10,000 objects, `bench_10k` (1280×720, modern profile, shadows and bloom on),
three interleaved trials of each configuration, same frames:

```
                          baseline   culling   batching   both
culled per frame                 0      4719          0    4719
draw calls per frame         10,000        73          2       2
trial 0, ms/frame            389.3     177.8      136.1   134.3   (2.9x)
trial 1, ms/frame            231.5     202.0      124.5   120.5   (1.9x)
```

Batching is the larger win at this object count (10,000 draw calls to 2), and
culling wins on its own (10,000 to 73 batches, ~4,700 objects skipped). The two
together are not quite culling's and batching's sum: the culler's per-object
cost is real, and at 2 draw calls the rest of the frame is fill. Across runs the
speedup of the defaults over the baseline measured 1.9x–5.5x; the ratio depends
on how loaded the container is at the time, the counts do not.

The same scene under 0.2 measured 7.5 ms/frame at 256 cubes. The difference is
not the draw submission (unchanged) but the shading and the targets: PBR costs
more per pixel than Lambert, the scene pass writes 8-byte RGBA16F instead of
4-byte RGBA8, and every frame pays one full-screen composite pass. The `modern`
line adds a 1024² shadow pass, a full-screen sky and three more full-screen
passes, which on a CPU rasterizer is where half the frame goes. On hardware
these are bandwidth-bound and should be a fraction of this; **that is a
prediction, not a measurement**, and it is why 0.4's numbers need a real GPU.

Demo (960×540, 34 draws, shadows + bloom + sky + fog), 20 frames, three runs:

```
IBL off: 44.2 / 46.4 / 47.8 ms per frame
IBL on:  49.6 / 51.7 / 56.0 ms per frame     (+11%: two cube taps and the
                                              split-sum BRDF per lit pixel)
```

A software rasterizer's number, and the only honest way to state IBL's cost
here; on hardware the same work is two cached cube fetches.

## Known gaps and risks

1. **No hardware GPU.** Correctness is verified; performance is not meaningful.
2. **No Windows verification**, and no D3D12/Metal run. The uniform layout and
   shaders are backend-neutral, but that is an argument, not a test.
3. **Windowed mode unverified here** (no display). The input code path is
   exercised only in headless form.
4. **`image_load` is untested** against a real PNG on disk.
5. **`TONEMAP_NONE` writes linear values, not sRGB.** The two tone-curve modes
   end in the sRGB transfer function, but `NONE` means what it says: no curve and
   no encode, which is what the exact-colour tests read. A program that wants
   linear output shown correctly on an sRGB display has to pick a curve (or
   encode itself).
6. **Reflections are unoccluded.** IBL reflects the sky from every direction, so
   a metal indoors reflects sky through walls. There is no screen-space or
   captured-probe pass; the environment is the sky and nothing else, and a
   scene with a different environment has no way to supply one yet.
7. **One shadow map, one box, no cascades.** A scene larger than the
   `shadow_area` box loses shadows outside it, and a low sun stretches the texels.
   The pass is culled against that box and instanced by geometry, but a scene with
   many *distinct* meshes still costs one draw per mesh.
8. **Records are append-only**; a workload that creates and destroys resources
   every frame would grow the registry.
9. **Transparency is sorted per object, not per triangle.** Overlapping parts of
   one transparent mesh, or interpenetrating ones, still blend in submission
   order within the object. Sorting is by world bounding-box centre distance,
   which is the standard approximation and is wrong for long thin geometry.
10. **`mesh_update` is 16-bit only**, and only for meshes created that way.
11. **`gfx` is young**; the API may change between Goose releases. Pin v2026.4.

12. **Culling and batching reorder work.** Opaque draws are grouped by geometry
    and material, transparent ones are sorted, and anything outside the frustum
    is dropped. Pixel equality is tested on the scenes in this repository, but a
    scene that relies on submission order between coplanar opaque surfaces (a
    decal exactly on a wall, z-fighting on purpose) could differ. Both switches
    can be turned off.

## Next three tasks

1. **A frozen public API** — the 0.5 roadmap item that does not exist yet: a
   versioned surface, a compatibility policy, and the two known gaps for a host
   (caller-owned window, custom material parameters).
2. **An out-of-tree consumer** — a program in another repository that builds
   against a tagged HiPGR, which is the only honest test of "usable as a
   library". Needs a second repository, so it is blocked here.
3. **Windows verification run** — build, run the demo and the tests on a Windows
   machine with a real GPU, and record driver and frame times here.
