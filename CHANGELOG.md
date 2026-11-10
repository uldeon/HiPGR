# Changelog

All notable changes to HiPGR are recorded here. The project follows semantic
versioning from 0.5 onward; before that the API is a 0.x draft and may change
between minor versions.

## 0.3.0 — 2026-11-10

Modern rendering: the scene pass now writes HDR into an off-screen target and a
post chain turns it into a finished image, and shading is metallic/roughness
PBR with normals from a normal map, one shadow map, a procedural sky and fog.

### Added

- **Deferred draw submission.** `draw()` records a `DrawItem`; `end_frame()`
  renders the frame as four passes: shadow, scene, bloom, composite. The API
  call sequence is unchanged, and a frame's whole contents are known before the
  shadow pass starts — which is also where 0.4's sorting and culling will live.
- **HDR target + tone mapping.** The scene renders into RGBA16F with its own
  depth buffer; `set_exposure`, `set_tonemap` with `TONEMAP_NONE` /
  `TONEMAP_REINHARD` / `TONEMAP_ACES`. Gamma is applied with a tone curve and
  only with one, so `TONEMAP_NONE` is the linear value the scene pass wrote.
- **Bloom.** `set_bloom(dev, strength, threshold)`: a half-resolution bright
  pass above a linear threshold, then a separable 5-tap Gaussian (horizontal,
  vertical). Strength 0 skips the passes entirely.
- **Shadows.** `set_shadows`, `set_shadow_area(center, radius)`: one 1024²
  depth map rendered from the light, read back with a hardware-compare
  `sampler2DShadow` and a four-tap PCF kernel plus a constant depth bias.
- **PBR materials.** `MaterialDesc` gains `metallic`, `roughness`,
  `normal_map`, `normal_strength` and `emissive`. The built-in shader is Lambert
  + GGX/Smith/Schlick direct lighting from the directional and every point light,
  with an ambient term. One shader pair now serves solid and textured materials:
  a material with no image samples a 1×1 white texel, one with no normal map
  reports strength 0 so the tangent frame and the extra tap are skipped.
- **Normal maps** without a tangent vertex attribute: the tangent frame comes
  from screen-space derivatives of position and UV, with the sign of the
  Jacobian determinant kept, which is what aligns the map with the surface
  instead of rotating it by 180°.
- **Procedural sky and fog.** `set_sky(horizon, zenith)` builds a 64² six-face
  gradient cube from two linear colours, drawn as a full-screen triangle along
  the view ray; `set_fog(density)` fades towards the horizon colour with
  distance. `set_sky_enabled` turns the sky off without touching the fog colour.
- **Quality profiles.** `quality(dev, QUALITY_MODERN)` (the default: ACES, bloom
  0.35, shadows, sky, fog) and `quality(dev, QUALITY_LINEAR)` (no tone mapping,
  bloom, shadows, sky or fog: 0.2's output exactly, which is what the 0.1/0.2
  regression tests now run under).
- **Uniform blocks** in `uniforms.goose`, shared by every pass: `Frame` (224),
  `Draw` (128), `Material` (64), `Light` (288), `Surface` (16), `Post` (32).
- **Shaders**: `mesh.frag` (PBR), `shadow.vert`, `empty.frag`, `fullscreen.vert`,
  `sky.frag`, `bright.frag`, `blur.frag`, `composite.frag`.
- **Tests**: `test_tonemap` (the three curves to 2/255, exposure, bloom and its
  threshold), `test_pbr` (metal loses its diffuse lobe, polish vs roughness,
  normal map turns a surface towards the light, strength 0 equals no map),
  `test_shadows` (shadow present, ambient kept, absent outside the box, moves
  when the light moves), `test_environment` (sky gradient, sky off, fog tint).
- **Benchmark**: `bench_scene` reports `linear` and `modern` frame times for the
  same scene, so the cost of the post pipeline is measured, not guessed.

### Changed

- The `Frame` block grew from 64 to 224 bytes (light matrix, camera position,
  sky/fog, shadow parameters, camera basis). Custom shaders that declare it must
  match; the *fragment* `Material` block stayed at 64 bytes on purpose, by
  moving `emissive` into its own 16-byte `Surface` block, so 0.2's shaders are
  untouched.
- `roughness` defaults to 1.0 (fully rough) so a plain coloured surface shades
  like matte paint; only a material that asks for a highlight gets one.
- Light colours are intensities: a white surface facing a full-strength light
  renders at 1.0, so the 4% Fresnel reflectance a dielectric gives up is what
  makes it 0.96 rather than 1.0.
- The demo is now a modern scene: a rotating gold metal hero over a shadowed
  grid, three emissive cubes that bloom, a sky, fog, a custom-shader row and a
  glass shell.

### Verified

- Linux x64, Vulkan (llvmpipe), headless: 14 tests pass, zero compiler warnings
  across every root program and every example/benchmark build.
- The 0.1/0.2 tests still assert their exact colours (26,102,230; 128,0,128;
  40,40,60; 220,200,120) under `QUALITY_LINEAR`, so the post chain provably does
  not disturb the linear path.
- Shadow and normal-map behaviour were each checked against the wrong version:
  a caster pushed towards the light shadows the whole scene, and dropping the
  Jacobian sign in the tangent frame turns the mapped surface away from the
  light. Both failures were observed, then fixed.
- 256 cubes, 1280×720, software device: 13.6 ms/frame (`linear`) and
  29.1 ms/frame (`modern`). Demo at 960×540: ~40 ms/frame. Software numbers; the
  ratio is the only part worth quoting.

### Not in this release

- Image-based lighting, environment maps and reflections: metals therefore
  reflect nothing and read dark. Planned for 0.4 with a prefiltered probe.
- MSAA, cascaded shadow maps, sorted transparency, sRGB texture sampling and
  mip generation. The first three are 0.4; sRGB sampling belongs with sRGB
  output encoding, which the gamma in the composite pass approximates but does
  not replace.
- Windows and real-GPU verification: still no hardware here.

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
