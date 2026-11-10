# HiPGR — Roadmap

Milestones are gates, not schedules. A milestone is done when its **acceptance
criteria** pass in this repository — compiled, executed, and where it involves
pixels, checked by reading them back. [PROGRESS.md](PROGRESS.md) is the current
status; this file is the plan.

**Status: 0.1 and 0.2 complete (2026-11-10). 0.3 not started.**

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

## HiPGR 0.3 — Modern rendering

* PBR (metallic/roughness), normal maps (with tangents), emissive.
* HDR render target, tone mapping, sRGB output encoding, then sRGB textures and
  mip generation (deferred from 0.2; the two go together).
* Shadow maps with a shadow pass and bias controls.
* Skybox / environment lighting (cubemap first, irradiance later).
* Post-processing chain (bloom, then anti-aliasing).
* Fog.

Acceptance criteria: a PBR variant of the demo scene; screenshots with a
headless render; read-back tests for tone mapping and shadow presence; a
documented comparison of frame time with and without each effect.

## HiPGR 0.4 — Performance

Only what measurement justifies.

* Frustum culling (including frustum extraction) and sorted transparency;
  instancing; draw batching by material; resource caching; a render graph if
  pass setup has become error-prone; profiling counters.

Acceptance criteria:

1. A benchmark scene with ≥10k objects, with before/after numbers on the same
   machine.
2. Every optimisation has a test that its output matches the unoptimised path
   (same pixels, or a stated tolerance).
3. Culling and instancing cannot be enabled by default until they win on a
   measured scene.

**Blocker:** the development machine has no hardware GPU, so 0.4 needs a real
GPU before any decision here can be honest.

## HiPGR 0.5 — External integration

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
