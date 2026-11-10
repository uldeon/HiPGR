# HiPGR — Public API (0.1.0)

Everything lives in namespace `hipgr`. Import the package and nothing else:

```goose
import hipgr from "../src/hipgr";
```

No `gfx` type appears in this API. Handles are opaque:

```goose
struct Mesh { id: u32 }
struct Image { id: u32 }
struct Material { id: u32 }
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
    meshes: i64, images: i64, materials: i64,
}
```

`meshes`/`images`/`materials` are live counts; `frames`, `draws` and
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
| `ERR_BAD_ARGUMENT` | invalid argument or geometry |
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
| `mesh_create(dev, vertices: const Vertex[:], indices: const u16[:]) -> Mesh` | upload; validates count, triangle count, and every index |
| `mesh_triangle(dev) -> Mesh` | one triangle facing +Z |
| `mesh_quad(dev) -> Mesh` | unit quad in XY, facing +Z |
| `mesh_cube(dev) -> Mesh` | unit cube, 24 vertices, 12 triangles, per-face normals and full-face UVs |
| `mesh_info(dev, mesh) -> MeshInfo` | `vertices`, `indices`, `triangles`, `vertex_bytes`, `index_bytes` |
| `release(dev, mesh)` | free the GPU buffers now |
| `vertex_bytes() -> i64` | 32 |

Limits and rules in 0.1: indices are `u16`, so at most 65536 vertices per mesh;
a mesh must be triangles; `mesh_create` copies the data into GPU buffers (the
CPU-side arrays may go out of scope immediately).

---

## Images

An image is an RGBA8 sampled 2D texture, row 0 first.

| Function | Purpose |
|---|---|
| `image_rgba8(dev, width, height, pixels: const u8[:]) -> Image` | upload tightly packed RGBA8 |
| `image_checker(dev, size, cell, ca: u8[4], cb: u8[4]) -> Image` | deterministic two-colour checkerboard |
| `image_load(dev, path: const u8[:]) -> Image` | PNG or BMP through the backend (no mips in 0.1) |
| `image_info(dev, image) -> ImageInfo` | `width`, `height` |
| `release(dev, image)` | free the texture now |

A material refers to its image **by handle**, so releasing an image that a
material still uses is detected at draw time (`ERR_BAD_HANDLE`), not by reading
freed GPU memory.

---

## Materials

A material is the shading state for a mesh: a pipeline shared with every
material of the same kind, a tint, an unlit flag and (for textured materials) an
image.

| Function | Purpose |
|---|---|
| `material_solid(dev, tint: float4, unlit: bool) -> Material` | tint only |
| `material_textured(dev, image, tint: float4, unlit: bool) -> Material` | albedo texture × tint |
| `set_light(dev, direction: float3, color: float3, ambient: f32) -> bool` | the single directional light; `direction` is the direction it travels in; `ambient` in 0..1 |
| `release(dev, material)` | free the material record (the shared pipeline stays with the device) |

Both built-in materials are lit unless `unlit`. Lighting is
`ambient + (1 - ambient) * max(dot(n, -direction), 0)`, multiplied by the light
colour.

Not yet available (0.2): custom shader pairs, pipeline state per material
(cull/blend/depth flags), per-material samplers, point lights.

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
| `mat4_look_at`, `mat4_perspective`, `mat4_ortho` | projection helpers |
| `mat4_column(m, i) -> float4` | column `i`, for diagnostics and tests |

---

## Rendering

```goose
fn begin_frame(dev, camera: Camera, clear: float4) -> bool
fn draw(dev, mesh: Mesh, material: Material, model: Mat4) -> bool
fn end_frame(dev) -> bool
```

* `begin_frame` validates state, computes view-projection from the camera and
  the current screen aspect, opens the screen pass and pushes frame state.
* `draw` submits one renderable. Order is submission order; there is no
  sorting, batching or culling in 0.1.
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
