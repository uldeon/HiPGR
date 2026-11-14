# HiPGR — Public API (0.4.0)

Everything lives in namespace `hipgr`. Import the package and nothing else:

```goose
import hipgr from "../src/hipgr";
```

No `gfx` type appears in this API. Handles are opaque:

```goose
struct Mesh { id: u32 }
struct Image { id: u32 }
struct Material { id: u32 }
struct Shader { id: u32 }
```

`id == 0` is never valid. Any function that takes a handle fails with
`ERR_BAD_HANDLE` if it is zero, released, or from another resource kind.

**Calling convention.** Functions that can fail return `bool` (or a zero
handle) and record a code on the device. They never abort the application.

---

## Device

```goose
root struct Device { … }        // var dev = hipgr::Device { .. };
```

A device owns every GPU object created through it. It is a Goose *root struct*,
so it cannot be copied, passed by value, or returned — always pass `Device&`.

| Function | Purpose |
|---|---|
| `open(dev, title, width, height) -> bool` | windowed device; the window is created by the backend |
| `open_headless(dev, width, height) -> bool` | no window; same rendering and read-back |
| `close(dev)` | release everything still live, then close the backend; idempotent |
| `is_open(dev) -> bool` | |
| `screen_size(dev) -> int2` | pixels, current for this frame |
| `driver(dev) -> u8[>..]` | `"vulkan"`, `"direct3d12"` or `"metal"` |
| `stats(dev) -> Stats` | counters, see below |
| `error_code(dev) -> i32` | last error code |
| `ok(dev) -> bool` | `error_code(dev) == ERR_NONE` |
| `clear_error(dev)` | reset the code to `ERR_NONE` |
| `error_text(code) -> u8[:]` | human-readable text for a code |
| `backend_error() -> u8[>..]` | the graphics backend's own last message |
| `version() -> u8[:]` | HiPGR version |

```goose
struct Stats {
    frames: i64, draws: i64, triangles: i64,
    meshes: i64, images: i64, materials: i64, shaders: i64,
    pipelines: i64, samplers: i64,
}
```

`meshes`/`images`/`materials`/`shaders` are live counts. `pipelines` and
`samplers` are cache sizes: materials that ask for the same state share one, so
these can be far smaller than the material count. `frames`, `draws` and
`triangles` accumulate for the device's lifetime.

### Error codes

| Code | Meaning |
|---|---|
| `ERR_NONE` | ok |
| `ERR_NO_DEVICE` | no GPU device could be opened |
| `ERR_NOT_OPEN` | the device is not open |
| `ERR_ALREADY_OPEN` | the device is already open |
| `ERR_NO_FRAME` | no frame open: `begin_frame` first |
| `ERR_FRAME_OPEN` | a frame is already open |
| `ERR_BAD_HANDLE` | invalid or released handle |
| `ERR_BAD_ARGUMENT` | invalid argument, state value or geometry |
| `ERR_GPU` | the backend rejected the call |
| `ERR_TOO_MANY` | handle index space exhausted |

Intentional misuse does **not** reach the backend: a rejected draw is skipped
and reported, and the frame can still be ended.

---

## Meshes

```goose
struct Vertex { pos: float3, normal: float3, uv: float2 }   // 32 bytes, packed
```

| Function | Purpose |
|---|---|
| `mesh_create(dev, vertices, indices: const u16[:]) -> Mesh` | upload, indexed with 16 bits: at most 65536 vertices |
| `mesh_create32(dev, vertices, indices: const u32[:]) -> Mesh` | the same, indexed with 32 bits, for large meshes |
| `mesh_update(dev, mesh, vertices, indices: const u16[:]) -> bool` | replace a 16-bit mesh's geometry; the count may grow or shrink |
| `mesh_triangle(dev) -> Mesh` | one triangle facing +Z |
| `mesh_quad(dev) -> Mesh` | unit quad in XY, facing +Z |
| `mesh_cube(dev) -> Mesh` | unit cube, 24 vertices, 12 triangles, per-face normals and full-face UVs |
| `mesh_info(dev, mesh) -> MeshInfo` | `vertices`, `indices`, `triangles`, `vertex_bytes`, `index_bytes`, `index_size` |
| `release(dev, mesh)` | free the GPU buffers now |
| `vertex_bytes() -> i64` | 32 |

