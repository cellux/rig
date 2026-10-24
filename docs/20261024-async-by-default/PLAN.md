# Rig Async by Default

## Purpose

This document plans standardizing Rig's runtime on a single scheduling model: a
cooperative scheduler is always present, `libuv` is the default I/O backend, and the
program's entry points run as coroutines so asynchronous operations are available
everywhere. It records the intended architecture, the alternatives considered, and the
migration strategy before implementation begins.

## Goal

1. The runtime **always** assembles a scheduler; `uv` is the **default** I/O backend.
2. The program's entry point(s) run as **coroutines** under that scheduler.
3. There is **one** asynchronous I/O API. No parallel sync/async implementations of the
   same operation.
4. `sched` remains the abstraction; `uv` stays behind it, so tests and tools can
   substitute a deterministic scheduler.
5. Startup is an explicit, async-capable phase.

## Background and current state

The pieces already exist; the goal is to remove optionality and duplication.

- **`sched`** is a generic cooperative scheduler (`sched.spawn`, `sched.await`,
  `sched.join`, `sched.park`, `sched.sleep`; a process-wide `_active_scheduler`).
- **`runtime.scheduler_component`** provides `sched.scheduler` (a pure-Lua `Scheduler`
  wrapping an inner scheduler, requiring a clock and timer). The `sdl3x` bundles'
  `add_core_components` always add it, so **a scheduler is already effectively fixed**
  in the `rig.run` path.
- **`uv.loop_component`** provides `uv.loop`, **requires `sched.scheduler`**, installs
  I/O handlers on it, and adds a progress `wait` handler that runs the uv loop when
  operations are pending. So uv is a backend *layered on top of* `sched`, not a
  scheduler itself.
- **`uv.bundle_uv`** assembles scheduler + uv; **`rig.run` currently does not add uv.**
- **`uv` exposes** `spawn`, `scandir`, `sleep`, `now`, `monotonic` — but **no async
  file read/write**.
- **`asset` reads files synchronously** through `rig.read_file` (`io.open`).
- **Termination:** `Scheduler:should_stop()` returns `had_foreground and
  foreground_count == 0`. Spawning a foreground coroutine that later finishes will
  therefore stop a class-driven app unless another foreground task remains. Background
  tasks do not set `had_foreground`.

## Design principles

- **One execution model.** Scheduler composition selects coroutine semantics; there
  is no second "sync" execution path in the product.
- **`sched` is the contract; `uv` is the default implementation.** Core code never
  calls libuv directly; it awaits `sched` operations that uv fulfils.
- **Async for I/O, sync for CPU.** Decoding, math, and other CPU-bound work stay
  synchronous; only inherently blocking I/O moves to the async path.
- **No duplicate operation stacks.** A synchronous-looking API, where needed, is
  "run the async path to completion", not a second libc implementation.
- **Startup is explicit.** Registration is declarative; I/O happens in a defined async
  phase, never silently before the loop exists.
- **Deterministic tests.** A manual/deterministic scheduler must remain substitutable.

## Target user experience

The code-first sketch path gains uv automatically and exposes an async startup hook:

```lua
rig.run {
   title = "Streaming",
   build = function(app)
      -- declarative registration only; no I/O that needs awaiting
      app:add_entity { mesh = ..., motion = ... }
   end,
   start = function(app, sched)          -- or app:on_start(fn)
      local bytes = sched.await("uv.fs_read", "assets/big.bin")
      app:add_entity { mesh = mesh_from_bytes(bytes) }
   end,
   update = function(app, frame) end,
   draw = function(app, frame) end,
}
```

Hand-built runtimes opt in the same way, using `uv.loop_component` beside the
scheduler.

## Architecture

### Layers

```
rig.run / app hooks        registration (sync) + async startup + frame callbacks
        |
runtime builder/compiler   assembles scheduler + uv.loop always (product path)
        |
sched                      cooperative scheduling, await/park/timers (the contract)
        |
uv                         libuv event loop: the default I/O backend
        |
libc                        only for CPU work and last-resort blocking paths
```

### Entry points and coroutines

There are two candidate entrypoint shapes; the plan must pick one and apply it
uniformly.

- **Function entrypoint**: with a scheduler present, `main(ctx)` is spawned as the
  initial foreground coroutine (this is already the 2026-10-23 design). This is the
  natural "always a coroutine" case.
- **Class entrypoint** (used by `rig.run` via `sdl3x.App`): there is no single `main`;
  the frame loop is driven by the progress engine and lifecycle hooks. For this shape,
  the async story is an explicit startup coroutine plus coroutine-capable update
  hooks, not a coroutine `main`.

The plan standardizes on: **the scheduler is always present and uv always assembled;
function entrypoints are foreground coroutines; class/frame apps get an explicit async
startup task and may spawn coroutines from `update`.** `draw` never yields.

### One I/O API

`asset` (and later `shader`, `font`) should expose awaitable operations backed by uv.
The async file surface is **read, write, and stat**:

```lua
local text = asset.read("notes.txt")          -- awaits uv.fs_read
local image = asset.image("logo.png")          -- await read, then sync decode
```

A synchronous context (tools, tests, pre-loop) uses a block helper that runs the same
operation to completion on the loop:

```lua
local bytes = sched.block(function() return asset.read("data.bin") end)
```

No second `io.open`-based implementation of `asset.read` is maintained.

### Startup phase

`build`/registration runs before compile and stays I/O-free. Awaitable loading happens
after startup in an explicit `on_start` hook spawned onto the scheduler. **`on_start`
gates the first frame**: the frame loop does not produce a frame until the startup
coroutine completes. Loads started after startup (on demand) are ordinary coroutines
and therefore do not gate rendering.

### Termination and tasks

Because `Scheduler:should_stop()` is `had_foreground and foreground_count == 0`:

- the startup coroutine is spawned **background**, so finishing it does not stop the
  app; a foreground keepalive is not needed for now;
- frame loops (class-driven) stay alive via their own `progress` and input
  `should_stop`, not via the scheduler.

This interaction is a required part of the implementation, not an afterthought.

## Scope

**In scope.** Always-assembled uv; coroutine entrypoints/async startup; `uv` async file
operations; one awaitable `asset` API; error/cancel/shutdown semantics; deterministic
scheduler for tests.

**Out of scope.** Threads/preemption; networking; a second non-uv I/O backend; async
CPU decoding.

## Relationship to earlier work

Continues `20261023-redesign` (scheduler-composition-selects-semantics, foreground/
background rules) and `20261024-demo-engine` (the code-first `rig.run` facade and
`asset`). It resolves the open question left in that work: whether sync and async I/O
should coexist. This plan says no — async-first, behind `sched`, with uv as the fixed
default backend.
