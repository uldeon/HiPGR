# Changelog

All notable changes to HiPGR are recorded here. The project follows semantic
versioning from 0.5 onward; before that the API is a 0.x draft and may change
between minor versions.

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
