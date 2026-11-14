# HiPGR — Roadmap

Milestones are gates, not schedules. A milestone is done when its **acceptance
criteria** pass in this repository — compiled, executed, and where it involves
pixels, checked by reading them back. [PROGRESS.md](PROGRESS.md) is the current
status; this file is the plan.

**Status: 0.1, 0.2, 0.3 and 0.4 complete (2026-11-14). 0.5 not started.**

---

## HiPGR 0.1 — GPU foundation ✅ complete

Deliver a renderer that initialises the GPU, owns resources safely, and draws a
triangle and a rotating textured cube, with the platform documented.

Delivered:

* device and surface (windowed and headless), frame lifecycle;
* vertex/index buffers, RGBA8 textures, samplers, pipelines;
* depth buffer, back-face culling, viewport;
* `Mesh`, `Image`, `Material`, `Camera`, `Mat4` with generation-checked handles;
* one directional light + ambient in the built-in materials;
* built-in geometry (triangle, quad, cube) and a checkerboard texture generator;
* demo application with a free camera and a switchable spin;
* test suite (6 tests) and a frame benchmark.

Acceptance criteria — **all met**:

| # | Criterion | Evidence |
|---|---|---|
| 1 | `goose check` is clean on every program, no warnings | `scripts/test.sh` builds every root file |
| 2 | A triangle renders in the expected place | `tests/test_triangle.goose` (centre and corners read back) |
| 3 | A textured cube renders, and rotates | `tests/test_cube_textured.goose` (both checker colours present; rotation changes >500 px) |
| 4 | Depth testing decides visibility, not draw order | `tests/test_depth.goose` (near-first and near-last both keep the near quad) |
| 5 | A released or invalid handle is an error, not a crash | `tests/test_handles.goose` |
| 6 | Multiple objects render in one frame | `tests/test_many_draws.goose` (256 cubes × 3 frames) |
| 7 | Applications never import the backend | `scripts/test.sh` fails on `import gfx;` outside the library |
| 8 | The demo runs independently of any engine | `examples/demo_cube.goose` |

Known gaps accepted for 0.1: no Windows verification, no real-GPU measurements,
windowed mode unverified in this container, append-only resource records.

## HiPGR 0.2 — 3D renderer ✅ complete (2026-11-10)

Delivered:

* **Material description as data**: `MaterialDesc` with `shader`, `image`,
  `tint`, `user0`/`user1`, `unlit`, `cull`, `blend`, `depth_test`,
  `depth_write`, `wireframe`, `filter`, `wrap`; unknown values are refused.
* **Custom shader pairs**: `shader_create` on `embed_shader` bytes, with the
  uniform-layout contract documented in `docs/API.md` §Shaders.
* **Pipeline and sampler caches**: shared by state, counted in `Stats`.
* **Normal matrix** (`mat4_normal`) carried in the draw block, so non-uniform
  scale shades correctly.
* **Lights**: one directional plus up to 8 point lights with smooth falloff to
  exactly zero at their radius, pushed once per frame.
* **Mesh data**: 32-bit indices (`mesh_create32`, `MeshInfo.index_size`) and
  in-place geometry updates that grow or shrink (`mesh_update`).
* **State vocabulary**: HiPGR's own `CULL_*`/`BLEND_*`/`FILTER_*`/`WRAP_*`,
  mapped to the backend in `gpu.goose`.

Acceptance criteria — **all met**:

| # | Criterion | Evidence |
|---|---|---|
| 1 | ≥3 materials (textured, solid, one custom shader) and ≥2 light types in one verified frame | `tests/test_materials.goose` (all three read back; directional + point light set) |
| 2 | Non-uniform scale lit correctly, against an equivalent mesh | `tests/test_normals.goose` (fails if the model matrix is used as the normal matrix) |
| 3 | `MaterialDesc` creates a wireframe and an alpha-blended material | `tests/test_materials.goose` (wireframe covers ≪ the filled cube; blend reads back 128,0,128) |
| 4 | No public API break without a CHANGELOG entry and version bump | `CHANGELOG.md` 0.2.0; `material_solid`/`material_textured` still exist as shorthands |

Deferred from the 0.2 plan, with reasons — this is deliberate, not forgotten:

