# Rules for agents working on HiPGR

These are standing rules for any agent or contributor continuing this
repository. They exist because the failure modes here are specific: a rendering
library can look finished while drawing nothing, and a young language rewards
guessing with silence.

---

## 1. Verify Goose before writing Goose

Do not invent an API, a type, a builtin, a compiler flag or a memory rule. Read
`docs/` in the Goose distribution (`/opt/goose/<version>/docs/`), `stdlib/` and
`pkg/gfx/gfx.goose` for the exact signatures, then compile a five-line program
to confirm the thing you are about to rely on.

`docs/goose-notes.md` records what has already been checked, including the
traps. Read it first; it will save a compile cycle.

## 2. Compile, run, then check the pixels

A rendering feature is **not implemented** until a program compiles, runs, and
something inspects what the GPU produced. In order of strength:

1. a test that reads back pixels and asserts values (strongest);
2. a test that asserts counters/state (`Stats`, `mesh_info`, error codes);
3. a program that runs without error (weakest: it proves nothing about output).

Never describe (3) as working. Never write a screenshot-mockup into a demo.

## 3. Keep the release path green

```bash
export PATH=/opt/goose/goose-v2026.4-linux-x64:$PATH
./scripts/test.sh          # builds every test, runs it headless, asserts pixels
./scripts/bench.sh 256 60  # frame timing regression baseline
```

Before finishing any change:

* every root file passes `goose check` with **zero warnings**;
* `./scripts/test.sh` reports `0 failed` (and no unexpected `SKIP`);
* if you changed rendering behaviour, the benchmark did not regress wildly.

On a machine with no GPU device, tests print `SKIP`. That is not a pass: record
in `PROGRESS.md` that nothing was validated there.

## 4. Add a verifier with every new behaviour

New public behaviour needs a test *in the same change*. The pattern is
`tests/test_*.goose` + `tests/verify/verify.goose`; `scripts/test.sh` picks it
up by filename. If the behaviour is GPU output, assert pixels. If it is a
refusal, assert the error code **and** that the process did not abort.

## 5. The public API stays free of the backend

* Only `src/hipgr/gpu.goose` issues `gfx` calls. `device.goose` may store `gfx`
  handle values, nothing more.
* No `gfx` type, constant or function may appear in the public API.
* `scripts/test.sh` fails the build if `examples/`, `tests/` or `bench/` contain
  `import gfx;`. Do not weaken that check to make something compile — fix the
  leak.
* Applications must run with a single `import hipgr from "…";`.

## 6. Respect the memory model

* A struct with more than one growable array must be a `root struct`, and a root
  value cannot be copied, passed or returned by value: take `Device&`.
* Do not assume RAII. There are no destructors: everything the device creates,
  the device releases, and `close(dev)` must remain a complete sweep.
* Bind a growable value to a local before passing it as a slice to a function
  that may be inlined.
* Rendering is main-thread only. Do not call into `gfx` from a `thread_fn`; the
  compiler will refuse, and if you work around it you will corrupt state.

## 7. Validate before the backend

`gfx` aborts the process on misuse at the next frame. A library must not let an
application's mistake reach it:

* resolve and check every handle (zero, range, generation, liveness);
* validate geometry before upload, including every index against the vertex
  count;
* check frame state (`no frame`, `frame already open`);
* validate resource lifetimes that cross objects (material → image);
* report through `Device.last_error` and return `false`.

Add the negative test, not just the happy path.

## 8. No performance work without a measurement

* The development container has **no hardware GPU** (Mesa llvmpipe software
  Vulkan). Frame times from it are a regression baseline only.
* Do not add culling, batching, instancing, a render graph, or a job system
  before the current milestone's acceptance criteria are met and a benchmark on
  real hardware justifies the feature.
* When adding one, record before/after numbers in `PROGRESS.md` and prove output
  is unchanged (same pixels, or a documented tolerance).

## 9. Keep changes small and honest

* One feature per change; do not refactor while implementing.
* Update `PROGRESS.md` (status + evidence) in the same change.
* Update `docs/API.md` when the public surface changes.
* Add a `CHANGELOG.md` entry and bump `version()` in `src/hipgr/hipgr.goose`
  for any user-visible change.
* If something does not work, say so in `PROGRESS.md` under **Known gaps**.
  Hiding a limitation is worse than having one.

## 10. Repository hygiene

* `tmp/` is scratch; never commit it. Do not add scratch programs to
  `examples/`.
* Build outputs (`examples/triangle`, `tests/test_*`, `bench/bench_scene`) and
  `*.png` are gitignored. Do not commit binaries or screenshots.
* Never commit a `Device`, a filesystem path, or an origin that only works on
  one machine.
* Do not add a dependency without a concrete need, and pin the Goose version in
  the docs when behaviour depends on it.

## 11. Windows and Linux

Both are targets; only Linux is verified. A change that uses a shell feature, a
path separator, or a platform API must either work on both or be documented as
platform-specific in `README.md` and `RECONNAISSANCE.md`.

## 12. When in doubt

`RECONNAISSANCE.md` says what is true, `ARCHITECTURE.md` says why the design is
the way it is, and `ROADMAP.md` says what is allowed next. If a change
contradicts one of them, update the document and say why in the same change —
do not silently redesign.
