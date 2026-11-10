# HiPGR — Technical Reconnaissance

Date: 2026-11-10.
Documented by: the initial implementation session.
Purpose: establish what Goose and its graphics module actually do before
designing HiPGR, and record which claims are verified, which are documented
upstream but untested here, and which are unknown.

Everything below was checked in this environment unless it is marked
**documented (not tested)**. Commands are reproducible; see
[§11](#11-reproducing-this-reconnaissance).

---

## 1. What this environment is

| | |
|---|---|
| OS | Ubuntu 22.04.5 LTS, x86-64, running as root |
| Workspace | `/home/daytona/codebase` |
| Display | none: `DISPLAY` and `WAYLAND_DISPLAY` unset, no X server, no Wayland compositor |
| GPU device node | none: `/dev/dri` does not exist; no `nvidia-smi` |
| C toolchain | gcc 11.4.0 (`/usr/bin/cc`), make 4.3. **No clang, no cmake.** |
| Other tools | git 2.34.1, node 22, python 3.10, gh 2.101. No Go, Rust, or D compiler. |
| X11 / Wayland dev packages | absent (`pkg-config` itself is not installed) |

Consequences for graphics work:

* A window cannot be opened, so every rendering result has to be produced
  **off-screen** and validated by **reading pixels back**.
* The release builds of Goose are self-contained (see §3), so the missing cmake
  and X11 headers do not block using `gfx`; they only block building Goose or
  its packages from source.

### What was installed to make GPU execution possible

```bash
apt-get install -y libvulkan1 mesa-vulkan-drivers vulkan-tools
```

`mesa-vulkan-drivers` provides **lavapipe**, a CPU implementation of Vulkan.
`vulkaninfo --summary` then reports:

```
GPU0: apiVersion = 4206847 (1.3.255)
      driverVersion = 1 (0x0001)
      deviceType = PHYSICAL_DEVICE_TYPE_CPU
      deviceName = llvmpipe (LLVM 15.0.7, 256 bits)
      driverID = DRIVER_ID_MESA_LLVMPIPE
      driverName = llvmpipe
```

So: **a real Vulkan driver is present, implemented on the CPU.** There is no
hardware GPU. Everything in this repository that runs on a "GPU" here runs on
llvmpipe, which is correct but slow, and its timings say nothing about real
hardware.

## 2. How to get Goose

```bash
curl -LO https://github.com/aardappel/goose/releases/download/v2026.4/goose-v2026.4-linux-x64.tar.gz
mkdir -p /opt/goose && tar xzf goose-v2026.4-linux-x64.tar.gz -C /opt/goose
export PATH=/opt/goose/goose-v2026.4-linux-x64:$PATH
```

The release archive contains the compiler, the standard library, the pinned
`gfx`/`audio`/`ui`/`physics` packages, the samples, the documentation and the
VS Code extension. `GOOSE_HOME` defaults to `~/.goose`, where compiled runtime
and package artifacts are cached.

## 3. Exact compiler and toolchain

```
$ goose version
goose v2026.4 (runtime dce889723a23)

$ goose toolchain
C compiler:   gcc 11.4.0, found on PATH
              /usr/bin/cc
C++ compiler: /usr/bin/g++
style:        cc
id:           gcc-11.4.0-a920ca84
cmake:       not found on PATH
git:          /usr/bin/git (2.34.1)
built in:     physics, gfx, audio, ui
GOOSE_HOME:   /home/daytona/.goose

$ goose --gfx-link cc
/home/daytona/.goose/build/builtin/gfx-c228da1c/link-cc.rsp
```

Facts that matter for HiPGR:

* **Minimum Goose version for this repository: v2026.4.** That is the release
  the code was written and verified against, and the one whose `gfx` API is
  used. Pin it; `gfx` is young and its API is still moving.
* `gfx` is **compiled into the compiler** in the official release (`built in:
  gfx`), together with a static SDL3 (pinned at `release-3.4.16`) and a shader
  compiler (cute_spirv). No separate package fetch, cmake or network access is
  needed to build a graphics program.
* Goose compiles a whole program to **one C file**, then calls gcc. `goose run`
  compiles and runs that C in-process with bundled TinyCC; `goose build`
  produces a native executable next to the source. Programs using threads must
  be built (TinyCC cannot place thread-local storage).
* `goose check` typechecks without linking — useful in CI without a GPU.
* Compiled executables are large because SDL is linked statically:
  `examples/demo_cube` is 3.4 MB, `examples/triangle` 3.4 MB.
* Cold build of a graphics program here takes ~1.4 s (the runtime C is cached
  in `GOOSE_HOME` after the first build per C compiler).

## 4. `gfx`: what it is

`import gfx;` gives a Goose program: a window and its input, GPU buffers and
textures, samplers, graphics and compute pipelines, render and compute passes,
and read-back. Underneath is **SDL3's GPU API (SDL_GPU)**, which draws through
**Direct3D 12, Vulkan or Metal**. The layering, from the package's own docs:

```
Goose program --extern fn--> gs_gfx_* (goose_gfx, native C) --> SDL3 (static) --> D3D12 | Vulkan | Metal
```

The layer between Goose and SDL is a natively compiled static library, not a
header spliced into the generated C: neither the generated C nor TinyCC sees an
SDL header. 64 functions cross the boundary.

Shaders are **GLSL 450**, compiled **when the program is compiled** by the
builtin `embed_shader`, into SPIR-V, MSL and HLSL at once, with reflection SDL
needs. There is no runtime shader compilation.

### The API surface (verified against `gfx.goose` in v2026.4)

Device / frames: `open`, `open_headless`, `close`, `frame`, `quit`, `flush`,
`error`, `check`, `driver`, `screen`, `screen_depth`, `screen_size`, `time`,
`delta_time`, `frame_count`.

Buffers: `buffer`, `vertex_buffer`, `index_buffer`, `update_buffer`,
`read_buffer`, `buffer_size`, `release`.

Textures: `texture`, `texture2d`, `render_target`, `depth_target`, `texture3d`,
`texture_cube`, `texture_array`, `load_texture` (PNG/BMP), `update_texture`,
`read_texture`, `read_pixels`, `save_png`, `screenshot`, `generate_mips`,
`texture_info`, `release`.

Samplers: `sampler`, `shadow_sampler`, `release`.

Pipelines and drawing: `pipeline`, `compute_pipeline`, `begin_pass`,
`begin_screen`, `end_pass`, `bind`, `bind_vertex_buffer`, `bind_index_buffer`,
`bind_texture`, `bind_storage_texture`, `bind_storage_buffer`, `uniforms`,
`push_uniforms`, `viewport`, `scissor`, `draw`, `draw_indexed`, and the
`*_instanced` forms, `begin_compute`, `dispatch`, `end_compute`.

Math: `mat4` (column-major), `mul`, `translate`, `scale`, `rotate`,
`perspective`, `ortho`, `look_at`.

### Contract details that HiPGR depends on

* **Bindings are checked at compile time.** Vertex uniform blocks are set 1,
  fragment uniform blocks set 3, fragment samplers set 2, and a resource in the
  wrong set is a compile error that names the rule.
* **Uniform blocks are std140; Goose structs are packed.** A pushed struct must
  match the shader block's *size* (member offsets are not checked in 0.1 of
  gfx). HiPGR's blocks are designed to match exactly: 64, 64, 32, 32 bytes.
