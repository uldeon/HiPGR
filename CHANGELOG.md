# Changelog

All notable changes to HiPGR are recorded here. The project follows semantic
versioning from 0.5 onward; before that the API is a 0.x draft and may change
between minor versions.

## 0.5.0 — 2026-11-14

The shadow pass now gets the same treatment the scene pass got in 0.4, the
output is encoded as sRGB rather than a plain 2.2 gamma, and the public API is
recorded and gated so a host can depend on it.

### Added — the public contract

- **`docs/api-surface.txt`**: every public declaration in the package, one line
each (270 of them), with the parameter types that make a change visible.
- **`scripts/api_surface.sh`**: extracts the same lines from `src/hipgr` and
  fails when a recorded declaration disappears or changes (breaking), and when
  one appears without being recorded (allowed, but must be written down). It runs
  in `scripts/test.sh`, so a breaking change cannot land unnoticed.
- **`docs/INTEGRATION.md`**: the compatibility policy the gate enforces (what a
  minor and a patch may do, which names are public and which are internal by
  convention, the uniform blocks that count as part of the contract), how to
  embed HiPGR in a host, and the two known gaps — HiPGR creates its own window,
  and materials carry only two `float4`s of application data.
- **`integration/consumer.goose`** and **`scripts/consumer.sh`**: an application
  that lives outside the package and uses only the public API, built and run from
  a clean copy of the tree (tracked files plus untracked non-ignored ones, no
  build artifacts). This is 0.5's acceptance criterion in the one form this
  repository can test: a second remote is not available here, so the consumer
  builds from the tree at this commit rather than from a git tag in another
  repository.

### Added

- **Shadow-pass culling**, tied to `set_culling`: a caster whose world bounds lie
  entirely outside the *light's* box is skipped. The test is the light's own
  view-projection, never the camera's, because an object off screen can still
  cast a shadow into view — `tests/test_shadow_batches` is built around exactly
  that case. Anything the light's box excludes would be clipped by the
  rasteriser anyway, so the skip changes no pixel.
- **Shadow-pass instancing**, tied to `set_batching`: casters are grouped by
  *geometry only* (a depth pass does not care about the material), so a scene
  that shares one mesh draws its whole shadow map in one call. A second
  instance pool holds 64-byte records — the model matrix, no normal — because
  the stride comes from the shader and a depth pass has no use for normals.
- **Counters**: `Stats.shadow_culled`, `shadow_batches`, `shadow_instances`.
- **Benchmark** `bench/bench_shadow.goose`: the same frame with shadows on and
  off, which isolates what the shadow pass costs. Measured against 0.4 at 10,000
  objects (1280×720, llvmpipe, shadow map 1024²): 39.4 ms/frame before, 12.3
  ms/frame after in the best trial, and 41.5 → 20.4 in the matched pair of
  repeat runs — a 2–3× cheaper shadow pass, with the totals therefore 84.1 →
  64.3 and 90.8 → 76.8 ms/frame for the whole frame.
- **Test** `test_shadow_batches`: 50 casters including eight outside the light's
  box and one the camera cannot see; with the optimisations off and on the
  frames are pixel-identical, exactly those eight are skipped, the shadow pass
  drops to one draw per mesh, and turning shadows off changes >400 pixels —
  which is what proves the shadows, including the off-screen caster's, are
  really there.

### Changed

- **sRGB output encoding.** The composite pass now applies the piecewise sRGB
  transfer function (linear below 0.0031308, a 1/2.4 power above it) instead of
  `x^(1/2.2)`. `TONEMAP_NONE` still writes the linear value unchanged, so every
  `QUALITY_LINEAR` colour assertion in the suite is unaffected; the tone-curve
  expectations moved by one code value (Reinhard 155 → 156, ACES 205 → 206),
  and both were recomputed from the curves rather than copied from the output.
- `Stats.batches` and the new shadow counters count **draw calls**, not runs: a
  scene with batching off now reports one batch per object, which is what its
  counters should have said in 0.4.

