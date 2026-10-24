# Implementation Phases

## Purpose

This document turns `PLAN.md` into ordered, independently testable phases. Progress
belongs in `DIARY.md`; enduring choices belong in `DECISIONS.md`.

## Conventions

- Phases are ordered and cumulative; a phase must not depend on later work.
- Each phase lists goal, deliverables, out of scope, dependencies, and verification.
- A phase is complete only when its verification passes via `make test` (rebuilding
  first when C code, build inputs, or embedded module sources change) and no earlier
  phase regresses.
- New module sources under `src/modules/` require a rebuild before any
  `./build/rig ...` smoke test, per `AGENTS.md`.
- No backward compatibility layer is required; old APIs are removed once in-repo
  callers are migrated.

## Phase 0 — Inventory and specification (documentation only)

**Status:** Planned

**Goal.** Freeze the async surface and the decisions before changing behavior.

**Deliverables.** `PLAN.md`, `DECISIONS.md`, `PHASES.md`, `INVENTORY.md`, `DIARY.md`
(this folder).

**Verification.** Review: every current scheduling/I/O surface is listed in
`INVENTORY.md` with a retained/reshaped/added/dropped classification and maps to a
decision.

## Phase 1 — Always assemble uv in the product path

**Status:** Done (2026-10-24)

**Goal.** Every `rig.run` sketch has a scheduler and a uv loop.

**Deliverables.**

- `sketch.run` attaches `uv.plugin` and adds `uv.loop_component` alongside the bundle's
  scheduler.
- `RuntimeApp:after_setup` populates `app.runtime` and `app.ctx` while the sketch is
  running, so callbacks can reach the loop and runtime.
- A documented way for hand-built runtimes to do the same (existing
  `uv.loop_component` / `uv.bundle_uv`).
- Tests confirming a sketch runtime exposes `uv.loop` and that `sched.active_scheduler()`
  is set (`tests/sketch_test.lua`), plus a bundle-level composition test
  (`tests/runtime_bundle_test.lua`).

**Out of scope.** Async file operations; startup hooks.

**Dependencies.** None.

**Verification.** `make test` passes (56/56); the running-sketch test observes
`app.ctx.uv` and an active scheduler.

## Phase 2 — Async startup hook

**Status:** Done (2026-10-24)

**Goal.** Let a sketch load awaitable data during startup without blocking the frame
loop.

**Deliverables.**

- `Compiled:startup(fn)` spawns `fn(ctx)` as a **background** scheduler task, with
  `startup_pending()` / `startup_stalled()` for the gate and fail-fast check.
- `app:on_start(fn)` and the `start` run option, invoked as `fn(app, sched)` from the
  class `after_setup` hook.
- **First-frame gating:** the progress engine skips `frame` handlers until the startup
  task completes (D9). Loads started after startup are ordinary coroutines and do not
  gate rendering.
- Error propagation for startup tasks; a startup that waits with no possible progress
  fails fast instead of spinning.
- Tests: startup runs and awaits, gates frames, completes without stopping the app, and
  surfaces its errors (`tests/runtime_start_test.lua`); the sketch path covers
  `start`/`on_start` ordering (`tests/sketch_test.lua`).

**Out of scope.** Async file read itself (Phase 3).

**Dependencies.** Phase 1.

**Verification.** `make test`; the startup tests await `sched.yield` and confirm
`start-end` precedes the first `frame`. A foreground keepalive was considered and
rejected: `should_stop` would stop the app the moment startup finished, so a background
task is simpler than adding an app-lifetime foreground task (D7).

## Phase 3 — uv asynchronous file operations

**Status:** Done (2026-10-24)

**Goal.** Provide the one I/O primitive the asset layer needs.

**Deliverables.**

- C: `rig_uv_fs_read`, `rig_uv_fs_write`, and `rig_uv_fs_stat` following the existing
  `rig_uv_scandir` pattern (request struct, callback, cleanup). Read opens the file and
  reads in 64 KiB chunks until EOF, then closes; write opens/truncates, writes until
  drained, then closes; stat returns size/mtime/mode/type.
- Lua: `uv.fs_read`, `uv.fs_write`, and `uv.fs_stat` as `sched.await(...)` operations,
  plus matching `uv.UvLoop` methods and loop handlers.