* **Vertex inputs come from the shader's locations**, packed in one struct in
  location order, from vertex buffer 0; `instance_location` splits per-instance
  data into buffer 1.
* **Clip space is SDL_GPU's on every backend**: y up, depth 0..1, texture
  coordinate (0,0) at the top left. `perspective` is right-handed looking down
  -Z with depth 0 at near.
* **A pipeline is not tied to its render targets**: it is created per
  combination of target formats/samples the first time it is bound in a pass.
* **Handles are one u32 with a slot index and a generation**: using a released
  handle is an error, not a crash.
* **Two kinds of failure.** A failure outside the program's control (no GPU, a
  missing file) returns false or a zero handle with the reason in `error()`. A
  call the program should not have made is a *misuse*: skipped, printed,
  counted, and **the program aborts at the next `frame()`, `check()`, read-back
  or `close()`**.

That last point is a real constraint for a library: HiPGR must not let a
mistake reach `gfx`, because aborting the host application is not acceptable
library behaviour. HiPGR validates handles, indices, frame state and image
lifetimes itself, and reports through the device instead (see
`tests/test_handles.goose`, which proves each rejection happens without a
process abort — except for a deliberate `close()` after misuse).

## 5. GPU execution: what actually ran

### 5.1 The official sample, unmodified

```bash
cp .../samples/27_gfx_cube.goose .
goose build 27_gfx_cube.goose            # 1.4 s
GOOSE_GFX_HEADLESS=1 ./27_gfx_cube
```

Output:

```
Installed Vulkan doesn't implement the VK_EXT_headless_surface extension
drew 131981 frames; cube in the middle: true; saved gfx_cube.png: true
```

The sample's own check reads the centre pixel back and compares it with the
clear colour, and it wrote a 5131-byte PNG. So on this machine: **device
creation, windowless surface, shader compilation, vertex/index buffers, depth
buffer, uniform block, draw, present and texture read-back all work.**

The first line is a harmless warning from SDL: the Vulkan driver has no
headless-surface extension, so SDL falls back to its offscreen video driver,
which is exactly the path documented for CI.

### 5.2 HiPGR's own rendering