`mesh_info(...).index_size` is 2 or 4: the width chosen when the mesh was
created. Both are drawn without the application doing anything.

`mesh_update` keeps the handle valid for the life of the mesh. It reuses the
existing buffers when the new geometry fits (the usual case for animation) and
builds replacements before releasing the old ones when it does not, so a failed
allocation leaves the mesh as it was. Only 16-bit-indexed meshes can be updated
this way: the width of the index slice decides how its bytes are read, so a
32-bit mesh is left to `mesh_create32`.

Every index is checked against the vertex count before upload
(`ERR_BAD_ARGUMENT`), as are empty meshes and index counts that are not a
multiple of three. `mesh_create` copies the data into GPU buffers, so the
CPU-side arrays may go out of scope immediately.

---

## Images

An image is an RGBA8 sampled 2D texture, row 0 first.

| Function | Purpose |
|---|---|
| `image_rgba8(dev, width, height, pixels: const u8[:]) -> Image` | upload tightly packed RGBA8 |
| `image_checker(dev, size, cell, ca: u8[4], cb: u8[4]) -> Image` | deterministic two-colour checkerboard |
| `image_load(dev, path: const u8[:]) -> Image` | PNG or BMP through the backend |
| `image_rgba8_srgb(dev, width, height, pixels) -> Image` | the same, **decoded from sRGB** on sampling, with a full mip chain |
| `image_rgba8_mips(dev, width, height, pixels) -> Image` | linear colour, with a full mip chain |
| `image_load_srgb(dev, path) -> Image` | a file decoded as sRGB, with a mip chain |
| `image_mip_pixels(dev, image, mip, out: u8[:]) -> bool` | read one mip level back, for tests |
| `image_info(dev, image) -> ImageInfo` | `width`, `height` |
| `release(dev, image)` | free the texture now |

A material refers to its image **by handle**, so releasing an image that a
material still uses is detected at draw time (`ERR_BAD_HANDLE`), not by reading
freed GPU memory.

**sRGB or linear.** Every colour a shader computes with should be linear light.
An image authored in an editor is in sRGB, so its 128 grey is 0.216 of the light
that a 0.5 grey value means. `image_rgba8_srgb` and `image_load_srgb` let the GPU
do the decode on sampling, which is the right choice for an albedo map; plain
`image_rgba8` keeps the stored values, which is what a mask, a normal map or any
other data texture wants. Stored values are what `frame_pixels` and
`image_mip_pixels` return, so an sRGB test reads 55 for a 128 grey.

**Mips.** A texture with a chain minifies cleanly: the sampler reads a coarser
level instead of four texels of the finest one, which is what stops a
checkerboard on a distant wall from shimmering. The chain is generated by the
backend from level 0 (`generate_mips`), so it costs one command per texture at
load time and nothing per frame. Material samplers always use a linear mip
filter; a texture with a single level has nothing to interpolate.

What 0.4 does *not* do: re-encode the **output** as sRGB. The composite applies
`x^(1/2.2)`, which agrees with the sRGB transfer function above 0.02 and differs
by up to about 9 of 255 in the darkest two code values.

Reading a level a texture does not have is a backend misuse: `image_mip_pixels`
aborts at the next `gfx` check rather than returning false.

---

## Shaders

A shader is a vertex + fragment pair compiled for every backend at build time
from source embedded in the program:

```goose
let vs = embed_shader("shaders/mine.vert");
let fs = embed_shader("shaders/mine.frag");
let sh = hipgr::shader_create(dev, vs, fs);
```