* **sRGB textures and mip generation** → 0.3. sRGB sampling without sRGB output
  encoding darkens every colour, and both belong with the HDR/tone-mapping
  work; mipmaps are only worth it once minified sampling is measured.
* **Frustum extraction** → 0.4, with the culling it exists to serve.
* **Tangents and normal-map support** → 0.3, with the normal maps that need them.
* **32-bit `mesh_update`** → when a scene needs it; the index slice's own width
  decides how bytes are read, so it would be a second function, not a flag.

## HiPGR 0.3 — Modern rendering ✅ complete (2026-11-10)

Delivered:

* **Deferred frame**: `draw()` records, `end_frame()` renders four passes
  (shadow, scene, bloom, composite). The application-facing API did not change.
* **PBR**: metallic/roughness with GGX/Smith/Schlick direct lighting from the
  directional light and every point light, normal maps from screen-space
  derivatives (no tangent attribute, no extra vertex memory), and emissive.
* **HDR**: the scene into RGBA16F, exposure, and Reinhard or ACES tone mapping
  with gamma. `TONEMAP_NONE` is linear-out for exact-colour work.
* **Shadow map**: one 1024² depth pass from the light, hardware-compared, four
  taps of PCF, constant bias, a configurable world box.
* **Bloom**: half-resolution bright pass plus a separable Gaussian.
* **Sky and fog**: a procedural six-face gradient cube sampled along the view
  ray, and distance fog towards the same horizon colour.
* **Quality profiles**: `QUALITY_MODERN` (the default) and `QUALITY_LINEAR`,
  which is what the 0.1/0.2 tests run under so their exact colours still mean
  something.

Acceptance criteria — **all met**:

| # | Criterion | Evidence |
|---|---|---|
| 1 | A PBR variant of the demo scene | `examples/demo_cube.goose`: metal hero, matte scenery, emissive props, shadows, bloom, sky, fog |
| 2 | Screenshots with a headless render | demo `--frames 30 --shot demo.png`, and every test reads pixels back |
| 3 | Read-back tests for tone mapping | `test_tonemap`: NONE = 128, Reinhard = 155, ACES = 205 for a 0.5 grey, each within 2/255 |
| 4 | Read-back tests for the presence of shadows | `test_shadows`: a probe inside the shadow reads <100 with the ambient floor >20, the same probe reads 255 with shadows off, and moving the light moves the shadow |
| 5 | Read-back tests for bloom, normal maps and the sky | `test_tonemap`, `test_pbr`, `test_environment` |
| 6 | A documented comparison of frame time with and without the effects | `bench_scene` prints `linear` and `modern`; the numbers are in `PROGRESS.md` |
| 7 | No public API break without a note | `CHANGELOG.md` 0.3.0; the 64-byte `Material` block was kept deliberately so 0.2 custom shaders still compile |

Deferred, with reasons:

* **Image-based lighting / environment maps** → 0.4. A prefiltered probe plus an
  irradiance term needs its own pass and its own tests; without it metals read
  dark, which is recorded in `PROGRESS.md` rather than hidden.
* **sRGB texture sampling and mip generation** → 0.4, together with real sRGB
  output encoding. The composite pass applies gamma with a tone curve, which is
  the right encode for a linear scene, but the *inputs* are still sampled as
  plain UNORM and minified without mips.
* **MSAA** → the next milestone that has a GPU to measure it on: it is memory
  the machine may not have, for an artefact nobody has measured here.
* **Cascaded shadow maps** → when a scene needs more than one box. 0.4 made the
  shadow pass the largest remaining per-object cost instead, and instancing it is
  ahead of cascades in the queue.
* **Tangent attribute** → not planned. The derivative frame is correct without
  one, which is cheaper in both memory and vertex work.

## HiPGR 0.4 — Performance, and the light that metals need ✅ complete (2026-11-14)

Delivered (image-based lighting):

* A 16² cosine-weighted irradiance cube and a 32² prefiltered radiance cube with
  five mip levels, integrated on the CPU from the sky's two colours, rebuilt on
  `set_sky`. RGBA16F, so HDR sky reflects as HDR.
