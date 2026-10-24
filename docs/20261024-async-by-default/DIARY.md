# Diary

Running log of discussion and progress. Enduring decisions live in `DECISIONS.md`;
ordered work lives in `PHASES.md`.

## 2026-10-24 — The question

While the image (with `libjpeg62-turbo-dev`) was building, the question was raised: is
it wise to make the uv scheduler a fixed component of the runtime, so that there is
only one implementation of operations like file reads (async, backed by uv) instead of
two (sync libc + async uv)? Standardizing on uv would make things simpler and would
mean the runtime executor always starts `main` as a coroutine under the uv scheduler.

## 2026-10-24 — Discussion and position

Grounded the discussion in what already exists:

- `sched` is already effectively fixed in the `rig.run` path: the `sdl3x` bundles'
  `add_core_components` always add `runtime.scheduler_component`, so `sched.await` can
  always park a coroutine.
- uv is **not** the scheduler; `uv.loop_component` *requires* `sched.scheduler` and
  installs I/O handlers on it, adding a progress `wait` handler to run the loop when
  operations are pending. So uv is a backend layered on `sched`.
- `uv` currently exposes `spawn`/`scandir`/`sleep` but **no async file read**.
- `asset` reads synchronously through `io.open`.
- `Scheduler:should_stop()` is `had_foreground and foreground_count == 0`, so a
  foreground startup coroutine that finishes would stop a class-driven app. Startups
  must be background tasks (or held by a keepalive).

Position taken:

1. Keep `sched` as the fixed abstraction and make **uv the always-assembled default
   backend** in the product path — "fixed" means always assembled, not hard-wired.
2. Always run entrypoints as coroutines: function `main` as the initial foreground
   coroutine; class/frame apps get an explicit async startup coroutine. `draw` must not
   yield.
3. Prefer **one** async I/O implementation over parallel sync/async stacks; express
   synchronous-looking use as run-to-completion on the same path (`sched.block`).
4. Make the startup phase explicit (an `on_start` hook) because `build`/registration
   runs before compile and before the loop exists.
5. Manage the real costs deliberately: coroutine error/cancel semantics, task
   lifecycle, and deterministic testing via the `sched` substitution point.
6. Reserve synchronous execution for CPU work (image decoding, math) and blocking
   last resorts.

## 2026-10-24 — Decision to write it up first

Rather than implement immediately, the work is captured here as a spec to implement
later: `PLAN.md`, `DECISIONS.md` (D1–D9), `PHASES.md` (Phases 0–6), and
`INVENTORY.md`. No code changes were made as part of this write-up.

## 2026-10-24 — Open questions resolved

- **Startup ordering (D9):** `on_start` **gates the first frame**. On-demand loads after
  startup run as ordinary coroutines and therefore do not gate rendering.
- **Keepalive vs background (D7):** a **background** startup task is sufficient now; no
  foreground keepalive.
- **Phase 3 scope (D10):** include `uv.fs_read`, `uv.fs_write`, and `uv.fs_stat`.

## 2026-10-24 — Phase 1 landed

Implemented Phase 1 (always assemble uv in the product path):

- `sketch.run` now layers `uv.plugin()` + `uv.loop_component()` onto the bundle's
  scheduler, so every `rig.run` sketch has a uv loop. No new helper was introduced;
  hand-built runtimes keep using `uv.loop_component` / `uv.bundle_uv`.
- `RuntimeApp:after_setup` sets `app.runtime` and `app.ctx` during the run (previously
  they were only assigned after `compiled:start()` returned). This lets frame
  callbacks reach the runtime (and, in Phase 2, the startup hook).
- Tests: `tests/sketch_test.lua` runs a real sketch, asserts `app.ctx.uv` is present
  and `sched.active_scheduler()` is set, then stops via `app.runtime:stop()`;
  `tests/runtime_bundle_test.lua` asserts the sdl3_gl bundle plus uv composes the uv
  binding over the scheduler. `make test` passes 56/56.