| Function | Purpose |
|---|---|
| `shader_create(dev, vert: const u8[:], frag: const u8[:]) -> Shader` | register a pair; empty source is refused |
| `release(dev, shader)` | forget the pair; pipelines already built from it stay valid |

Nothing is compiled by `shader_create`: the backend compiles the pair when the
first material that uses it is created. A broken shader therefore fails
`material_create` (or the first draw) with `ERR_GPU` and the backend's message.

### The shader contract

A custom shader must read HiPGR's vertex layout and may use HiPGR's blocks.
These are a compatibility promise from 0.2 on.

```
vertex inputs        location 0 vec3 position, 1 vec3 normal, 2 vec2 uv
vertex, set 1 b0     Frame    { mat4 view_proj; mat4 light_view_proj;
                               vec4 camera_pos; vec4 sky; vec4 params;
                               vec4 cam_right; vec4 cam_up; vec4 cam_forward; }
vertex, set 1 b1     Draw     { mat4 model; mat4 normal; }
fragment, set 3 b0   Material { vec4 tint; vec4 params; vec4 user0; vec4 user1; }
fragment, set 3 b1   Light    { vec4 direction; vec4 color; vec4 points[16]; }
```

Sizes must match exactly: `Frame` is 224 bytes, `Draw` 128, `Material` 64,
`Light` 288. The material block is 64 bytes on purpose, so 0.2's custom shaders
keep working unchanged.

* `normal` is the inverse transpose of `model`'s upper 3×3, so normals survive a
  non-uniform scale.
* `params.x` is 1 when the material is unlit, `y` metallic, `z` roughness, `w`
  normal-map strength (0 when the material has no normal map).
* `user0` and `user1` are the material's own data, untouched by HiPGR.
* `direction.xyz` is the direction the directional light travels in; `w` is
  ambient. `color.rgb` is its colour; `w` is the point light count.
* `points` holds, per light, `(position, radius)` then `(colour, 0)`.
* `camera_pos.xyz` is the eye; `sky.rgb` the sky/fog colour and `sky.w` the fog
  density; `params.x` shadows on, `params.y` one shadow-map texel,
  `params.z` shadow bias. `cam_right`/`cam_up`/`cam_forward` are the camera basis
  scaled for a ray through an NDC point.

HiPGR binds **no** textures for a custom shader: the three sampler slots of the
built-in shader (`u_albedo`, `u_normal_map`, `u_shadow` at set 2 bindings 0, 1,
2) belong to it alone. A custom shader that wants a texture uploads it through
its own bindings (not exposed by 0.3) or computes its colour, as the demo's
`stripes.frag` does.

---

## Materials

A material is the shading state for a mesh: a shader pair, pipeline state, a
tint, application data, and optionally an image.

```goose
struct MaterialDesc {
    shader: Shader = Shader { 0 },   // 0: the built-in PBR pair
    image: Image = Image { 0 },      // albedo texture; 0: tint only
    normal_map: Image = Image { 0 }, // tangent-space normal map; 0: flat
    tint: float4 = float4 { 1.0, 1.0, 1.0, 1.0 },
    user0: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    user1: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    emissive: float3 = float3 { 0.0, 0.0, 0.0 },   // emitted, independent of light
    unlit: bool = false,
    metallic: f32 = 0.0,             // 0 dielectric, 1 metal
    roughness: f32 = 1.0,            // 0 mirror, 1 fully rough
    normal_strength: f32 = 1.0,      // 0 ignores the normal map
    cull: i32 = CULL_BACK,
    blend: i32 = BLEND_NONE,
    depth_test: bool = true,
    depth_write: bool = true,
    wireframe: bool = false,
    filter: i32 = FILTER_LINEAR,
    wrap: i32 = WRAP_CLAMP,
}
```

