# Notes on Goose and `gfx` that HiPGR depends on

Working notes for anyone changing this repository. Facts here were checked
against Goose v2026.4; see [RECONNAISSANCE.md](../RECONNAISSANCE.md) for how.

## The memory model, in the shape that matters here

* There is **no heap, no GC and no destructors**. Memory is compiler-managed
  data stacks. A growable value (`T[>..]`) lives on a data stack and is released
  when its scope exits.
* An **ordinary struct may own one growable array, on its tail**. A
  **`root struct` may own several**, each with independent storage:

  ```goose
  root struct Device {
      meshes: MeshRec[>..] = [],
      images: ImageRec[>..] = [],
      …
  }
  ```
* A root value cannot be copied, assigned wholesale, passed or returned by
  value, or used as a field of another struct. Functions take `Device&`.
* Growable arrays cannot be array elements, so every record in a registry is a
  fixed-size struct.
* Growth is a bump allocation and references into a grow-only array stay valid,
  so `push` returning a reference is safe to keep.

## Language details that cost time if you guess

| Rule | Wrong | Right |
|---|---|---|
| Expression-bodied non-void functions | `fn f() -> bool { g() }` | `fn f() -> bool { return g() }` |
| `write_stderr` lives in `os` | `import std;` | `import std; import os;` |
| A variable holding a string literal must be const | `var p: u8[:] = "";` | `var p: const u8[:] = "";` |
| Redundant casts are warnings | `x as f32` where x is i32 | `x` (an i32 converts implicitly) |
| `assert` takes a bool only | `assert(c, "msg")` | build the message and `abort(str(...))` |
| `for` over a range | `for i in 1..=n` | `for i in 1..n` |
| Slices from a fresh growable into an inlined call | `f(build())` | bind first: `let s = build()[..]; f(s)` (a known compiler bug upstream) |

This repository builds with **zero warnings**. A new warning is a defect.

## Shaders

* `embed_shader("shaders/x.vert")` compiles a file **when the program is
  compiled**, into SPIR-V, MSL and HLSL at once. There is no runtime shader
  compilation.
* The path resolves **relative to the file that contains the call**, so a
  library can ship its own shaders (HiPGR does, in `src/hipgr/shaders/`).
* GLSL 450, cute_spirv dialect: no doubles, no geometry/tessellation stages,
  uniform blocks have no instance names, and a storage buffer block holds one
  runtime array.
* A shader that does not compile is a **compile error at the call**, with the
  offending GLSL line.
* Resources must sit where SDL_GPU expects them or it is a compile error:

  | Stage | Set | Holds |
  |---|---|---|
  | vertex | 0 | samplers, then storage textures, then read-only storage buffers |
  | vertex | 1 | uniform blocks |
  | fragment | 2 | samplers, then storage textures, then read-only storage buffers |
  | fragment | 3 | uniform blocks |

  `slot` counts within one kind: the first storage buffer is slot 0 however many
  samplers precede it.

## Uniform blocks

* Shaders are std140; Goose structs are packed. A `vec3`/`vec4` member starts on
  a 16-byte boundary and a block's size rounds up to 16.
* The backend checks the **size** of a pushed struct (not member offsets), and
  an incorrect size is a misuse.
* A fixed-size array in a Goose struct is inline, so `bytes_of` includes it:
  `LightUniform`'s `points: float4[16]` is 256 bytes of the 288. Verified — a
  std140 `vec4 points[16]` in the shader matches it and the draw works.
* HiPGR's blocks are built to match exactly: `Frame` 64, `Draw` 128, `Material`
  64, `Light` 288 bytes. If you add a member, keep the size identical in
  `renderer.goose` and the shaders, or the draw fails.

## Errors and misuse

* A failure the program cannot control returns `false` / a zero handle with the
  reason in `gfx::error()`.
* A call the program should not have made is a **misuse**: printed, counted,
  skipped — and the program aborts at the next `frame()`, `check()`, read-back
  or `close()`.
* Therefore a library must not pass application mistakes to the backend. HiPGR
  validates handles, lifetimes, indices and frame state first, and reports
  through `Device.last_error`. Tests assert that no abuse reaches the backend.
* An unknown SDL **key name** is a misuse, not a false return: `key_down("Left
  Shift")` is valid, `key_down("LeftShift")` aborts later. There is no query API
  for valid names in `gfx`.

## Threads

`gfx` cannot be reached from a `thread_fn`; the compiler says so:

```
error: gfx runs on the main thread only: gfx::open_headless is reached from thread_fn worker
```

Workers are separate programs with their own memory, exchanging flat values
through typed queues. So: prepare data on a worker, upload on the main thread.
Note the diagnostic names the `gfx` call, not HiPGR's wrapper.

## Packages

* A package is a directory with `name.goose` declaring `namespace name;`.
  Further files sit beside it, share the namespace, and import each other with
  `import .module;`. Applications import the package once and see every module's
  public names as `name::thing` (verified).
* A package that imports a blessed package (`gfx`) does not force the
  application's root file to declare it (verified). That is what lets
  applications import only `hipgr`.
* Root files declare packages: `import hipgr from "../src/hipgr";`.
* Whole-program compilation: there is no separate compilation, so the library is
  rebuilt with each program (1–2 s here).

## Rendering conventions in `gfx`

* Right-handed, camera looks down -Z; clip depth **0..1** (not -1..1).
* Texture coordinate (0,0) is the **top-left**.
* Front faces are counter-clockwise by default; `PipelineDesc.clockwise` flips
  it.
* A pipeline is not tied to render targets: it is created per target-format
  combination the first time it is bound in a pass.
* Pipelines, buffers and textures use one `u32` handle with a generation, so a
  released handle is an error rather than a crash.
* `open()` under `GOOSE_GFX_HEADLESS=1` opens no window; on a machine with no
  display, SDL falls back to its offscreen driver and prints
  `Installed Vulkan doesn't implement the VK_EXT_headless_surface extension`,
  which is harmless noise on stderr.