- Tests: read a fixture, write-then-read-back, a >1-chunk (128 KiB) round trip, stat a
  file and a directory, errors on a missing path, argument validation, a deterministic
  `sched` substitution path, and runtime-component integration
  (`tests/uv_test.lua`, `tests/runtime_uv_test.lua`).

**Out of scope.** Streaming/chunked reads (the chunked read is internal, not a public
streaming API); directory operations beyond `stat`.

**Dependencies.** Phase 1.

**Verification.** `make test`; the fs tests read, write, and stat through the
scheduler, including a file larger than the read chunk.

## Phase 4 — Single async asset API

**Status:** Done (2026-10-24)

**Goal.** Replace `asset`'s synchronous reads with the one async implementation.

**Deliverables.**

- `asset.read` (awaitable, backed by `uv.fs_read`), with `asset.text`/`asset.bytes` as
  aliases. `image`/`material`/`mesh` await their reads and decode/parse inline.
- The direct `io.open`/`rig.read_file` path is gone from `asset`.
- `sched.block(fn)` for tools and pre-loop contexts, driving the active
  `runtime.Scheduler` (timers + I/O pump) to completion; `runtime.Scheduler:block`
  records the calling script so path-relative `asset` calls resolve against it even
  though `fn` runs in a fresh coroutine. The `uv` loop component installs the pump.
- `asset` path resolution now walks past builtin (`@rig/...`) frames, so tail-calling
  an asset loader (`return asset.read(...)`) still resolves against the user script.
- Tests: `asset_test.lua` runs the loaders under the scheduler; `runtime_sched_test.lua`
  and `runtime_uv_test.lua` cover `block` (timer, uv I/O, errors, coroutine guard, and
  `asset.read` through a block).
- Examples (`shader_asset`, `post_process_common`, `textured_quad_common`) load assets
  in `start` instead of before the run.

**Out of scope.** Migrating `shader`/`font` loaders (Phase 5), which still use `io.open`.

**Dependencies.** Phase 2, Phase 3.

**Verification.** `make test`; asset tests run under the scheduler, and `block` runs
`asset.read` and `uv.fs_read` to completion.

## Phase 5 — Unify other loaders

**Status:** Done (2026-10-24)

**Goal.** Apply the single-path rule to remaining loaders where it matters.

**Deliverables.**

- `shader` no longer reads files: the `io.open` helper and the `path` option are gone,
  and `shader.compile`/`shader.create_stage` take in-memory `source`. File-backed
  shader source goes through the async asset path (`asset.text(path)`) and is then
  passed as `source` (or via `sched.block` in synchronous contexts). No in-repo caller
  used `path`.
- `font.load_face(path)` uses FreeType's own file I/O, not `io.open`; it is documented
  as synchronous setup/startup-only rather than routed through `asset` (codec work is
  out of scope).
- Remaining `io.open` use is confined to `rig.read_file`/`rig.run_script_file`
  (retained sync primitives) and the Fennel compiler, per the inventory.

**Out of scope.** Codecs and decode work (FreeType/PNG/JPEG internals).

**Dependencies.** Phase 4.

**Verification.** `make test`; `shader_test` still passes with source-only specs.

## Phase 6 — Lifecycle hardening and determinism

**Status:** Done (2026-10-24)

**Goal.** Make coroutine entrypoints, cancellation, and shutdown robust and testable.

**Deliverables.**

- Startup errors re-raise with `debug.traceback`, so the originating coroutine stack is
  attached (not just the message).
- Async tickets gained `:cancel()` and the scheduler a `:cancel_async()`. Shutdown wakes
  background tasks with `CANCELLED`, completes outstanding tickets, then drains, so late
  backend callbacks are no-ops instead of waking dead tasks. A second `:wake()`/`:fail()`
  is still an error; waking after `:cancel()` is not.
- `uv.UvLoop:release()` keeps its Lua callback closures rooted while it drains in-flight
  requests, then drops them and closes the loop.
- Deterministic `sched` substitution coverage for `uv.fs_read`/`fs_write`/`fs_stat`, and a
  cancelled-ticket test mirroring the shutdown order (`tests/sched_test.lua`,
  `tests/uv_test.lua`).
- Foreground/background/shutdown rules documented in `runtime.md` and `sched.md`.

**Out of scope.** Preemption; threads.

**Dependencies.** Phases 2–5.

**Verification.** `make test`; the startup failure case asserts a traceback is present,
and the cancellation cases assert no wake after cancel and balanced pending counts.
