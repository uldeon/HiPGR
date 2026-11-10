# HiPGR — Progress

As of 2026-11-10, HiPGR **0.1.0**.

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
| RGBA8 textures, upload from bytes | **Verified** | `test_cube_textured` (both checker colours counted) |
| Samplers | **Verified** | linear + clamp, used by textured materials |
| Shader compilation (`embed_shader`, library-owned shaders) | **Verified** | built-in shaders compile into every program; two fragment shaders in use |
| Pipelines (shared, cached per kind) | **Verified** | both material kinds render |
| Depth test + write | **Verified** | `test_depth` |
| Back-face culling | **Implemented** | cube renders solid from outside; **no test** for a wound-wrong face being culled |
| Viewport / scissor | **Planned** | not exposed yet (0.2) |
| Present / quit handling | **Verified** | demo `--frames`, window close path (`end_frame` false) |

### Resources

| Feature | Status | Evidence / gap |
|---|---|---|
| Generation-checked handles | **Verified** | `test_handles`: stale, zero, double-release all rejected |
| Immediate release of GPU objects | **Verified** | `test_handles`; `gfx` would report a released handle, and does not, because HiPGR rejects first |
| Device-owned sweep on `close` | **Verified** | `test_handles` closes with live resources and exits cleanly |
| Index validation before upload | **Verified** | `test_handles` (out-of-range index rejected) |
| Material → image lifetime check | **Verified** | `test_handles` (released image caught at draw) |
| Slot recycling / compaction | **Planned** | records are append-only in 0.1; handles already carry generations |
| Texture mipmaps / sRGB | **Planned** | 0.2 |

### 3D rendering

| Feature | Status | Evidence / gap |
|---|---|---|
| Perspective camera, look-at, view-projection | **Verified** | `test_camera` (CPU) + every 3D render test |
| Orthographic camera | **Tested (CPU)** | `test_camera`; no ortho render test yet |
| Free camera in the demo | **Implemented** | WASD/mouse; not exercised (no display) |
| Meshes: triangle, quad, cube | **Verified** | tests |
| Multiple objects | **Verified** | `test_many_draws` (256 cubes) |
| Transform matrices, TRS | **Verified** | `test_camera`, `test_many_draws` |
| Textured materials | **Verified** | `test_cube_textured` |
| Solid (tint) materials | **Verified** | `test_triangle`, `test_depth` |
| Directional light + ambient | **Implemented** | lit renders look plausible; **no test asserts shading values** |
| Point lights | **Planned** | 0.2 |
| Multiple materials in one frame | **Verified** | `test_depth` (two solid materials), demo (textured + solid) |
| Unlit materials | **Verified** | used by `test_triangle` and `test_cube_textured` |
| Non-uniform scale with a normal matrix | **Planned** | 0.2; normals are rotated by the model matrix only |
| Mesh animation / skinning | **Planned** | no milestone yet |

### Modern rendering

| Feature | Status |
|---|---|
| PBR, normal maps, emissive | **Planned** (0.3) |
| HDR, tone mapping | **Planned** (0.3) |
| Shadow maps | **Planned** (0.3) |
| Skybox, environment lighting | **Planned** (0.3) |
| Bloom, anti-aliasing, fog | **Planned** (0.3) |

None of these exists. The repository contains no shader that pretends to.

### Performance

| Feature | Status | Evidence / gap |
|---|---|---|
| Stats (frames/draws/triangles/resources) | **Verified** | asserted in every render test |
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

### Platform and tooling

| Feature | Status | Evidence / gap |
|---|---|---|
| Linux x64 | **Verified** | this environment, software Vulkan |
| Windows x64 | **Untested** | no machine; steps in RECONNAISSANCE §9 |
| Direct3D 12 / Metal backends | **Untested** | Vulkan only here; shaders are compiled for all backends at build time |
| Test runner with SKIP reporting | **Implemented** | `scripts/test.sh` |
| Zero-warning build | **Verified** | `goose check` clean for all 9 root programs |
| API-isolation guard | **Verified** | `test.sh` fails on `import gfx;` in examples/tests/bench |

## Verification evidence

```
$ ./scripts/test.sh
ok   test_camera
ok   test_cube_textured
ok   test_depth
ok   test_handles
ok   test_many_draws
ok   test_triangle

6 passed, 0 skipped, 0 failed
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

Benchmark on this machine (llvmpipe, **not** a hardware number):

```
HiPGR 0.1.0 benchmark: 256 cubes, 60 frames, driver vulkan
frames 60, draws 15360, triangles 184320
elapsed 0.452 s, 7.54 ms/frame, 133 fps      (1280x720, textured + lit)
```

Demo (960x540, 50 cubes): 3.3–4.5 ms/frame on the same software device.

## Known gaps and risks

1. **No hardware GPU.** Correctness is verified; performance is not meaningful.
2. **No Windows verification**, and no D3D12/Metal run. The uniform layout and
   shaders are backend-neutral, but that is an argument, not a test.
3. **Windowed mode unverified here** (no display). The input code path is
   exercised only in headless form.
4. **Lighting is untested numerically** — no test asserts a shaded value, so
   "directional lighting works" rests on visual plausibility, not a check.
5. **`image_load` is untested** against a real PNG on disk.
6. **Records are append-only**; a workload that creates and destroys resources
   every frame would grow the registry.
7. **Custom shaders are not exposed**, so an application with unusual material
   needs waits for 0.2.
8. **`gfx` is young**; the API may change between Goose releases. Pin v2026.4.

## Next three tasks

1. **0.2 material description**: pipeline state + custom shaders with a
   documented uniform contract, so the API stops being tint-and-texture only.
2. **Lighting and texture tests**: assert shaded values for a known
   normal/light pair, and load a real PNG to cover `image_load`.
3. **Windows verification run**: build, run the demo and the tests on a Windows
   machine with a real GPU, and record driver + frame times here.