`./scripts/test.sh` on this machine: 6 passed, 0 skipped, 0 failed. Every GPU
test reads the rendered pixels back and asserts on them — placement, texture
texels, depth ordering, rotation changing the image, 256-object frames. See
[PROGRESS.md](PROGRESS.md#verification-evidence).

Frame timing on llvmpipe (software, 1280x720, 256 cubes = 3072 triangles per
frame, textured and lit):

```
elapsed 0.452 s, 7.54 ms/frame, 133 fps
```

These numbers are **not** a performance claim: they are a CPU rasterizer. They
are useful only as a regression baseline on this machine.

## 6. Language constraints that shaped the architecture

Goose is a memory-safe systems language with **no heap allocator, no garbage
collector, no destructors**. Memory is a set of compiler-managed data stacks.
This is the single most important fact for a renderer's design.

| Constraint | Evidence | Consequence in HiPGR |
|---|---|---|
| No destructors / `Drop` / RAII | language design (README, spec) | Resources are released explicitly: `release(dev, handle)` and `close(dev)`. The device owns everything so `close` cannot leak. |
| An ordinary struct owns **at most one** growable array, on its tail; a `root struct` may have several independent ones | spec §3.4 | `Device` is a root struct with one growable array per resource kind. Root values cannot be copied, passed, returned or used as fields. |
| Root structs are reached by reference only | spec §3.4 | Every API entry point takes `Device&`. |
| Growable arrays cannot be array elements | spec §3.4 | No `Mesh[]` inside a struct; records are fixed-size structs in flat arrays. |
| No inheritance, traits or vtables; ADTs are the only dynamic polymorphism | spec §3.5 | A runtime-swappable backend object is impossible. The backend boundary is a *module* (`gpu.goose`) chosen at compile time, not an interface value. Material kinds dispatch on a tag. |
| No closures or function pointers; function values are compile-time entities | README | No per-material callbacks or user shader hooks in 0.1. |
| `embed_shader` arguments are literals or globals initialized with one | `gfx` docs | Shaders live in the library as `.vert`/`.frag` files and are compiled into the program at build time. **Verified:** a package module can embed its own shader files (paths resolve relative to the calling file). |
| `gfx` cannot be reached from a `thread_fn` | **verified**: compile error `gfx runs on the main thread only: gfx::open_headless is reached from thread_fn worker` | Rendering is main-thread only. CPU-side work (decode, generation) may use workers; GPU upload must happen on the main thread. Note the error names the `gfx` call, not HiPGR's wrapper. |
| Whole-program compilation, no separate compilation | README | Libraries are source packages (`import hipgr from "path"`), rebuilt with the program. |
| No namespace privacy | language scope notes | `Device` internals are visible. Fields prefixed `gpu_` are implementation detail by convention; documented as such. |

Two further practical facts found while building HiPGR:

* **A package's other modules are reachable through the package name.** A
  package can be split across files that share `namespace hipgr;`, import each
  other with `import .module;`, and applications still write `hipgr::name`.
  Verified with a two-module package.
* **A package that imports `gfx` does not force the application's root file to
  declare `gfx`.** Verified: an application whose only import is `hipgr` builds
  and runs, because `gfx` is a blessed package. This is what makes the "no
  backend in the public API" property enforceable, and `scripts/test.sh`
  enforces it.

### Goose compiler quirks met in practice

* `assert(cond)` takes a bool only; there is no message argument. Tests build
  their own failure text and `abort`.
* Redundant casts are warnings (`redundant 'as f32': an i32 converts to f32
  implicitly here`). This repository builds with **zero warnings**, and treats
  a new warning as a defect.
* A `var` slot holding a string must be declared `const u8[:]`; storing a
  read-only slice in `u8[:]` is a compile error (§9.5).
* An expression-bodied function with a non-void return type needs an explicit
  `return`, even when the body is a single call.
* `write_stderr` lives in the `os` module, not `std`.
* A known compiler bug documented by the `gfx` package: a fresh growable result
  passed straight into an inlined function's slice parameter can produce
  invalid C at `-O1`/`-O2`. HiPGR binds such values to locals first
  (`mesh_cube` → `mesh_create`); this was a precaution, not reproduced here.

## 7. What Goose cannot currently do (for this project)

1. **No RAII.** A renderer must design for explicit lifetimes. Mitigation: the
   device owns resources and `close` sweeps; handles carry generations.
2. **No runtime polymorphism.** No plug-in backend chosen at runtime. A second
   backend is a different build of this library, or a compile-time choice.
3. **No shader hot-reload or runtime shader compilation.** Shaders are compiled
   with the program. Iterating on a shader means a rebuild (1–2 s here).
4. **No debug labels, indirect draws, stencil or blend constants** in `gfx`
   (listed upstream as follow-up work), so 0.1 cannot offer GPU debug markers
   or indirect/instanced-by-buffer draws.
5. **No way to attach to an existing window or swapchain.** `gfx::open` creates
   the window. An application with its own window (or an editor viewport) cannot
   hand it to HiPGR in 0.1.
6. **No depth-texture read-back region** (SDL limitation noted upstream), which
   limits depth-precision tests to what the colour pass shows.
7. **No 3D asset importers.** `gfx` loads PNG/BMP textures only. glTF/GLB,
   KTX2 and HDR parsing would have to be written in Goose (or via C) — a
   milestone of its own.
8. **Single-threaded rendering.** No parallel command recording.

## 8. Which parts can use `gfx`, and which might eventually bypass it

**Use `gfx` (0.1 does this):**

* device, window and swapchain management (SDL3 picks the backend and handles
  platform quirks);
* buffer/texture creation, uploads, read-back, screenshots;
* render passes, pipelines, bindings, draws, depth, viewport/scissor;
* shader compilation (`embed_shader` → SPIR-V/MSL/HLSL);
* input and timing, through the thin `platform.goose` facade.

**Candidates to bypass later, in order of expected value:**

1. **Descriptor/binding overhead** — if profiling shows the per-draw uniform
   pushes dominate for many-object scenes, a backend with explicit descriptor
   sets/root signatures would help. Not measurable through llvmpipe here.
2. **Instancing and indirect draws** — `gfx` has `draw_*_instanced` but no
   indirect draw; a large scene wants indirect + GPU culling.
3. **Multi-threaded command recording** — impossible through `gfx`; would need
   a native layer written for HiPGR.
4. **Render graph / barrier control** — `gfx` inserts its own barriers; a pass
   graph wants explicit control.
5. **Native surface attachment** — required if G3E ever embeds the renderer in
   its own windowing or an editor.

None of these is justified yet. The measurements that would justify them
(many-object frame time, uniform-push cost, draw-call overhead) cannot be taken
honestly on a CPU rasterizer.

## 9. Windows and Linux

* **Linux x64**: verified here, on Vulkan via lavapipe. Windowed mode is
  unverified because the container has no display; the same code path is used
  by the official sample, whose windowed mode is exercised in Goose's own CI.
* **Windows x64**: not verified — no Windows machine was available.
  Reproducible steps for whoever has one:
  1. unpack `goose-v2026.4-windows-x64.zip`, put it on `PATH`;
  2. `goose build examples\demo_cube.goose` and run `examples\demo_cube.exe`
     (Direct3D 12 by default; `gfx::driver()` prints which backend was used);
  3. run the tests: `goose build tests\test_triangle.goose` then
     `tests\test_triangle.exe` for each test, with `GOOSE_GFX_HEADLESS=1` set
     in the environment (`scripts/test.sh` itself needs Git Bash).
* **What to expect on Windows**: MSVC or clang on `PATH` for `goose build`;
  `d3dcompiler_47.dll` is loaded by name for DXBC, which ships with Windows 10
  and 11. Headless mode on Windows relies on SDL's offscreen driver plus D3D12
  and is **unverified** — if it fails, run windowed there.

## 10. What is uncertain

* Real-GPU correctness beyond Vulkan (D3D12 and Metal) — the shaders and the
  uniform layout are backend-neutral, but only Vulkan has been exercised here.
* Real-GPU performance, and therefore every performance decision in
  [ROADMAP.md](ROADMAP.md) 0.4.
* Whether SDL's offscreen path is reliable on Windows.
* `gfx::delta_time()` accuracy under llvmpipe; frame-time numbers from the demo
  and benchmark should be read as relative, not absolute.
* Long-running resource churn: HiPGR's records are append-only in 0.1 (released
  slots are not reused, though handles already carry generations for when they
  are). Creating and destroying many resources per frame would grow the
  registry; no workload in 0.1 does that.
* `gfx` is a young package. Pin Goose v2026.4 until its API settles.

## 11. Reproducing this reconnaissance

```bash
# toolchain
curl -LO https://github.com/aardappel/goose/releases/download/v2026.4/goose-v2026.4-linux-x64.tar.gz
mkdir -p /opt/goose && tar xzf goose-v2026.4-linux-x64.tar.gz -C /opt/goose
export PATH=/opt/goose/goose-v2026.4-linux-x64:$PATH
goose version && goose toolchain

# a GPU device, in software
apt-get install -y libvulkan1 mesa-vulkan-drivers vulkan-tools
vulkaninfo --summary | sed -n '/Devices:/,/^$/p'

# the official sample, unmodified
cd /tmp && cp /opt/goose/goose-v2026.4-linux-x64/samples/27_gfx_cube.goose . \
  && goose build 27_gfx_cube.goose && GOOSE_GFX_HEADLESS=1 ./27_gfx_cube

# HiPGR
cd /home/daytona/codebase && ./scripts/test.sh && ./scripts/bench.sh 256 60
```
