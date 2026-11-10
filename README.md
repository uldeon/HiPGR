# HiPGR — High Performance Goose Renderer
<img width="6912" height="3456" alt="IMG_0842" src="https://github.com/user-attachments/assets/9845d952-5e0d-45cb-a2ce-26025fcd4b5f" />


HiPGR is a 3D rendering library for the [Goose programming language](https://github.com/aardappel/goose),
written in Goose and built on Goose's `gfx` module (SDL3's GPU API: Vulkan,
Direct3D 12, Metal). It is a library, not an engine: applications own their
scene, objects and game loop, and hand HiPGR meshes, materials and transforms
to draw.

It is developed to be usable on its own, and eventually as the graphics
backend of G3E. Nothing in this repository imports or knows about G3E.

**Status: 0.2.0 — 3D renderer.** Meshes up to 66k vertices, materials described
as data (cull, blend, depth, wireframe, per-material samplers), shader pairs an
application embeds itself, one directional and up to eight point lights,
correct normals under non-uniform scale, a camera, and explicit resource
lifetimes — all verified by tests that read the rendered pixels back. See
[PROGRESS.md](PROGRESS.md) for exactly what is verified and
[ROADMAP.md](ROADMAP.md) for what is not built yet.

## Requirements

| | |
|---|---|
| Goose | **v2026.4 or later** (tested with v2026.4, runtime `dce889723a23`) |
| Platform | Windows x64, Linux x64 (only Linux x64 verified so far) |
| GPU backend | Vulkan, Direct3D 12 or Metal through SDL3, as Goose `gfx` provides |
| C toolchain | a C compiler on `PATH` (gcc or clang; MSVC on Windows), for `goose build` |
| Linux | glibc 2.35+ (Ubuntu 22.04 or newer); a Vulkan driver, or Mesa's `lavapipe` for a software device |

HiPGR has no other dependencies. `gfx` is a package compiled into the official
Goose release, so no cmake or package fetch is needed.

## Quick start

```bash
# 0. Put the Goose compiler on PATH (unpack the release, then):
export PATH=/opt/goose/goose-v2026.4-linux-x64:$PATH

# 1. Build and run the demo (window, free camera, four materials, point light)
goose build examples/demo_cube.goose
./examples/demo_cube

# 2. The smallest complete program
goose build examples/triangle.goose
./examples/triangle

# 3. Build everything and run the GPU tests headless
./scripts/test.sh

# 4. Frame benchmark
./scripts/bench.sh 256 60
```

On a machine with no display, render off-screen — no window is opened, and
rendering, read-back and screenshots all still work:

```bash
GOOSE_GFX_HEADLESS=1 ./examples/demo_cube --frames 60 --shot demo.png
```

