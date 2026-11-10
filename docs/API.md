# HiPGR — Public API (0.2.0)

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
| `image_load(dev, path: const u8[:]) -> Image` | PNG or BMP through the backend (no mips yet) |
| `image_info(dev, image) -> ImageInfo` | `width`, `height` |
| `release(dev, image)` | free the texture now |

A material refers to its image **by handle**, so releasing an image that a
material still uses is detected at draw time (`ERR_BAD_HANDLE`), not by reading
freed GPU memory.

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
vertex, set 1 b0     Frame    { mat4 view_proj; }
vertex, set 1 b1     Draw     { mat4 model; mat4 normal; }
fragment, set 2 b0   sampler2D u_albedo   (only when the material names an image)
fragment, set 3 b0   Material { vec4 tint; vec4 params; vec4 user0; vec4 user1; }
fragment, set 3 b1   Light    { vec4 direction; vec4 color; vec4 points[16]; }
```

* `normal` is the inverse transpose of `model`'s upper 3×3, so normals survive a
  non-uniform scale.
* `params.x` is 1 when the material is unlit.
* `user0` and `user1` are the material's own data, untouched by HiPGR.
* `direction.xyz` is the direction the directional light travels in; `w` is
  ambient. `color.rgb` is its colour; `w` is the point light count.
* `points` holds, per light, `(position, radius)` then `(colour, 0)`.

---

## Materials

A material is the shading state for a mesh: a shader pair, pipeline state, a
tint, application data, and optionally an image.

```goose
struct MaterialDesc {
    shader: Shader = Shader { 0 },   // 0: the built-in pair for whether there is an image
    image: Image = Image { 0 },      // 0: no texture
    tint: float4 = float4 { 1.0, 1.0, 1.0, 1.0 },
    user0: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    user1: float4 = float4 { 0.0, 0.0, 0.0, 0.0 },
    unlit: bool = false,
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
| `material_solid(dev, tint, unlit) -> Material` | shorthand: no image, built-in solid shader |
| `material_textured(dev, image, tint, unlit) -> Material` | shorthand: built-in textured shader |
| `release(dev, material)` | free the material record; the shared pipeline and sampler stay with the device |

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

Built-in lighting is `directional + Σ point`, where each term is a colour times
`max(dot(n, to_light), 0)`; the directional term is scaled by
`ambient + (1 - ambient) * ndl`. There is no specular term yet.

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

* `begin_frame` validates state, computes view-projection from the camera and
  the current screen aspect, opens the screen pass, and pushes the frame and
  light blocks.
* `draw` binds the material's pipeline, the mesh buffers, the draw and material
  blocks, the texture when the material has one, and issues an indexed draw with
  the mesh's index width. It updates `Stats`.
* `end_frame` closes the pass and presents. It returns **false when the program
  should quit** (window closed, `quit()` called); true means continue.

Read-back and capture:

| Function | Purpose |
|---|---|
| `frame_pixels(dev) -> u8[>..]` | last presented screen, RGBA8, top row first; for tests and tools |
| `screenshot(dev, path) -> bool` | write the screen as a PNG |

Minimal program:

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
