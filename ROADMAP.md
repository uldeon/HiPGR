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
* **MSAA** → 0.6, done: it turned out measurable on the software renderer
  without a GPU (cost ratio within a run), and the artefact is visible to anyone
  who looks at an edge.
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

## HiPGR 0.5 — External integration ✅ complete (2026-11-14), one item re-scoped

Delivered:

* **Shadow-pass culling and instancing** (0.4 measured that pass as the largest
  per-frame cost at 10k objects), with the same pixel-equality treatment, and
  `bench/bench_shadow` to measure it: 39.4 → 12.3 ms/frame at 10,000 objects.
* **sRGB output encoding**, with the tone-curve expectations re-recorded from
  the curve (Reinhard 156, ACES 206).
* Evidence: `tests/test_shadow_batches`, `tests/test_tonemap`; numbers in
  [PROGRESS.md](PROGRESS.md).

Also delivered:

* **A recorded, gated public API** — `docs/api-surface.txt` (277 declarations as of 0.6)
  and `scripts/api_surface.sh`, which fails on a removed or changed declaration
  and on an unrecorded addition; it runs in `scripts/test.sh`.
* **A compatibility policy** — `docs/INTEGRATION.md`: what a minor and a patch
  may do, which names are public and which are internal by convention, the
  uniform blocks that count as part of the contract.
* **An out-of-package consumer** — `integration/consumer.goose`, built and run
  from a clean copy of the tree by `scripts/consumer.sh`, using only the public
  API and no backend import.
* **Host guidance** — embedding, lifetime, threading and ordering in
  `docs/INTEGRATION.md`, including the two gaps a host will hit: HiPGR creates
  its own window, and materials carry two `float4`s of application data.
* Guidance for G3E integration, including the two known gaps at the time
  (caller-owned window, custom material parameters — both addressed since: the
  parameters in 0.6, the textures and shadows in 0.7).

Acceptance, as met: an application outside the package builds against HiPGR at
this commit without patching it — `scripts/consumer.sh`, from a clean copy — and
the documented API covers everything it used, because the surface is recorded
and the consumer is compiled against it.

**Dropped at the user's direction:** "an independent demo in a separate
repository". It needs a second remote, and it tests nothing the clean-copy
consumer does not already test — that a program outside the package builds
against it without patching. It is not part of the plan any more.

## HiPGR 0.6 — Antialiasing, and application data ✅ complete (2026-11-14)

Scope, chosen as the two quality gaps left after 0.5: an edge was a staircase,
and a custom shader had two `float4`s of its own data and nothing else.

Delivered:

* **4× multisampling** (`set_msaa`) — the scene pass resolves into the HDR
  target, so the shadow map, the post chain and every pixel test are unchanged.
  `tests/test_msaa`: 0 partial pixels on a slanted edge without it, 128 with it,
  an identical flat interior, and an exact return to the plain frame when turned
  off. Cost measured on this machine: 25.4–26.6 → 48.7–59.9 ms/frame at 300
  cubes, so 1.9–2.4×, which is why it is off by default.
* **`Material.v[8]`** — eight `float4`s per material, `set_material_param` /
  `material_param`, read by a custom shader with exact-pixel tests. This closes
  the "custom material parameters" gap 0.5 documented.
* **A breaking change, priced as one:** the `Material` block grew from 64 to 192
  bytes, so 0.6 is a minor version with a migration note, and the API gate caught
  it before it could be committed unnoticed.

Deferred with a reason, not forgotten: 2× and 8× multisampling, refused because
this backend cannot report sample-count support and both resolved to a black
frame here; cascaded shadow maps, still "when a scene needs more than one box"; a
caller-owned window, still untestable without a display.

## HiPGR 0.7 — Custom materials, first class ✅ complete (2026-11-14)

Scope, chosen as the last thing a host's own material system could not do: a
custom shader could not sample a texture and could not receive a shadow.

Delivered:

* **Textures** — `MaterialDesc.texture_count` (0..4) plus
  `set_material_texture`, bound at the shader's own sampler slots; an unset slot
  is a white texel. `tests/test_custom_textures` checks both slots, the swap and
  the default at exact pixel values.
* **Shadows** — `MaterialDesc.use_shadow_map` binds the scene's shadow map after
  the material's textures, with the matrix and bias in `Frame`.
  `tests/test_custom_shadows` renders a floor that turns black exactly where the
  caster's shadow falls, and follows the light when it moves.
* No breaking change this time: the surface grew by two functions and a constant,
  and the API gate reported the additions rather than blocking them.

Still deferred: a caller-owned window (no display here to test one), cascaded
shadow maps (when a scene needs more than one box), and a custom vertex layout
(HiPGR's `Vertex` is fixed at 32 bytes, so a host repacks).

## HiPGR 0.8 — Shadows that follow the camera ✅ complete (2026-11-14)

Scope, chosen as the last rendering gap with real reach to it: one shadow box
around a fixed centre means a scene that moves away from that centre loses its
shadows.

Delivered:

* **Two camera-following cascades** — `set_shadow_cascades(near, far)`, with
  `set_shadow_area` keeping single-box mode as the default so nothing that was
  shadowed before changed. Casters are culled per cascade, so the second pass
  only draws what belongs to it.
* `tests/test_cascades` measures all of it in pixels: same shadow inside the box
  (82 vs 82), the single box loses it when the camera moves (0) and the cascades
  keep it (82), a far-only caster still casts, and the shadow pass is 4 draws per
  frame against 2.
* **A breaking change, priced as one:** `Frame` grew 224 → 304 bytes for the far
  matrix and the cascade parameters. Three test shaders and the sky failed
  loudly until updated, which is the contract working.

Deferred with a reason: a fade across the cascade boundary (the switch is hard,
and no test here could tell a fade from the correct pixels), a caller-owned
window (needs a display), and point-light shadow maps.

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