* Split-sum specular with Karis' analytic `EnvBRDFApprox`, `textureLod` at
  `roughness * 4`; diffuse from the irradiance cube.
* `set_ibl(dev, strength)`, 0..4; `QUALITY_MODERN` sets 1.0, `QUALITY_LINEAR` 0.0.
  IBL off is 0.2's constant ambient, pixel for pixel.
* Evidence: `tests/test_ibl.goose` (sky colour, irradiance value, roughness
  blur, IBL-off equality), listed in [PROGRESS.md](PROGRESS.md).

Delivered (performance, on by default, `set_culling`/`set_batching` to switch
it off):

* **Frustum culling** from the frame's view-projection, against each mesh's
  local bounds transformed by its model matrix. Never applied to the shadow
  pass: an object off screen can still cast into view.
* **Sorted transparency**: opaque first, transparent back to front by bounding-box
  centre distance. Mixed with batching, opaque draws are grouped by geometry and
  material.
* **Draw batching and instancing**: a run of draws sharing a mesh and a material
  becomes one instanced call, with a per-frame instance buffer and a second
  vertex shader for the built-in material.
* **Counters**: `culled`, `batches`, `instances`, `instanced` in `Stats`.
* **Textures**: sRGB decode on sampling, generated mip chains, and a linear mip
  filter on material samplers.
* Evidence: `test_culling`, `test_batching`, `test_transparency`,
  `test_texture_mips`; numbers in [PROGRESS.md](PROGRESS.md).

Acceptance criteria — **all met**:

| # | Criterion | Evidence |
|---|---|---|
| 1 | A benchmark scene with ≥10k objects, with before/after numbers on the same machine | `bench/bench_10k.goose`: 10,000 cubes, four configurations interleaved on the same frames. 10,000 draw calls → 2 instanced draws with 4,719 objects culled; 389 → 134 ms/frame and 232 → 121 ms/frame in the two recorded trials |
| 2 | Every optimisation has a test that its output matches the unoptimised path | `test_culling` and `test_batching` compare the switch-off and switch-on images with `count_different == 0`; `test_transparency` checks the composited value against the arithmetic one |
| 3 | Culling and instancing cannot be enabled by default until they win on a measured scene | Both are on by default, and `bench_10k` shows them winning on the measured scene; both can be switched off, and the tests do exactly that |

Not done, and why:

* **sRGB output encoding**: the composite writes gamma 1/2.2 where sRGB wants the
  piecewise curve (≤ ~9/255 difference in the darkest two code values). Moving it
  rewrites every tone-curve expectation in the suite; recorded in `PROGRESS.md`
  as a gap rather than done badly.
* **Instancing/culling the shadow pass**, a render graph, profiling counters
  beyond the four above: not justified by the measurement yet.
* **Real-GPU numbers**: still a blocker. This machine has llvmpipe only, so the
  ratios are measured and the absolute times are not meaningful.

## HiPGR 0.5 — External integration

* Instancing and culling in the shadow pass (0.4 measured it as the largest
  per-frame cost at 10k objects), with the same pixel-equality treatment.
* sRGB output encoding, with the tone-curve expectations re-recorded.
* Stable public API draft, versioned, with a compatibility policy.
* Independent demo in a separate repository, consuming HiPGR from git at a tag.
* An integration test program that is not part of this repository.
* Guidance for G3E integration, including the two known gaps (caller-owned
  window, custom material parameters).

Acceptance criteria: an external Goose project builds against a tagged version
without patching HiPGR; the documented API covers everything it used.

## HiPGR 1.0 — Stable library

Stable API, Windows and Linux verified on real GPUs, regression suite,
reproducible builds, release notes and migration notes.

Acceptance criteria: a clean checkout builds and passes the full suite on both
platforms; the API has not broken for one minor cycle; every rendering feature
in the docs has a test that reads back pixels.

---

## Order-of-work rules

* Do not start a milestone before the previous one's criteria pass.
* Never add a performance feature without a benchmark showing it wins.
* Never record a rendering feature as verified without a test that inspects the
  pixels produced.
* Bump [CHANGELOG.md](CHANGELOG.md) and the version in `src/hipgr/hipgr.goose`
  with every user-visible change.
