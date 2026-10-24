# Design Decisions

## Purpose

This document records the decisions that shape the async-by-default work. Decisions
remain in force until explicitly superseded. Progress belongs in `DIARY.md`; ordered
work belongs in `PHASES.md`.

## Status key

- **Accepted** — in force.
- **Superseded by Dn** — retained for history, no longer in force.
- **Proposed** — under review, not yet binding.

---

## D1 — The runtime always assembles a scheduler

**Status:** Accepted (2026-10-24, Phase 1)

Every runtime the product starts (the `rig.run` path and the `sdl3x`/`uv` bundles)
assembles a cooperative scheduler. The scheduler is no longer an optional layer; every
program has one, so coroutine-based `await` is always meaningful. `sched` is the only
scheduling contract; components depend on it, not on a concrete backend.

## D2 — uv is the default I/O backend, behind `sched`

**Status:** Accepted (2026-10-24, Phase 1)

`libuv` is assembled by default and remains the event loop that fulfils asynchronous
operations. It stays behind the `sched` abstraction: core and product code call
`sched.await(...)`, and only `uv.lua`/`uv.c` talk to libuv. A deterministic/manual
scheduler must remain substitutable for tests and tools. "uv is fixed" means "always
assembled by default", not "hard-wired into core".

## D3 — Entry points run as coroutines

**Status:** Accepted (2026-10-24, Phases 2/6)

Function execution runs `main(ctx)` as the initial foreground coroutine (as already
specified in the 2026-10-23 redesign). Class/frame-based execution (used by `rig.run`)
keeps the progress-engine frame loop and gains an explicit async startup coroutine;
`update` may spawn coroutines, `draw` must not yield.

## D4 — An explicit async startup phase

**Status:** Accepted (2026-10-24, Phase 2)

`build`/registration remains declarative and I/O-free, running before compile. Awaitable
loading happens in a defined startup phase after resources exist, exposed as an
`on_start` hook (or `start` option) spawned onto the scheduler. No API silently allows
`await` before the loop exists.

## D5 — One I/O API, async-first

**Status:** Accepted (2026-10-24, Phases 3–5)

There is one implementation of each I/O operation, asynchronous and backed by uv.
Synchronous-looking use is "run the async path to completion" through a block helper,
never a second `io.open`/libc implementation. This avoids divergent path, encoding, and
error behavior, and halves the test surface.

## D6 — Async for I/O, sync for CPU

**Status:** Accepted (2026-10-24, Phases 3–5)

Only inherently blocking I/O moves to the scheduler. Decoding (PNG/JPEG), math, and
other CPU-bound work stays synchronous; `asset` reads awaitably, then decodes inline.
CPU-bound work must not be wrapped in fake async.

## D7 — Task lifecycle is explicit

**Status:** Accepted (2026-10-24)

Because `Scheduler:should_stop()` is `had_foreground and foreground_count == 0`, the
async startup coroutine is spawned **background**, so finishing it does not stop the
runtime. A foreground keepalive is not needed for now. Frame loops (class-driven) stay
alive through their own `progress` and input `should_stop`, not through the scheduler.
Shutdown cancels background tasks and allows cleanup before resource teardown. Errors
from scheduler tasks must surface with the originating stack and must not be swallowed
by the progress engine.

## D8 — Determinism is preserved through the abstraction

**Status:** Accepted (2026-10-24, Phases 3/6)

Because components depend on `sched` and not on uv directly, tests can run against a
manual/deterministic scheduler and completion model. Any new async operation must be
expressible as a `sched` operation with a substitutable implementation.

## D9 — `on_start` gates the first frame

**Status:** Accepted (2026-10-24)

The async startup coroutine gates frame production: the first frame is not produced
until `on_start` completes. Later, on-demand loads are ordinary coroutines and
therefore do **not** gate rendering — starting a load after startup does not stop
frames.

## D10 — The async file surface is read, write, and stat

**Status:** Accepted (2026-10-24)

Phase 3 provides `uv.fs_read`, `uv.fs_write`, and `uv.fs_stat` as `sched` operations
(backed by `rig_uv_fs_read`/`write`/`stat` in C). Read is needed by `asset`; write and
stat are needed for caching and hot reload and are added alongside rather than
retrofitted later.