Observation for later phases: `PLAN.md`'s target sketch example passes `update` and
`draw` as top-level `rig.run` options, but the current facade only registers frame
callbacks through `build` (`app:on_update` / `app:on_draw`). Resolved for
`update`/`draw` (below); `start` remains Phase 2.

## 2026-10-24 — Top-level `update` / `draw` options

`sketch.run` now accepts `update` and `draw` directly in the options table (matching
the target UX in `PLAN.md`), as shorthand for `app:on_update` / `app:on_draw`. They
are applied after `build`, so they win over callbacks registered there. `start` stays
out until Phase 2, where it needs the first-frame gating semantics.

Tests: `tests/sketch_test.lua` runs a sketch with top-level `update`/`draw` and a
`build`-registered `on_update`, asserting the top-level callbacks run and the
`build`-registered one does not. `make test` passes 56/56.

## 2026-10-24 — Back-to-back GL runtime segfault (fixed)

Investigated the segfault found during Phase 1 test development. Reproduced with two
sequential `rig.run` sketches. Minimized it to the graphics path: two `sdl3_gl`
runtimes with a scene container; uv and the render plugin were irrelevant. Two class
runtimes *without* a scene did not crash, which pointed at the GL render path.

Root cause: `gl.lua` lazily resolves each entry point and caches it with `rawset`.
`gl.clear_resolver()` cleared only `_resolver`, leaving the resolved function pointers
cached. Those pointers are context-specific dispatch stubs; after the first runtime's
GL context is destroyed they are stale, and the second runtime reuses them. The crash
landed in `gl.Viewport` (via a dead dispatch stub). Clearing the cached cdata between
runs eliminated the crash.

Fix: `gl.set_resolver` / `gl.clear_resolver` now drop every cached cdata entry point
before changing the resolver. Regression tests:
`tests/gl_test.lua` (cache dropped on resolver change) and
`tests/runtime_graphics_test.lua` (two sequential GL runtimes both call
`gl.Viewport`). `make test` passes 56/56.

## 2026-10-24 — Phase 2 landed (async startup)

Implemented the async startup phase:

- `Compiled:startup(fn)` spawns `fn(ctx)` as a **background** scheduler task;
  `startup_pending()` tracks completion and `startup_stalled()` detects a pending
  startup with no ready work, pending async, or timer.
- `ProgressEngine:step` skips `frame` handlers while `startup_pending()`, so the first
  frame is gated on startup (D9). A stalled startup fails fast with `runtime startup task
  is waiting but no progress is pending` rather than spinning (the background-task
  equivalent of the foreground deadlock check).
- Sketch surface: `app:on_start(fn)` and the `start` run option, invoked as
  `fn(app, sched)` from `RuntimeApp:after_setup`.
- Tests: `tests/runtime_start_test.lua` covers gating/ordering, error propagation, and
  the stall guard; `tests/sketch_test.lua` covers `start`/`on_start` ordering in a real
  sketch. `make test` passes 56/56.

Considered using a **foreground** startup task: rejected. `should_stop` is
`had_foreground and foreground_count == 0`, so a foreground startup would stop the app
the instant it finished unless a foreground keepalive for the whole app lifetime is
added — strictly more machinery than a background task, and it would not remove the
first-frame gate. Background startup plus the stall guard keeps the rule simple.

## 2026-10-24 — Phase 3 landed (async file I/O)

Implemented the async file surface:

- C (`uv.c`): `rig_uv_fs_read` opens the file, reads 64 KiB chunks until EOF, and
  closes; `rig_uv_fs_write` opens/truncates, writes until drained in a loop, and closes;
  `rig_uv_fs_stat` surfaces size/mtime/mode and file/dir/symlink flags. All reuse the
  request-struct + `uv_fs_*` callback + `uv_fs_req_cleanup` pattern from `scandir`.
  `uv_buf_init` is an external libuv symbol, so `uv_buf_t` is built inline.
- Lua (`uv.lua`): `uv.fs_read` / `uv.fs_write` / `uv.fs_stat` as `sched.await`
  operations, with `uv.UvLoop` methods and loop handlers.