On Windows, use the prebuilt `goose-v2026.4-windows-x64.zip` compiler and run
the same `goose build` / program commands from PowerShell or cmd. The
`scripts/*.sh` runners need Git Bash; each test can also be run directly (see
[Testing](#testing)).

Demo controls: `WASD` move, `Q`/`E` down/up, `Tab` capture the mouse, mouse to
look, `Left Shift` to move faster, `Space` pause the spin, `F12` save
`demo.png`, `Escape` quit.

## Using HiPGR in your own program

Add the package to your root file and import nothing else. This is
[`examples/minimal.goose`](examples/minimal.goose) verbatim, so it compiles:

```goose
import std;
import os;
import vec;
import hipgr from "../HiPGR/src/hipgr";

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open(dev, "my app", 1280, 720) else {
        write_stderr(str("hipgr: ", hipgr::error_text(hipgr::error_code(dev)), "\n"));
        return;
    }
    defer hipgr::close(dev);              // releases whatever is still live

    let cube = hipgr::mesh_cube(dev);                       // mesh
    let img  = hipgr::image_checker(dev, 64, 8, [40,40,60,255], [220,200,120,255]);
    let mat  = hipgr::material_textured(dev, img, float4_1, false);   // material
    hipgr::set_light(dev, float3 { -0.4, -0.8, -0.6 }, float3_1, 0.25);

    let cam = hipgr::camera_look_at(float3 { 0.0, 0.8, 3.0 }, float3_0,
                                    float3 { 0.0, 1.0, 0.0 }, 0.8);

    var t: f32 = 0.0;
    while hipgr::begin_frame(dev, cam, float4 { 0.05, 0.06, 0.08, 1.0 }) {
        t += hipgr::delta_time() as! f32;
        hipgr::draw(dev, cube, mat, hipgr::mat4_spin(float3_0, t, 1.0));
        if !hipgr::end_frame(dev) { break; }     // false: window closed / quit
        if hipgr::key_pressed("Escape") { break; }
    }
}
```

`import gfx;` is not needed, and `scripts/test.sh` fails the build if any
example or test imports the backend directly, so that stays true.

The full public surface is documented in [docs/API.md](docs/API.md).

## Design in one page

```
application  ──►  hipgr (public API: Device, Mesh, Material, Camera, Mat4)
                    │
                    ├─ renderer   frame lifecycle, draw submission, uniform blocks
                    ├─ material   shader pairs, MaterialDesc, caches, lights
                    ├─ mesh       Vertex, Mesh, 16/32-bit indices, updates
                    ├─ image      RGBA8 textures
                    ├─ camera     view / projection
                    ├─ state      cull / blend / filter / wrap, as data
                    ├─ math       Mat4, transforms, normal matrix
                    ├─ device     resource records, generation-checked handles
                    ├─ platform   keys, mouse, clock
                    └─ gpu        the backend boundary  ──►  Goose gfx  ──►  SDL3 GPU
```

* **The backend is one file.** `src/hipgr/gpu.goose` is the only module that
  issues `gfx` calls; the renderer above it deals in HiPGR handles and uniform
  byte blocks. Replacing the backend means reimplementing that file.
* **The device owns the resources.** Goose has no destructors and no heap, so
  ownership is explicit: creating a resource returns a handle, `release()`
  frees it immediately, and `close(dev)` frees whatever is left. A handle
  carries an index and a generation, so a released handle is reported as an
  error instead of reaching the GPU.
* **Errors are values, not crashes.** Every fallible call returns `false` (or a
  zero handle) and records a code on the device: `hipgr::error_code(dev)` and
  `hipgr::error_text(code)`.
* **No scene graph.** Applications submit `draw(dev, mesh, material, model)`.
  HiPGR does not own a world, an ECS or a hierarchy; that is what lets G3E use
  it without HiPGR dictating G3E's scene model.
* **Materials are data, and pipelines are cached.** State is a `MaterialDesc`
  value; materials that ask for the same state share one pipeline and sampler,
  which the device owns. An application can bring its own shader pair with
  `shader_create` and read its own `user0`/`user1` data through a documented
  block layout, without ever seeing a backend type.

More detail: [ARCHITECTURE.md](ARCHITECTURE.md).

## Repository layout

```
src/hipgr/          the library (Goose package, namespace hipgr)
  shaders/          built-in GLSL, compiled into programs by embed_shader
examples/           demo application and a minimal example
tests/              GPU tests that check pixels, plus a CPU camera test
bench/              frame benchmark
scripts/            test and benchmark runners
docs/API.md         public API reference
docs/goose-notes.md  notes on the Goose and gfx behaviour HiPGR relies on
```

## Testing

```bash
./scripts/test.sh                 # all tests, headless
GOOSE=/path/to/goose ./scripts/test.sh
```

Each test is a Goose program. It prints `PASS name` when the checks it ran
succeeded, `SKIP name` when the machine has no GPU device (nothing was
validated in that case), and aborts with a reason otherwise. The ten tests
cover triangle placement, textured and rotating cubes, depth ordering, resource
lifetime and misuse, camera projection, 256-object frames, material state
(wireframe, blending, culling, custom shaders, pipeline sharing), point-light
falloff and radius, the normal matrix under non-uniform scale, and a
66049-vertex mesh. The runner also fails on any compiler warning and on any
`import gfx;` outside the library. A rendering feature is only recorded as
verified in [PROGRESS.md](PROGRESS.md) when a test reads the pixels it
produced.

## Platform status

* **Linux x64** — verified in this repository's development environment, on
  Mesa's `lavapipe` software Vulkan device (no physical GPU was available).
  Correctness is verified; the frame times are not representative of hardware.
* **Windows x64** — expected to work (Goose ships a Windows compiler with
  `gfx` built in and SDL3 uses Direct3D 12), but **not verified**: no Windows
  machine was available. See [RECONNAISSANCE.md](RECONNAISSANCE.md) for the
  reproducible steps.

## Documentation

| Document | What it covers |
|---|---|
| [RECONNAISSANCE.md](RECONNAISSANCE.md) | What was actually verified about Goose, `gfx` and this environment, with commands and outputs |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The design, its invariants, and the constraints Goose imposes |
| [ROADMAP.md](ROADMAP.md) | Milestones with acceptance criteria, and their status |
| [PROGRESS.md](PROGRESS.md) | Implemented / tested / partial / planned, feature by feature |
| [AGENT_RULES.md](AGENT_RULES.md) | Rules for agents continuing this work |
| [docs/API.md](docs/API.md) | The public API reference |
| [CHANGELOG.md](CHANGELOG.md) | Release notes |

## License

HiPGR itself has no license file yet; Goose is Apache 2.0. Add a license before
publishing or accepting contributions.
