# Changelog

All notable changes to HiPGR are recorded here. The project follows semantic
versioning from 0.5 onward; before that the API is a 0.x draft and may change
between minor versions.

## 0.2.0 — 2026-11-10

Materials become data, and the renderer grows the pieces a real scene needs:
custom shaders, pipeline state per material, point lights, correct normals
under non-uniform scale, and meshes past 65536 vertices.

### Added

- **`MaterialDesc`** and `material_create`: cull mode, blend mode, depth test
  and write, wireframe, sampler filtering and wrapping, tint, image, unlit, and
  two `float4`s of application data (`user0`, `user1`). Invalid state values are
  rejected with `ERR_BAD_ARGUMENT` instead of being mapped to something else.
- **`Shader` handle** and `shader_create(dev, vert, frag)`: an application's own
  embedded shader pair, compiled by the backend when the first material uses it.
  The blocks it must declare are documented in `docs/API.md` and in
  `src/hipgr/material.goose`.
- **Point lights**: `set_point_light(dev, index, position, color, radius)`, up to
  `MAX_POINT_LIGHTS` (8), with smooth falloff to exactly zero at the radius, plus
  `clear_point_lights` and `point_light_count`. The built-in shaders light with
  one directional and all point lights in one block.
- **Normal matrix**: `mat4_normal(m)`, and the draw block now carries it, so a
  non-uniformly scaled mesh shades correctly. The vertex shader passes world
  position for point lights.
- **32-bit indices**: `mesh_create32` for meshes past 65536 vertices, with the
  width recorded in `MeshInfo.index_size` and used at draw time.
- **Geometry updates**: `mesh_update(dev, mesh, vertices, indices)` replaces a
  mesh's geometry in place, growing or shrinking; buffers are reused when the
  new data fits, and rebuilt (old ones kept until the new ones exist) when it
  does not.
- **Pipeline and sampler caches**: materials with identical state share one
  pipeline and one sampler, counted by `Stats.pipelines` and `Stats.samplers`.
- **`state.goose`**: HiPGR's own `CULL_*`, `BLEND_*`, `FILTER_*` and `WRAP_*`
  values, mapped to the backend inside `gpu.goose` so the API does not depend on
  the backend's numbering.
- **Tests**: `test_materials` (three materials and two light kinds in one frame,
  wireframe, alpha blending, culling, pipeline sharing, rejected state),
  `test_normals` (a stretched mesh against an equivalent baked one),
  `test_lights` (falloff, radius, multiple lights), `test_big_mesh` (66049
  vertices, growth, shrink, refused updates).
- **Demo**: striped custom-shader cubes, a circling point light, and a
  translucent shell around the subject.

### Changed

- The draw uniform block is now 128 bytes (`model` and `normal`), the material
  block 64 (`tint`, `params`, `user0`, `user1`) and the light block 288
  (`direction`, `color`, 16 light vec4s). Custom shaders must match; this is why
  the block sizes are a documented contract from 0.2 on.
- Built-in shader pairs are created on first use and addressed like any other
  shader, instead of being two device fields.
- `MaterialRec` no longer stores a material kind: whether a material samples a
  texture follows from whether it names an image.

### Verified

- Linux x64, Vulkan (llvmpipe), headless: 10 tests pass, zero compiler
  warnings across every root program.
- The normal-matrix test was checked against a deliberate regression (the model
  matrix used as the normal matrix): it fails, so the test has teeth.
- 256- and 1024-cube benchmarks: 7.53 ms/frame at 256 cubes (unchanged from
  0.1 within noise) and 24.95 ms/frame at 1024 cubes, 1280x720, software device.

### Not in this release

- sRGB textures, mip generation, tangents, frustum extraction and 32-bit
  `mesh_update` were on the 0.2 plan and are deferred to 0.3/0.4; see
  `ROADMAP.md` for the reasons.

## 0.1.0 — 2026-11-10

The first release: a verified GPU foundation on Goose's `gfx` module.

### Added

- **Device**: `open`, `open_headless`, `close`, frame lifecycle
  (`begin_frame` / `draw` / `end_frame`), screen and depth buffer, stats,
  error codes with text, backend error reporting, backend driver name.
- **Resources**: generation-checked handles (`Mesh`, `Image`, `Material`),
  immediate `release`, device-owned sweep on `close`, validation of handles,
  geometry and frame state before anything reaches the backend.
- **Meshes**: packed 32-byte `Vertex`, `mesh_create` with index validation,
  built-in triangle, quad and cube.
- **Images**: RGBA8 upload from bytes, procedural checkerboard, PNG/BMP load.
- **Materials**: solid (tint) and textured (albedo × tint) built-in materials
  with shared cached pipelines, lit or unlit, one directional light with
  ambient via `set_light`.
- **Camera**: `Camera` with perspective, orthographic and first-person
  constructors, view / projection / view-projection matrices.
- **Math**: `Mat4` (std140 layout) with mul, TRS, spin, look-at, projections and
  point transforms.
- **Backend boundary**: `src/hipgr/gpu.goose`, the only module that issues
  `gfx` calls; the public API names no `gfx` type.
- **Platform facade**: keys, mouse delta/position, capture, clock, quit.
- **Demo**: `examples/demo_cube.goose` — free camera, 49 tiled cubes and a
  spinning hero cube, `--frames` and `--shot`.
- **Examples/tests/bench**: `examples/triangle.goose`, six tests that read back
  pixels (triangle, textured cube + rotation, depth ordering, lifetime and
  misuse, camera math, 256-object frames), `bench/bench_scene.goose`.
- **Tooling**: `scripts/test.sh` (with SKIP reporting and an API-isolation
  guard), `scripts/bench.sh`.
- **Documentation**: `README.md`, `RECONNAISSANCE.md`, `ARCHITECTURE.md`,
  `ROADMAP.md`, `PROGRESS.md`, `AGENT_RULES.md`, `docs/API.md`,
  `docs/goose-notes.md`.

### Verified

- Linux x64, Vulkan (Mesa llvmpipe software device), headless: all six tests
  pass.
- 256 cubes (3072 triangles), textured and lit, 1280×720: 7.54 ms/frame on that
  software device — a regression baseline, not a hardware claim.

### Known limitations

- Windows and Direct3D 12/Metal are untested.
- Windowed mode was not observed in the development container (no display).
- Lighting has no numerical test; custom shaders, point lights, mipmaps, sRGB,
  PBR, shadows, HDR and post-processing do not exist yet.
- Resource records are append-only; slots are not recycled.
- glTF/GLB, KTX2 and HDR importers do not exist.
