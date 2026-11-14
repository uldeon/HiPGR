# HiPGR — Using it from another project

This is 0.5's contract with a host: what the public surface is, what changing it
costs, and how to embed the renderer in an application it does not own.

## Consuming the package

There is no package registry: a Goose package is source, imported by path.

```goose
import hipgr from "../HiPGR/src/hipgr";
```

At a pinned revision that is the whole story — `git clone`, `git checkout
v0.5.0`, build. `scripts/consumer.sh` does exactly this in a temporary copy of
the tree and builds [`integration/consumer.goose`](../integration/consumer.goose),
an application that lives outside the package and uses nothing but the public
API. If that check passes, an application can consume HiPGR from this commit.

An application never imports `gfx`. `scripts/test.sh` and `scripts/consumer.sh`
both fail if anything outside `src/hipgr` does.

## Versioning and the compatibility policy

`hipgr::version()` and [CHANGELOG.md](../CHANGELOG.md) carry a semantic version.
For a `0.x` library the rules are deliberately conservative:

| Change | Version | What it costs a host |
|---|---|---|
| A declaration removed, or its parameters or result changed | **minor bump** | a migration note in `CHANGELOG.md`; the host must edit its call |
| A struct field removed or reordered | **minor bump** | same; a reordered field can also move a uniform block |
| A uniform block's size changes (`Frame`, `Draw`, `Material`, `Light`, `Surface`, `Post`) | **minor bump** | every custom shader that declares the block must be updated |
| A behaviour change that can change pixels | **minor bump** | a note saying what moved and why |
| A new function, constant or field; an internal refactor | patch | nothing — old code keeps compiling and rendering |
| A fix that restores documented behaviour | patch | nothing |

`docs/api-surface.txt` is the recorded surface: one line per public declaration
in `src/hipgr`. `scripts/api_surface.sh` extracts the same lines from the code
and fails when a recorded line is **removed or changed**, and when a line is
**added without being recorded**. So a breaking change cannot reach `main`
without someone writing it down:

```
./scripts/api_surface.sh            # check (runs in ./scripts/test.sh)
./scripts/api_surface.sh --record   # accept the current surface, after the bump
```

The check covers the whole package because Goose has no privacy: every `fn`,
`struct` and `let` is reachable. Everything is therefore *recordable*, but not
everything is *supported*:

* **Public, documented in [API.md](API.md)**: the handle types, the `Device`
  entry points, `MaterialDesc`, `Camera`, `Mat4`, the `CULL_*`/`BLEND_*`/
  `FILTER_*`/`WRAP_*`/`QUALITY_*`/`TONEMAP_*` constants, `Stats`, `MeshInfo`,
  `ImageInfo`, and the shader block contract.
* **Internal by convention**: names and struct fields prefixed `gpu_`, the
  `*Rec` records, and the helpers whose names say what they are internal to
  (`build_*`, `upload_*`, `alloc_*`, `ensure_*`, `*_index`). They can change in
  a patch release; nothing outside `src/hipgr` should call them.

Because a field reorder can silently move a uniform, the block layouts are also
recorded in `ARCHITECTURE.md` §5.3 with their exact sizes, and the backend checks
each size against its shader at push time — a mismatch is a loud error, not
corruption.

## Embedding the renderer

A host keeps its scene, its loop and its objects; HiPGR owns the GPU objects it
created and nothing else.

```goose
var dev = hipgr::Device { .. };
guard hipgr::open(dev, "host window", 1280, 720) else { return; }
defer hipgr::close(dev);

while hipgr::begin_frame(dev, cam, clear) {
    for object in scene { hipgr::draw(dev, object.mesh, object.material, object.model); }
    if !hipgr::end_frame(dev) { break; }        // false: the host should quit
}
```

* **Lifetime.** Every GPU object belongs to the `Device`; `close` sweeps whatever
  is still live, so a host never has to walk its own lists on shutdown. Handles
  are generation-checked, so a released handle is an error at the next call
  rather than a crash.
* **Threading.** `gfx` cannot be reached from a `thread_fn`, so rendering,
  upload and read-back are main-thread only. Building vertex data, decoding
  assets and generating geometry may happen on workers; the upload must not.
* **Ordering.** The host submits in any order. Culling, transparency sorting and
  batching happen inside `end_frame` (see [API.md](API.md) §Rendering), so a
  host that already sorts loses nothing and one that does not gets it for free.
* **Read the error code, not a log.** `ok(dev)`, `error_code(dev)` and
  `error_text(code)` are the contract; `backend_error()` is the backend's own
  message, for diagnostics only.

## The two known gaps

Both are recorded here because a host will hit them, not because they are
planned for a specific release.

**1. HiPGR creates its own window.** `open` asks the backend for a window and a
swapchain; there is no way to hand HiPGR a window the host already owns, and no
way to render into a host-provided native handle. Workarounds today: let HiPGR
own the window and have the host drive everything else (the demo does this), or
run HiPGR headless and blit `frame_pixels` into the host's surface — correct but
a copy per frame, which is only acceptable at low resolution or low frame rate.
Fixing it means a `open_with_native_handle` entry point and a backend that can
render into an existing swapchain: real work in `gpu.goose`, and untestable in
this repository (no display).

**2. Materials carry two `float4`s of application data — closed in 0.6.**
`MaterialDesc.user0` and `user1` reach a custom shader as `Material.user0` /
`user1`, which was not enough for a real material. 0.6 added `Material.v[8]`:
`set_material_param(dev, material, slot, value)` writes one of eight `float4`s
that the shader reads directly, pushed with the material on every draw. The
migration cost is that the `Material` block grew from 64 to 192 bytes, which is
why 0.6 is a minor version and why a shader that was not updated fails at the
push with both sizes named.

What is *not* solved by that, and is still a host limitation: the eight vectors
are fixed in number and type, so there is no growable block and no per-material
texture. A custom shader still cannot sample an image of its own — HiPGR binds no
textures for it, so `u_albedo` and friends belong to the built-in shader — and
that is the next thing a host with its own material system will want.

## Status of this document

The policy above is enforced by a script and the guides are checked by building
the consumer, so neither is aspirational: `./scripts/api_surface.sh` and
`./scripts/consumer.sh` are the evidence. The gap list is honest about what a
host cannot do yet; it is not a promise of when.