| Function | Purpose |
|---|---|
| `material_create(dev, desc: MaterialDesc) -> Material` | any state above |
| `material_solid(dev, tint, unlit) -> Material` | shorthand: a matte colour, no texture |
| `material_textured(dev, image, tint, unlit) -> Material` | shorthand: an albedo texture, matte |
| `release(dev, material)` | free the material record; the shared pipeline and sampler stay with the device |

One built-in pair shades every material that does not name a shader. A material
with no `image` samples a 1×1 white texel and one with no `normal_map` samples a
flat normal, which a material without one does not pay for: HiPGR tells the
shader the strength is 0, so the tangent frame and the extra tap are skipped.

`roughness` defaults to 1 (fully rough) rather than to a mirror-like value: a
plain coloured surface then shades like matte paint, and only a material that
asks for a highlight gets one. `metallic`, `roughness` and `normal_strength`
outside 0..1, 0..1 and 0..4 are refused with `ERR_BAD_ARGUMENT`.

State values (HiPGR's own, independent of the backend):

| Constant | Values |
|---|---|
| `CULL_NONE`, `CULL_BACK`, `CULL_FRONT` | which faces to drop |
| `BLEND_NONE`, `BLEND_ALPHA`, `BLEND_ADD` | how a fragment combines with the target |
| `FILTER_NEAREST`, `FILTER_LINEAR` | texture magnification/minification |
| `WRAP_CLAMP`, `WRAP_REPEAT` | UVs outside 0..1 |

An unknown value is refused with `ERR_BAD_ARGUMENT` rather than silently
becoming the default. Materials with identical state share one pipeline and one
sampler; changing any state value makes a new one.

Two transparent-material notes: use `depth_write: false` unless you want the
transparent object to hide what is behind it, and draw transparent objects after
opaque ones — HiPGR does not sort draws yet (0.4).

---

## Lights

| Function | Purpose |
|---|---|
| `set_light(dev, direction, color, ambient) -> bool` | the directional light: `direction` is where it travels, `ambient` in 0..1 |
| `set_point_light(dev, index, position, color, radius) -> bool` | one point light slot, 0 .. `MAX_POINT_LIGHTS`-1 |
| `clear_point_lights(dev)` | remove all point lights |
| `point_light_count(dev) -> i64` | how many are set |
| `MAX_POINT_LIGHTS` | 8 |

Point light falloff is `((1 - d²/r²)⁺)²`: smooth, and exactly zero at `radius`,
so geometry a light cannot reach is untouched by it and the shader cost stays
bounded. Slots can be updated in place every frame; the lights are pushed once
per frame, not per draw.

Built-in lighting is metallic/roughness PBR: a Lambertian diffuse term plus a
GGX/Smith/Schlick specular lobe, direct from the directional light and every
point light, plus **image-based lighting from the sky** (see
[Image-based lighting](#image-based-lighting)). With IBL on, the sky is the
ambient term and the `ambient` argument to `set_light` is ignored — it only
applies with `set_ibl(dev, 0.0)`, which is 0.2's constant ambient.

Light colours are intensities, not radiances: a white surface facing a
full-strength white light renders at 1.0 (the surfaced PI in the BRDF is undone
once, in the shader), so a colour picked in an editor means what it looks like.
The 4% Fresnel reflectance of a dielectric is subtracted from the diffuse term,
which is why that surface is 0.96 rather than 1.0.

---

## Camera

```goose
struct Camera {
    eye: float3, target: float3, up: float3,
    fov_y: f32, near: f32, far: f32,
    orthographic: bool, ortho_height: f32,
}
```

| Function | Purpose |
|---|---|
| `camera_look_at(eye, target, up, fov_y) -> Camera` | perspective camera |
| `camera_perspective(eye, target, up, fov_y, near, far) -> Camera` | with explicit depth range |
| `camera_orthographic(eye, target, up, height, near, far) -> Camera` | orthographic, `height` in world units |
| `camera_fps(eye, yaw, pitch, fov_y) -> Camera` | first-person from angles |
| `camera_direction(yaw, pitch) -> float3` | yaw 0 looks down -Z; +yaw turns right; +pitch looks up |
| `camera_view(c) -> Mat4` | view matrix |
| `camera_projection(c, aspect) -> Mat4` | projection |
| `camera_view_projection(c, aspect) -> Mat4` | projection × view |

The camera is plain data that the application owns and moves. HiPGR only reads
it when a frame begins.

---

## Matrices

`Mat4` is a column-major 4×4 matrix in std140 layout. It is the type uniforms
and shaders use.

| Function | Purpose |
|---|---|
| `mat4_identity()` | |
| `mat4_mul(a, b)` | `a * b` |
| `mat4_mul_vec4(m, v) -> float4` | matrix × vector |
| `mat4_point(m, p: float3) -> float3` | point through a matrix, no perspective divide |
| `mat4_translate(t)` / `mat4_scale(s)` / `mat4_rotate(axis, angle)` | single transforms |
| `mat4_trs(t, axis, angle, s)` | translate × rotate × scale |
| `mat4_spin(center, yaw, scale)` | rotate about Y and place — the common demo transform |
| `mat4_normal(m)` | the inverse transpose of the upper 3×3: for normals |
| `mat4_look_at`, `mat4_perspective`, `mat4_ortho` | projection helpers |
| `mat4_column(m, i) -> float4` | column `i`, for diagnostics and tests |

`draw` computes `mat4_normal(model)` itself, so an application only needs the
function when it is doing its own lighting on the CPU.

---

## Rendering

```goose
fn begin_frame(dev, camera: Camera, clear: float4) -> bool
fn draw(dev, mesh: Mesh, material: Material, model: Mat4) -> bool
fn end_frame(dev) -> bool
```

* `begin_frame` validates state, sizes the render targets to the screen, and
  starts recording. Nothing is drawn yet.
* `draw` validates the mesh, the material and its images, and records the draw.
  It updates `Stats` and sorts nothing; the order is decided by `end_frame`.
* `end_frame` renders the recorded frame and presents it. It returns **false
  when the program should quit** (window closed, `quit()` called); true means
  continue.

A frame is four passes, in this order:

| Pass | Target | What it does |
|---|---|---|
| shadow | 1024² depth map | every recorded mesh, from the light's point of view, with the depth-only pipeline |
| scene | RGBA16F + depth | the sky, then every recorded mesh with its material |
| bloom | two half-resolution RGBA16F targets | a bright pass above the threshold, then a horizontal and a vertical 5-tap blur |
| composite | screen | bloom added, exposure, tone curve, gamma |

Because recording is separate from rendering, a frame's whole contents are known
before the shadow pass starts, which is what lets culling, sorting and batching
happen without changing this API. Recording also means a draw is validated while
the frame is being built: a rejected `draw` is skipped, and the frame can still
be ended.

### Order, culling and batching

Before any pass runs, `end_frame` turns the recorded list into a plan:

1. **Cull**: objects whose world bounding box is entirely outside the camera
   frustum are skipped (`set_culling`, on by default). The **shadow pass is not
   culled** — an object off screen can still cast a shadow into view.
2. **Order**: opaque draws first, then transparent ones (any material whose
   `blend` is not `BLEND_NONE`) sorted back to front by their bounding-box centre.
   An application does not have to sort transparency itself, and submission
   order no longer decides the result.
3. **Batch**: runs of draws that share a mesh and a material become one instanced
   draw (`set_batching`, on by default), with the model and normal matrices read
   per instance from a per-frame buffer. Only the built-in shader is instanced; a
   material with a custom shader is drawn one item at a time.

With batching on, opaque draws are grouped by geometry and material, so they are
**reordered**: depth testing decides their visibility, not submission order. That
is safe for normal opaque geometry and wrong for anything that relies on
submission order between coplanar surfaces (deliberate z-fighting, a decal at
exactly the wall's depth).

| Function | Purpose |
|---|---|
| `set_culling(dev, on) -> bool`, `culling_enabled(dev) -> bool` | skip objects outside the view |
| `set_batching(dev, on) -> bool`, `batching_enabled(dev) -> bool` | merge compatible draws into instanced ones |
| `stats(dev) -> Stats` | `culled` objects, `batches` draw calls, `instances` objects drawn instanced, `instanced` instanced draws — all cumulative |

All four are cheap to switch: nothing is precomputed per switch, so a test or a
profile can turn them off between frames and compare.

Read-back and capture:

| Function | Purpose |
|---|---|
| `frame_pixels(dev) -> u8[>..]` | last presented screen, RGBA8, top row first; for tests and tools |
| `screenshot(dev, path) -> bool` | write the screen as a PNG |

Minimal program (the 0.3 defaults: ACES, bloom, shadows, sky):

```goose
var dev = hipgr::Device { .. };
guard hipgr::open(dev, "app", 1280, 720) else { return; }
defer hipgr::close(dev);

let cube = hipgr::mesh_cube(dev);
let mat  = hipgr::material_solid(dev, float4 { 0.9, 0.5, 0.2, 1.0 }, false);
hipgr::set_light(dev, float3 { -0.4, -0.8, -0.6 }, float3_1, 0.25);
hipgr::set_point_light(dev, 0, float3 { 0.0, 1.5, 2.0 }, float3 { 1.0, 0.6, 0.3 }, 8.0);
let cam  = hipgr::camera_look_at(float3 { 0.0, 0.0, 3.0 }, float3_0, float3 { 0.0, 1.0, 0.0 }, 0.8);

while hipgr::begin_frame(dev, cam, float4 { 0.05, 0.06, 0.08, 1.0 }) {
    hipgr::draw(dev, cube, mat, hipgr::mat4_identity());
    if !hipgr::end_frame(dev) { break; }
}
```

---

## Image quality

One preset sets the whole post pipeline; the individual setters override parts
of it.

| Function | Purpose |
|---|---|
| `quality(dev, profile) -> bool` | `QUALITY_LINEAR` or `QUALITY_MODERN` |
| `set_exposure(dev, exposure) -> bool` | multiplies the HDR scene before the tone curve, 0 < exposure ≤ 64 |
| `set_tonemap(dev, mode) -> bool` | `TONEMAP_NONE`, `TONEMAP_REINHARD`, `TONEMAP_ACES` |
| `set_bloom(dev, strength, threshold) -> bool` | strength 0..4 (0 disables the bloom passes), threshold in linear light |
| `set_shadows(dev, on) -> bool` | the shadow pass, and shadow lookups in the shader |
| `set_shadow_area(dev, center, radius) -> bool` | the world box the single shadow map covers |
| `set_sky(dev, horizon: float3, zenith: float3) -> bool` | rebuild the procedural sky cube from two linear colours |
| `set_sky_enabled(dev, on) -> bool` | draw the sky behind the scene |
| `set_fog(dev, density) -> bool` | distance fog towards the horizon colour; 0 disables it |
| `set_ibl(dev, strength) -> bool` | image-based lighting from the sky, 0..4; 0 falls back to the constant ambient |
| `ibl_strength(dev) -> f32` | the current value |
| `sky_horizon(dev)`, `sky_zenith(dev)` | the current sky colours |

| Profile | Meaning |
|---|---|
| `QUALITY_MODERN` (default) | ACES tone mapping, bloom 0.35, the shadow map, the sky, IBL, fog 0.012 |
| `QUALITY_LINEAR` | no tone mapping, no bloom, no shadows, no sky, no IBL, no fog: the scene pass's linear values straight to the screen, which is what 0.2 produced |

`QUALITY_LINEAR` exists for two reasons: it is the profile an application wants
when it is composing colours itself, and it is what the 0.1/0.2 regression tests
run under, so their exact-colour assertions still mean something.

Tone mapping is a choice of curve, and `TONEMAP_NONE` means exactly that: no
curve **and no gamma**. Gamma is applied only with a curve, so `NONE` is the
linear value the scene pass wrote — 0.5 stays 128/255 — while ACES and Reinhard
append the 1/2.2 encode. The sky and the fog colour are linear values too, and
fog fades towards the horizon colour, so distant geometry meets the sky.

Shadow limits stated plainly: one map, one orthographic box, 1024², no cascades,
no sorting, no per-light maps. Everything inside the box casts and receives;
everything outside is unshadowed. A surface shadowing itself is handled by a
constant depth bias (`shadow_bias`, 0.0015 in depth units) plus a four-tap
hardware-compare PCF kernel, not by a slope-scaled bias.

### Image-based lighting

The sky is not only a background: it lights the scene. Two cubes are integrated
from the same two sky colours, on the CPU, when a device opens and again when
`set_sky` changes them:

* a 16² **irradiance** cube, the cosine-weighted mean sky radiance per direction
  (64 samples per texel), which is what a Lambertian surface receives;
* a 32² **prefiltered radiance** cube with five mip levels, mip *n* holding the
  sky blurred by roughness *n*/4 (GGX importance sampling weighted by N·L), which
  is what a reflection sees.

Both are RGBA16F, so a sky brighter than 1.0 still reflects as brighter than 1.0.
The fragment shader combines them in the split-sum approximation — irradiance ×
albedo × (1 − metallic) for diffuse, prefiltered radiance × (F0 × scale + bias)
for specular, with the BRDF integral from Karis' analytic `EnvBRDFApprox` fit
instead of a lookup table.

What that means in practice:

* a metal has no diffuse lobe, so with the sky on it is a mirror of the sky and
  reads as the sky's colour, brighter where the sky is brighter;
* a rough surface blurs the reflection: `roughness` 1.0 samples the whole sky,
  which is why a rough metal is a soft tinted grey rather than a dark one;
* reflections are not occluded (no screen-space pass), so a shadowed metal still
  reflects the sky. Diffuse light is likewise unoccluded, but the shadow map
  removes the sun, which is the bright part;
* a sky that is dark makes the scene dark, exactly as it would outside.

Cost: building the cubes is ~60k deterministic samples, paid on open and on
every `set_sky` — tens of milliseconds on a CPU, once. Sampling costs two cube
lookups plus the BRDF fit per lit pixel: measured on llvmpipe at 960×540, the
demo runs 46.4 ms/frame with IBL off and 51.7 ms/frame with it on (medians of
three 20-frame runs), about +11%. On a GPU these are two cached cube fetches;
that number is a software rasterizer's.

With `set_ibl(dev, 0.0)` the shader takes the old path instead: `ambient` ×
albedo (or × F0/2 for metal), which is what 0.2 rendered, pixel for pixel.
`test_ibl` asserts that equality, and asserts that the sky's colour and its
roughness blur actually reach the surface.

---

## Platform facade

A very small surface so an application never has to import the backend for
input or timing. It is not an input system; games with one should use their own.

| Function | Purpose |
|---|---|
| `key_down(name) -> bool` / `key_pressed(name) -> bool` | SDL key names, verbatim: `"W"`, `"Space"`, `"Left Shift"`, `"Escape"`, `"F12"` |
| `mouse_delta() -> float2` | motion since the last frame, in pixels |
| `mouse_position() -> float2` | |
| `capture_mouse(on) -> bool` | first-person capture (confines and hides the pointer) |
| `quit()` | ask `end_frame` to return false |
| `time() -> f64` / `delta_time() -> f64` | seconds since the device opened / last frame's duration |

**Key names are SDL's own.** An unknown name is a backend misuse, and the
backend aborts at the next frame — `"LeftShift"` is wrong, `"Left Shift"` is
right. Names are not validated by HiPGR because it has no table of SDL's names;
take them from SDL's documentation.