### Note on the 0.5 roadmap

`ROADMAP.md` asks for an independent demo *in a separate repository*, consuming
HiPGR from git at a tag. That is the one 0.5 item this environment cannot do:
creating a second remote is outside what this repository can authorise. What is
here instead is the same property tested against a clean copy of this tree
(`scripts/consumer.sh`), and a tagged release is a `git tag v0.5.0` away.

## 0.4.0 — 2026-11-14

Image-based lighting, and the performance work a 10k-object benchmark justified:
frustum culling, sorted transparency and instanced draw batching. Texture
sampling gained sRGB decode and generated mips.

### Added

- **Image-based lighting from the sky.** `set_ibl(dev, strength)` (0..4, default
  1.0, `QUALITY_MODERN` sets it, `QUALITY_LINEAR` zeroes it). Two cubes are
  integrated from the same two sky colours on the CPU, when a device opens and
  again on `set_sky`: a 16² cosine-weighted **irradiance** cube (64 samples per
  texel) and a 32² **prefiltered radiance** cube with five mip levels, mip *n*
  holding the sky blurred by roughness *n*/4 via GGX importance sampling. Both
  RGBA16F, so an HDR sky reflects as HDR.
- **Split-sum specular.** The fragment shader samples the prefiltered cube at
  `roughness * 4` and applies Karis' analytic `EnvBRDFApprox` in place of a
  precomputed BRDF lookup texture. Diffuse uses the irradiance cube × albedo ×
  (1 − metallic). Two new samplers (`samplerCube` at set 2 bindings 3 and 4) on
  the built-in shader only; custom shaders are untouched.
- **New module** `src/hipgr/env.goose`: sky radiance as a function (shared with
  the sky cube's rasteriser, so the visible sky and the light it casts cannot
  disagree), cube face directions, the hemisphere and GGX integrals, and a float
  → half encoder for the RGBA16F upload (Goose has no bit cast; the value is
  read back through its bytes, little-endian).
- **Test** `test_ibl`: a mirror metal reflects a blue sky blue and a red sky
  red; the irradiance of a constant 0.8 sky is 0.8 (225/255 through ACES, within
  8), a green sky lights the surface green, and with IBL off an unlit matte
  surface is black; a rough metal gathers the horizon a mirror misses; and IBL
  off reproduces `QUALITY_LINEAR` pixel for pixel.
- **Measured cost**: `demo_cube` at 960×540, 20 frames, three runs each — IBL
  off 44.2 / 46.4 / 47.8 ms per frame, IBL on 49.6 / 51.7 / 56.0, i.e. about
  **+5 ms (+11%)** for two cube taps plus the split-sum math on a CPU
  rasterizer. On hardware this is two cached cube fetches; the number here is a
  software device's, and is quoted as one.

### Added — draw ordering and batching

- **Frustum culling**, on by default, `set_culling(dev, on)` / `culling_enabled`.
  Each mesh records its local axis-aligned bounds when it is created (and again
  on `mesh_update`); the frame's plan transforms those bounds by the model
  matrix and tests the result against the six planes extracted from the frame's
  view-projection. Objects entirely outside are skipped in the scene pass. The
  **shadow pass is never culled**: an object off screen can still cast a shadow
  into view.
- **Sorted transparency**: transparent draws (any material whose blend is not
  `BLEND_NONE`) are drawn after all opaque ones, farthest first by their world
  bounding-box centre. An application no longer has to sort them itself, and
  submission order no longer decides the result. Opaque draws are reordered by
  geometry and material while batching is on — depth testing, not submission
  order, decides their visibility.
- **Draw batching and instancing**, on by default, `set_batching(dev, on)` /
  `batching_enabled`. Consecutive items sharing a mesh and a material become one
  instanced draw: a new `shaders/mesh_instanced.vert` reads the model and normal
  matrices per instance from vertex buffer 1 (locations 3..10, 128 bytes) and a
  per-frame instance buffer is filled once per frame and rewritten whole, so the
  backend can cycle it. Only the built-in shader is instanced; a custom shader's
  vertex layout is its own, so its materials are drawn one item at a time.