- Tests (`uv_test.lua`, `runtime_uv_test.lua`): fixture read, write/read-back,
  128 KiB round trip (multi-chunk), file and directory stat, missing-path errors,
  argument validation, a manual-scheduler substitution path (D8), and runtime-component
  integration. `make test` passes 56/56.

## 2026-10-24 — Phase 4 landed (single async asset API)

`asset` now reads through `uv.fs_read`: `asset.read` is the awaitable entry point and
`asset.text`/`asset.bytes` are aliases; `image`/`material`/`mesh` await their reads and
decode/parse inline. The `io.open`/`rig.read_file` path is gone from `asset`. Examples
load assets in the sketch `start` hook instead of before the run.

Added `sched.block(fn)` for synchronous pre-loop contexts. It delegates to the active
`runtime.Scheduler`, which advances timers and pumps I/O (the `uv` loop component
installs the pump) until the function completes. Because `fn` runs in a fresh
coroutine, its caller frame is absent, so the blocking driver records the calling
script and `asset` uses it for relative path resolution.

Path resolution in `asset` now walks up past builtin `@rig/...` frames instead of using
a fixed stack depth. This fixes a latent issue: `return asset.read(...)` is a tail call
that removed the caller's frame, so the old depth-3 lookup resolved against the wrong
directory. (The new `sched.block` case made it visible.)

Tests: `asset_test.lua` (loaders under the scheduler), `runtime_sched_test.lua` and
`runtime_uv_test.lua` (`block` with timers, uv I/O, error propagation, the coroutine
guard, and `asset.read` through a block). `make test` passes 56/56.

## 2026-10-24 — Phase 5 landed, and the audio flake fixed

Phase 5 removed the `io.open` path from `shader`: `shader.compile`/`create_stage` now
require an in-memory `source`, and file-backed source goes through `asset.text`. No
in-repo caller used `path`. `font.load_face` uses FreeType's own file I/O and is
documented as synchronous setup/startup-only (codec work is out of scope). Remaining
`io.open` is confined to `rig.read_file`/`rig.run_script_file` and the Fennel compiler.

While verifying, the `audio_test.lua` flake (previously noted here) got frequent enough
to investigate. The test cases all passed; the *process* segfaulted. Backtrace showed a
thread in SDL's PipeWire backend (`SDLPwAudioPlug` ->
`libpipewire-module-protocol-native`). Under concurrent test processes, initializing
the real audio server races and crashes, and the missing-file case called
`ensure_audio` just to discover the file was missing.

Fixes:
- `ctest` now runs with `SDL_AUDIO_DRIVER=dummy` / `SDL_AUDIODRIVER=dummy`, matching the
  existing offscreen video hints, so tests never attach to a real sound server.
- `audio.load` resolves the path and checks the cache first, and returns a missing-file
  error without initializing the audio subsystem.

`make test` passes 56/56 across repeated runs; the flake no longer reproduces.

## 2026-10-24 — Phase 6 landed (lifecycle hardening)

- Startup tasks now run under `xpcall(..., debug.traceback)` and re-raise the traceback,
  so startup failures carry the originating coroutine stack.
- `AsyncTicket:cancel()` completes a ticket without waking its task; `scheduler:cancel_async()`
  cancels all outstanding tickets. Shutdown now cancels background tasks, completes
  tickets, then drains. Late `uv` callbacks therefore find a cancelled ticket and no-op
  instead of waking an already-completed task. Double completion is still an error.
- `uv.UvLoop:release()` no longer clears `_callbacks` before draining: it keeps the Lua
  callback closures rooted while `uv_run_nowait` finishes in-flight requests, then drops
  them and closes the loop. Previously a completed callback could be invoked after its
  closure was collectable.
- Determinism: the `uv.fs_read` substitution test now stubs all three fs ops, and a new
  `sched_test` case mirrors the shutdown order (cancel ticket, wake task with the
  sentinel, drain, late wake is a no-op).
- Foreground/background/shutdown rules documented in `runtime.md` and `sched.md`.

All phases 0–6 are now done. `make test` passes 56/56 (repeatedly, after the audio-driver
fix from the previous entry).

## Open questions

- None blocking. Implementation may surface ordering details once gating is wired into
  the progress engine.
