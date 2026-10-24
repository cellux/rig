# Inventory

## Purpose

Freeze the scheduling/I/O surface affected by the async-by-default work and classify
each entry as **retained**, **reshaped**, **added**, or **dropped**. Search scope:
`src/`, `tests/`, `examples/`, `scripts/` (not `src/` alone), per `AGENTS.md`.

## Scheduling

| Surface | Classification | Rationale |
|---|---|---|
| `sched` (`spawn`, `await`, `join`, `park`, `sleep`, `active_scheduler`) | **Retained** | The scheduling contract; the thing everything else targets. |
| `runtime.scheduler_plugin` / `scheduler_component` (`sched.scheduler`) | **Retained** | Already assembled by `sdl3x` bundles; becomes guaranteed in the product path. |
| `uv.plugin` / `uv.loop_component` (`uv.loop`) | **Retained** | The I/O backend; becomes always assembled by `rig.run`. |
| `uv.bundle_uv` | **Retained** | Convenience assembly for hand-built runtimes. |
| `M.Scheduler:should_stop` (`had_foreground and foreground_count == 0`) | **Retained** | Constrains how startup tasks are spawned (D7). |
| Function execution (`main` as initial foreground coroutine) | **Retained** | Already the design; unchanged. |
| Class execution (`sdl3x.App`) | **Reshaped** | Gains an async startup task; frame loop otherwise unchanged. |
| Deterministic/manual scheduler for tests | **Retained** | The substitution point that keeps D8 true. |

## uv operations

| Surface | Classification | Rationale |
|---|---|---|
| `uv.spawn` (captured process) | **Retained** | Existing async operation. |
| `uv.scandir` | **Retained** | Existing async operation; the C pattern for new fs ops. |
| `uv.sleep` / `uv.now` / `uv.monotonic` | **Retained** | Existing timer/clock operations. |
| `uv.fs_read` / `uv.fs_write` / `uv.fs_stat` | **Added** | Async file surface (D10): read for `asset`, write/stat for caching and hot reload. |
| `rig_uv_fs_read` / `rig_uv_fs_write` / `rig_uv_fs_stat` (`uv.c`) | **Added** | C side of the above, mirroring `rig_uv_scandir`. |

## Facade and asset

| Surface | Classification | Rationale |
|---|---|---|
| `rig.run` (sketch) | **Reshaped** | Assembles uv and exposes the async startup hook. |
| `sketch.App` callbacks (`on_update`/`on_draw`/input) | **Reshaped** | Adds `on_start`; documents that `draw` must not yield. |
| `asset.text` / `bytes` / `image` / `material` | **Reshaped** | Re-expressed on one awaitable `asset.read`. |
| `asset.read` (awaitable) | **Added** | The single I/O entry point (D5). |
| `sched.block(fn)` (run-to-completion helper) | **Added** | Synchronous-looking use without a second implementation. |
| `rig.read_file` / `rig.file_exists` | **Retained** | Sync primitives for CPU/tools and last-resort blocking paths. |
| `io.open` reads inside `asset` | **Dropped** | Replaced by the async path (D5). |

## Consumers

| Surface | Classification | Rationale |
|---|---|---|
| `animator.App` foreground drive tasks | **Retained** | Keeps the runtime alive; unaffected. |
| `profiler` / `stat` scheduler use | **Retained** | Read-only use of `sched`. |
| `uv.bundle_uv` in tests (`scripts/run_all_tests.lua`) | **Retained** | Tests already run under uv; new ops join them. |

## Out of scope

Threads/preemption, networking, a non-uv I/O backend, and async CPU decoding are not
part of this inventory.