- **Counters**: `Stats.culled`, `Stats.batches`, `Stats.instances` (objects
  covered by instanced draws) and `Stats.instanced` (instanced draw calls).
- **Benchmark** `bench/bench_10k.goose`: 10,000 cubes, four configurations timed
  interleaved on the same frames.
- **Textures**: `image_rgba8_srgb` (decoded from sRGB on sampling, full mip
  chain), `image_rgba8_mips` (linear, mips), `image_load_srgb` (a file decoded
  and mipmapped), `image_mip_pixels` (read a level back). Material samplers now
  use a linear mip filter, so a texture with a chain minifies smoothly; a
  texture with one level is unaffected.
- **Tests**: `test_culling`, `test_batching`, `test_transparency`,
  `test_texture_mips` — 19 in total.

### Changed — what the optimisations are allowed to do

- Batching reorders opaque draws; culling removes invisible ones; sorting
  reorders transparent ones. `tests/test_culling` and `tests/test_batching`
  render the same scene with the switch off and on and require **identical
  pixels** (`count_different == 0`); `tests/test_transparency` requires the
  sorted result to be the arithmetically correct one.
- Measured on this container (llvmpipe, 1280×720, 10,000 cubes, shadows and
  bloom on, `bench_10k` 100 20):

  ```
  trial 0: baseline 389.3   culling 177.8   batching 136.1   both 134.3 ms/frame  (2.9x)
  trial 1: baseline 231.5   culling 202.0   batching 124.5   both 120.5 ms/frame  (1.9x)
  ```

  The same scene's draw count goes from 10,000 to 73 batched (culling only) or 2
  instanced draws (batching on), and 4,719 of the 10,000 objects are culled.
  Absolute times on this machine swing by more than 2x between runs because it
  is a CPU rasteriser in a shared container; the *ratio* within a trial is the
  number to read, and it is 1.9x–5.5x across runs. Both switches stay on by
  default because they win on the measured scene, and both can be turned off.
- `bench_scene` (256 cubes) drops to 9.9–10.1 ms/frame linear and 25.0–25.6
  ms/frame modern, from 12–17 and 24–33 before the plan existed.
- Reading a mip level a texture does not have is a backend misuse that aborts at
  the next `gfx` check; `image_mip_pixels` is for a level that exists.

### Not in this release

- **sRGB output encoding.** The composite still applies a 1/2.2 gamma curve
  rather than the piecewise sRGB transfer function, which differs from it by up
  to about 9 of 255 in the darkest two code values and by under 1 above 0.02.
  Inputs (textures) can now be sRGB; the output encode is not.
- **Instancing the shadow pass**, culling against the light's frustum, cascaded
  shadow maps, MSAA, screen-space reflections, and sorting transparent draws by
  triangle rather than by object.

### Changed

- `Frame.params.w` is now the IBL strength instead of "sky on" (it was unused by
  the mesh shader), so no uniform block changed size and 0.2/0.3 custom shaders
  still compile.
- With IBL on, the `ambient` argument of `set_light` is ignored: the sky is the
  ambient term. `set_ibl(dev, 0.0)` restores 0.2's constant ambient exactly.
- The demo was rebalanced for a sky-lit scene: exposure 0.85, a sun at 2.1
  (above the sky, or shadows stop reading as shadows) and a darker floor. Mean
  luma 188.8 → 175.1 and luma standard deviation 24.3 → 32.4 against the
  untuned IBL build; the pre-IBL demo was 164.5 / 45.4.

### Verified

- Linux x64, Vulkan (llvmpipe), headless: 15 tests pass, zero compiler warnings.
- `test_ibl`'s numbers are read back from the rendered pixels, not asserted on
  the CPU: 225 for the constant-sky irradiance, 16/0/227 for a mirror pointing
  at the zenith, 119/0/168 when the same surface is fully rough (the horizon it
  now gathers), 0 with IBL off.

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
