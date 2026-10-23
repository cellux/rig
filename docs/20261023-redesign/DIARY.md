# Implementation Diary

## Purpose

This document is an append-only timestamped record of completed implementation work,
discoveries, and resolved decisions. Earlier entries must not be edited. Pending work
is tracked in a single `HANDOFF` section at the end of this file and updated before
each context flush.

---

## 2026-10-23 — Phase planning and design freeze

**Done**

- Read and accepted `PLAN.md` as the milestone specification.
- Wrote `PHASES.md`: 14 ordered phases (0–13), each with goal, deliverables, out of
  scope, dependencies, and verification. Foundations (builder, capability graph,
  lifecycle, resource ownership) precede backend migration; bundles and deletion of
  the old model come last.
- Wrote `DECISIONS.md`: D1–D17 recording the enduring decisions implied by `PLAN.md`,
  including the decision to keep the old runtime model alive until Phase 13.
- Confirmed the repository builds and `make test` passes (30/30) before starting
  design work, after removing 48 constants absent from the installed HarfBuzz and
  SDL3 3.2.10 headers (`harfbuzz.c`, `sdl3.c`).

**Discoveries from reading the current implementation**

- `src/modules/rig.lua` (~760 lines) holds the entire old runtime model:
  `ServiceRegistry`, `ResourceScope`, `App`, `Runtime`, runtime-driver/preset/hook
  registries, and `rig.run`. This is the primary deletion target and the primary
  behavior-reference for the new builder/compiler/runtime.
- `rig.run` already contains a `ResourceScope` and reverse-order release, but release
  is per-component (drivers/app) rather than a single runtime ownership graph, and
  startup failures are not rolled back uniformly.
- The four `sdl3x` drivers (`sdl3`, `sdl3_gl`, `sdl3_gpu`) share an identical loop
  shape (poll → drain → frame) and differ only in setup + frame function. This is the
  clearest evidence for a composable input source + scheduler + presentation split.
- `uv.lua` mixes component concerns in module globals (`M._loop`, `M._scheduler`,
  callback registries). The new model must move these into runtime-scoped instances.
- `sched` already has the task/async-ticket machinery needed for Phase 5; the redesign
  mainly re-homes scheduler ownership and its sleep backend.
- `time.lua` is a thin wrapper over the `time` service and is a direct Phase 11
  capability-conversion target.
- `sdl3x.App`/`SceneApp` carry both component behavior (vsync/fullscreen/profile) and
  user app wiring. Phase 10 should split the component behavior out of the base class.
- Existing `rig.App` lifecycle methods (`after_setup`, `before_drain`, `before_frame`,
  `before_shutdown`) map onto the new extension-point contracts (Phase 6).

**Not done**

- `INVENTORY.md` (Phase 0) is not started; the phase plan is the deliverable for today.

---

## 2026-10-23 — Phase 0 complete: current API and behavior inventory

**Done**

- Wrote `INVENTORY.md`: a classification (Retained / Reshaped / Deferred / Dropped) of
  every current public knob and runtime behavior, organized as:
  1. runtime-level knobs,
  2. `rig.run` lifecycle and driver phases,
  3. execution and scheduling behavior,
  4. time and event behavior,
  5. window and graphics behavior,
  6. ordinary module/resource knobs,
  7. tests/examples/scripts,
  8. deferred work.
- Searched `src/`, `tests/`, `examples/`, and `scripts/`; included every in-repo
  `rig.run` call site, `register_runtime_driver`/`register_runtime_preset` site, and
  service definition/provider.
- Added a coverage check against the `PLAN.md` inventory checklist and four follow-up
  verification checkpoints to re-validate during later phases.

**Discoveries recorded in `INVENTORY.md`**

- `mode`, `driver`, `providers`, and `rig.run` itself are all Dropped (Phase 12–13);
  `module_config`/`driver_config` are Reshaped into component options.
- The `time`, `font.renderer`, `mesh.vertex_input`, `gl.resolver`, and `shader.stage`
  services all dissolve into capabilities (Phase 11).
- `sched` is largely Retained; only scheduler ownership and the sleep backend move.
- `sdl3x` module-global accessors (`get_window`/`get_renderer`/`get_gpu_device`/
  `get_gl_context`) become `ctx` bindings; the pure builder helpers and owning wrappers
  (`Properties`, `Window`, `GPUShader`) are Retained.
- Pure libraries (`dxc`, `shaderc`, `shadercross`, `spirvcross`, `stat`, `profiler`,
  `scenegraph`) are Retained; only their runtime wiring changes.
- The test suite's fake service providers/drivers are Dropped in Phase 13 in favor of
  headless/fake components.

**Follow-ups flagged (not blockers)**

- Confirm nothing outside `uv`/`test`/`scripts` uses `uv.get_loop`/`uv.stop` before
  Phase 7.
- Confirm no example depends on exact `driver_config` key names after Phase 8–10.
- Confirm `sdl3x` accessors are unreferenced after Phase 11.
- Confirm no test depends on `rig.run` validation error strings after Phase 13.

---

## 2026-10-23 — Phase 1 complete: plugin, builder, and descriptor core

**Done**

- Added `src/modules/runtime.lua` (registered in `src/modules/modules.txt` after
  `rig`):
  - `runtime.plugin(spec)` validates a plugin value (`id` required, known namespace
    fields must be tables if present) and returns it.
  - `runtime.descriptor(plugin, spec)` copies `spec` and tags the descriptor with its
    originating plugin.
  - `runtime.Builder` with `state`, `:use`, `:add`, `:on`, `:execute`, and `:compile`.
  - `runtime.Compiled` snapshot with `state = "compiled"`, `plugins`, `descriptors`,
    `handlers`, and `execution`.
- Added `rig.runtime()` in `src/modules/rig.lua`; it lazily `require`s the `runtime`
  module so there is no load-order dependency.
- Added `src/modules/runtime.md` documenting the new API.
- Added `tests/runtime_test.lua` with 12 cases covering fresh builders, plugin and
  descriptor validation, duplicate attach by identity and id, unattached descriptors,
  handler/execution validation, compile snapshotting, post-compile freeze, and
  side-effect-free compilation.

**Behavior implemented**

- `:use` rejects duplicate plugin values and duplicate plugin ids.
- `:add` rejects non-tables, descriptors without a plugin, descriptors from
  unattached plugins, and empty `name` values.
- `:on` rejects empty names and non-function handlers.
- `:execute` accepts only a function or `rig.Class` and only once.
- `:compile` snapshots the builder into `runtime.Compiled` and transitions the builder
  to `"compiled"`; all further mutation and re-compilation error.
- Compilation acquires no resources and invokes no plugin constructors.

**Verification**

- `make` rebuilt the embedded `runtime` module and linked cleanly.
- `make test`: 31 files passed, 0 failed (was 30; new `tests/runtime_test.lua` has
  12/12 passing).

**Notes for later phases**

- Execution-form inference and rejection of missing/mixed execution are intentionally
  **not** implemented yet; Phase 3 owns them.
- Capability resolution, dependency ordering, and `ctx` binding validation are Phase 2.
- `runtime.Compiled` currently only snapshots; `:start()` and the state machine are
  Phase 3.

---

## 2026-10-23 — Phase 2 complete: capability and dependency-graph compilation

**Done**

- Extended `src/modules/runtime.lua` with compile-time capability resolution, dependency
  ordering, context binding validation, extension-point validation, config schema
  validation, and plan lowering.
- Strengthened `runtime.plugin` validation for `capabilities` and `extension_points`
  declarations.
- Added `tests/runtime_compile_test.lua` with 17 cases.
- Updated the Phase 1 compile test to declare its extension point (the new Phase 2
  validation rejects unknown extension points).
- Documented capabilities, descriptors, extension points, and `compiled.plan` in
  `src/modules/runtime.md`.

**Behavior implemented**

- Capabilities are declared per plugin and referenced by `provides`/`requires`; unknown
  references are compile errors.
- Requirement selection: declarative `properties` equality, then an optional pure
  `predicate(descriptor)`, then highest `priority`; equal top priority is a tie error.
- Distinct errors for absent provider (no component provides the capability) vs
  constraint conflict (providers exist but none match).
- Optional requirements may remain unresolved.
- `excludes` rejects unsupported capability combinations.
- `config` is validated through `config_schema` and normalized into the plan.
- Topological order is provider-first and deterministic (stable by descriptor order),
  with cycle detection.
- Duplicate context binding names, unknown extension points, single-cardinality
  handler overflow, and core-namespace redeclaration are all rejected.
- Compile failure leaves the builder `"building"` so it can be corrected and recompiled.

**Deliberate boundary choices (recorded in `DECISIONS.md` as D19)**

- A component is excluded from its own requirement candidates (a self-cycle would
  otherwise be an immediate cycle error).
- `provides`/`requires` must reference capabilities declared by an attached plugin.
- Extension-point `payload` is accepted as a schema-like table but not deeply applied
  yet; that belongs to dispatch in Phase 6.

**Verification**

- `make` rebuilt the embedded `runtime` module and linked cleanly.
- `make test`: 32 files passed, 0 failed (new `tests/runtime_compile_test.lua`: 17/17).

---

## 2026-10-23 — Phase 3 complete: lifecycle, execution forms, progress engine

**Done**

- Extended `src/modules/runtime.lua`:
  - execution selection (`function` / `class` / `hooks`) with compile-time rejection of
    missing execution and of mixing handlers with `:execute`;
  - runtime state machine on `runtime.Compiled`: `compiled` -> `starting` -> `running` ->
    `stopping` -> `stopped`, with `failed` on startup/run error and `compiled.error`;
  - `compiled:stop()` (running only) and `compiled:start()` (compiled only);
  - `ctx` construction and component instantiation via `descriptor.create(context)` in
    `plan.order`;
  - `runtime.ProgressEngine` with per-component `descriptor.progress` operations
    (`poll`, `drain`, `frame`, `should_stop`) and a step context.
  - `builder:has_execution()` / `builder:has_handlers()` introspection.
- Added `tests/runtime_start_test.lua` with 13 cases.
- Updated Phase 1/2 tests for the new execution-configuration rules.
- Documented execution forms, lifecycle, context creation, and the progress engine in
  `src/modules/runtime.md`.

**Behavior implemented**

- Function execution calls `main(ctx)` once; returning stops the runtime.
- Class execution constructs the class with `ctx` into `compiled.instance`.
- Hook execution is inferred from `:on(...)` registrations and runs the engine until
  stopped.
- Direct function execution does not enter the engine loop.
- Startup/run failures transition to `failed` and re-raise the original error.
- Double start, start after `stopped`/`failed`, and `stop()` outside `running` are
  rejected.
- Components may request stop via `context.runtime:stop()`; `should_stop` and
  `progress.*` are validated at compile time.

**Deliberate boundary choices (recorded as D20)**

- `descriptor.create` is the Phase 3 in-memory instantiation hook; resource ownership,
  rollback, and release are Phase 4.
- The progress engine is a built-in skeleton. Handler dispatch for hooks and class
  lifecycle methods is **not** performed yet; that is Phase 6.
- `wait`/`deadline` operations are reserved but unused until the scheduler/timer phases.

**Verification**

- `make` rebuilt the embedded `runtime` module and linked cleanly.
- `make test`: 33 files passed, 0 failed (new `tests/runtime_start_test.lua`: 13/13;
  `runtime_compile_test.lua` 17/17; `runtime_test.lua` 12/12).

---

## 2026-10-23 — Phase 4 complete: resource ownership and rollback

**Done**

- Added `runtime.ResourceScope` and `format_cleanup_errors` to `src/modules/runtime.lua`.
- Every `runtime.Compiled` now owns `compiled.resources`.
- Component instantiation adopts resources:
  - `context.adopt(resource, release_fn)` for extra resources;
  - `descriptor.release(value)` auto-adopted when `create` returns a non-nil value.
- `descriptor.create` / `descriptor.release` types are validated at compile time.
- `compiled:start()` now releases resources in reverse acquisition order on both
  success and failure, aggregating cleanup errors and continuing past them.
- Startup failure rolls back partial resources and combines the component-labelled
  startup error with any cleanup errors.
- Added `tests/runtime_resource_test.lua` with 8 cases.
- Documented resource ownership in `src/modules/runtime.md`.

**Behavior implemented**

- Reverse-order release across components and within a component.
- Idempotent, error-aggregating `ResourceScope:release()`.
- Startup error text becomes
  `runtime component '<label>' failed during startup: <error>`, satisfying the
  requirement that startup failures identify the failing component.
- Cleanup failure on normal shutdown transitions the runtime to `failed` with
  `runtime cleanup failed with N error(s): ...`.

**Verification**

- `make` rebuilt the embedded `runtime` module and linked cleanly.
- `make test`: 34 files passed, 0 failed (new `tests/runtime_resource_test.lua`: 8/8).

---

## 2026-10-23 — Phase 5 complete: clock, scheduler, and timers

**Done**

- Added to `src/modules/runtime.lua`:
  - `runtime.Clock` (function-backed) and `runtime.ManualClock` (deterministic);
  - `runtime.Timer` (one-shot deadline queue);
  - `runtime.Scheduler` wrapping `sched.Scheduler` with foreground/background task
    tracking, sleep via the timer, deadlock detection, cancellation, and shutdown;
  - `runtime.CANCELLED` sentinel;
  - component helpers `runtime.scheduler_plugin`, `runtime.clock_component`,
    `runtime.timer_component`, and `runtime.scheduler_component`.
- `runtime.Compiled` now detects `sched.clock` / `sched.timer` / `sched.scheduler`
  providers, activates the scheduler, spawns function execution as a coroutine when a
  scheduler is assembled, and shuts the scheduler down (cancelling background tasks)
  before resource release.
- Added a `wait` step to `runtime.ProgressEngine`.
- Added `tests/runtime_sched_test.lua` with 10 cases.
- Documented the scheduler components in `src/modules/runtime.md`.

**Behavior implemented**

- Function `:execute(fn)` becomes a foreground coroutine when a scheduler is present;
  returning from it ends the runtime.
- `scheduler:sleep` is implemented through the timer capability.
- Foreground tasks keep the runtime alive; background tasks do not.
- On shutdown, background tasks are woken with `runtime.CANCELLED` and drained once to
  allow cleanup.
- Foreground deadlock raises `runtime scheduler deadlocked: ...` and fails the runtime.
- Scheduler/clock/timer compatibility is enforced at compile time via capability
  properties (`protocol = "sched"`).

**Deliberate boundary choices (recorded as D22)**

- The scheduler reuses `sched.Scheduler` (retained per the inventory) and activates it
  for the runtime's duration; runtime-scoped ownership is carried by
  `runtime.Scheduler`.
- The `wait` operation advances a `ManualClock` to the next deadline; a real blocking
  wait is the responsibility of backend clock components (Phases 7/8).
- Cancellation is best-effort: tasks are resumed with `runtime.CANCELLED`; LuaJIT has no
  coroutine error injection, so tasks that ignore the sentinel are dropped.

**Verification**

- `make` rebuilt the embedded `runtime` module and linked cleanly.
- `make test`: 35 files passed, 0 failed (new `tests/runtime_sched_test.lua`: 10/10).

---

## 2026-10-23 — Phase 6 complete: events, extension points, dispatch, class adapter

**Done**

- Extended `src/modules/runtime.lua`:
  - shared `validate_extension_point_declaration` (cardinality, order, method, payload
    schema);
  - core extension points now carry class method mappings;
  - compile-time `class_methods` map with duplicate/clash validation and
    `event_sources` validation;
  - `compiled:emit(name, payload)`, `_emit_phase`, and payload schema validation;
  - automatic core lifecycle emission in `_run` / `_teardown`;
  - progress engine invokes event source `poll` each step and passes `emit` in the
    step context.
- Added `tests/runtime_event_test.lua` with 11 cases.
- Documented declarations, dispatch, lifecycle emission, and event sources in
  `src/modules/runtime.md`.

**Behavior implemented**

- `builder:on(...)` handlers are now invoked: `core.before_setup`, `core.after_setup`,
  `core.before_shutdown`, `core.after_shutdown`, and plugin events.
- `order = "reverse"` dispatches handlers in reverse registration order.
- Payload schemas are validated on emit, and unknown extension points are rejected.
- Class execution constructs the instance before `core.after_setup` and dispatches
  declared class methods for lifecycle and plugin events.
- Duplicate method mappings and mappings to reserved `init`/`super` are compile errors.
- Event sources declare the events they may emit and poll each step; unknown declared
  events are compile errors.
- `compiled:emit` is public for direct event injection in tests and components.

**Deliberate boundary choices (recorded as D23)**

- Handlers receive a single payload/context value rather than positional arguments.
  Core phases pass `{ runtime, ctx }`; plugin payloads are whatever the emitter sends.
- Only `registration` and `reverse` ordering are supported initially; advanced
  fan-out/ordering policy remains deferred.
- Event sources are polled before component progress operations in each engine step.

**Verification**

- `make` rebuilt the embedded `runtime` module and linked cleanly.
- `make test`: 36 files passed, 0 failed (new `tests/runtime_event_test.lua`: 11/11).

---

## 2026-10-23 — Phase 7 complete: uv as composable components

**Done**

- Added composable components to `src/modules/uv.lua` (`runtime` is now required there):
  - `uv.plugin`, `uv.clock_component`, `uv.loop_component`, and `uv.UvLoop`;
  - loop-scoped `spawn`/`scandir` handlers installed on the runtime scheduler;
  - a loop-scoped `wait` progress operation that runs the uv loop while async work is
    pending;
  - loop teardown through `descriptor.release`.
- `src/modules/runtime.lua` now exposes `context.runtime` to component `create` and
  records `compiled.capability_values` (capability id -> first provider value).
- Added `tests/runtime_uv_test.lua` with 7 cases.
- Documented the component API in `src/modules/uv.md`.

**Behavior implemented**

- `ctx.uv:spawn(spec)` awaits a captured subprocess and returns exit status, term
  signal, stdout, stderr, and `success`.
- `ctx.uv:scandir(path)` returns entries or `nil, err`.
- `ctx.clock` (from the uv clock component) and `ctx.uv` expose `now`/`monotonic`.
- The loop is released on shutdown via the resource graph; `loop.released` reflects it.
- Callback state (`_callbacks`, `pending`) lives on the `UvLoop` instance rather than
  module globals.

**Deliberate boundary choices (recorded as D24)**

- The uv clock provides real time but no `wait`; blocking waits come from the loop's
  `wait` operation. `sched.sleep` under a uv clock therefore busy-spins until the
  deadline rather than blocking; sleep-heavy uv runtimes should use a blocking clock in
  a later phase.
- The loop's `wait` only runs uv when its own `pending` count is nonzero, so scheduler
  sleep tickets do not block in `uv_run`.
- The existing `mode = "uv"` driver, globals, and `sched.register_handler` handlers
  remain until Phase 13.

**Verification**

- `make` rebuilt the embedded `uv`/`runtime` modules and linked cleanly.
- `make test`: 37 files passed, 0 failed (new `tests/runtime_uv_test.lua`: 7/7).

---

## 2026-10-23 — Phase 8 complete: SDL subsystem, window, input components

**Done**

- Added `EVENT_WINDOW_CLOSE_REQUESTED`, `EVENT_WINDOW_FOCUS_GAINED`, and
  `EVENT_WINDOW_FOCUS_LOST` to `src/modules/sdl3.c` (needed by the input component).
- Added composable components to `src/modules/sdl3x.lua` (`runtime` is now required):
  - `sdl3x.plugin` with `sdl3.subsystem`/`sdl3.window`/`sdl3.input` capabilities and
    `sdl3.key`/`sdl3.mouse`/`sdl3.resize`/`sdl3.close`/`sdl3.focus` extension points
    mapped to class methods;
  - `sdl3x.subsystem_component`, `sdl3x.window_component`, `sdl3x.input_component`;
  - `sdl3x.SdlSubsystem` and `sdl3x.SdlInput` component objects.
- Added `tests/runtime_sdl_test.lua` with 4 cases.
- Documented the components in `src/modules/sdl3x.md`.

**Behavior implemented**

- The subsystem component initializes only the missing SDL subsystems and quits only
  the flags it owns.
- The window component creates a real window from properties (defaults preserved by
  `sdl3x.Window`), requiring only the subsystem so it composes with and without
  graphics.
- The input component polls SDL each engine step, emitting normalized key, mouse,
  resize, close, and focus events, plus an initial resize.
- Composition order is subsystem -> window -> input, enforced by capability
  requirements.

The SDL smoke test created a real window and emitted the initial resize in this
environment (181 ms); it skips gracefully when no video driver is available.

**Verification**

- `make` rebuilt the C `sdl3` module and the embedded `sdl3x`/`runtime` modules.
- `make test`: 38 files passed, 0 failed (new `tests/runtime_sdl_test.lua`: 4/4).

---

## 2026-10-23 — Phase 9 complete: graphics context capabilities

**Done**

- Added a `graphics.context` capability to `sdl3x.plugin` and three context components
  to `src/modules/sdl3x.lua`:
  - `sdl3x.renderer_context_component` (`backend = "renderer"`);
  - `sdl3x.gl_context_component` (`backend = "gl"`);
  - `sdl3x.gpu_context_component` (`backend = "gpu"`).
- Each context requires `sdl3.window`, publishes its backend as a capability property,
  and releases its own resources on partial-creation failure.
- Added `tests/runtime_graphics_test.lua` with 6 cases.
- Documented the components in `src/modules/sdl3x.md`.

**Behavior implemented**

- Consumers select a backend by capability constraint without naming a component.
- Renderer context exposes `present`/`set_vsync`; GL exposes
  `present`/`set_swap_interval`/`get_proc_address`; GPU exposes the device.
- Renderer, OpenGL, and GPU smoke tests all created real contexts in this environment
  (706 ms). They skip gracefully when a backend is unavailable.

**Deliberate boundary choices (recorded as D26)**

- A GL context assumes the window was created with the OpenGL window property; the
  bundle/user supplies it via `window_props`.
- GPU frame acquisition/presentation (swapchain) is deferred to Phase 10; Phase 9
  only creates and owns the device.
- The legacy `sdl3x` driver setup functions and their module globals remain until
  Phase 13.

**Verification**

- `make` rebuilt the C `sdl3` module and embedded `sdl3x`/`runtime` modules.
- `make test`: 39 files passed, 0 failed (new `tests/runtime_graphics_test.lua`: 6/6).

---

## 2026-10-23 — Phase 10 complete: frame lifecycle and presentation

**Done**

- Added `core.before_frame`/`core.after_frame` extension points (class methods
  `before_frame`/`after_frame`) to `src/modules/runtime.lua`.
- Gave each graphics context a backend-agnostic `render_frame(render_fn)` method
  (renderer/GL call `render_fn` then present/swap; GPU acquires a command buffer and
  swapchain, calls back with them, then submits).
- Added `sdl3x.frame_component(plugin, options)` with a `frame` progress operation that
  emits the frame phases, renders, presents, and optionally profiles.
- Added `tests/runtime_frame_test.lua` with 4 cases.
- Documented the frame component and `render_frame` in `src/modules/sdl3x.md`.

**Behavior implemented**

- The frame loop is one progress operation; frame phases are ordinary extension points.
- Class execution uses `instance:render(...)`, forwarding GPU arguments; `options.render`
  overrides it.
- `options.frame_profiler` (true or table) wraps the frame and render call.
- Renderer and GPU frame smoke tests ran in this environment (109 ms / 21 ms) and skip
  gracefully when a backend is unavailable.

**Deliberate boundary choices (recorded as D27)**

- Presentation is selected through the graphics context object's `render_frame`; there
  is no separate presentation capability yet.
- Vsync is exposed by the graphics context and fullscreen by the window resource; both
  are component capabilities rather than app base-class methods.
- `frame_profiler` lives on the frame component, but its `before_frame`/`after_frame`
  observation points are the core extension points.

**Verification**

- `make` rebuilt the embedded `sdl3x`/`runtime` modules.
- `make test`: 40 files passed, 0 failed (new `tests/runtime_frame_test.lua`: 4/4).

---

## 2026-10-23 — Phase 11 complete: rendering services via capabilities

**Done**

- Declared `font.renderer`, `shader.stage`, `mesh.vertex_input`, and `gl.resolver`
  capabilities in `sdl3x.plugin`; added provider components in `sdl3x.lua`:
  `mesh_vertex_input_component`, `gpu_shader_stage_component`,
  `gl_shader_stage_component`, `font_renderer_component`,
  `gl_font_renderer_component`, and `gl_resolver_component`.
- Added `plugin`/`component` constructors to `mesh`, `shader`, `font`, and `gl`, plus
  optional provider arguments on `mesh.build_vertex_input`, `shader.create_stage`,
  `shader.destroy_stage`, and `font.create_text_renderer`.
- `gl.component` installs the resolver during the run and clears it on release.
- Added `context:capability(id)` to the component create context in `runtime.lua`.
- Added `tests/runtime_services_test.lua` with 6 cases; documented the new constructors
  in `mesh.md`, `shader.md`, `font.md`, and `gl.md`.

**Behavior implemented**

- Consumer components resolve providers from capabilities and expose them as
  `ctx.<name>` without `rig.require_service`.
- Module functions accept the `ctx` provider so new code can pass it explicitly while
  the legacy service fallback remains until Phase 13.
- A real GPU mesh provider test built vertex input through the capability path (19 ms).

**Deliberate boundary choices (recorded as D28)**

- The `sdl3x` graphics context components now set the legacy module globals
  (`runtime_renderer`, `runtime_gl_context`, `runtime_gpu_device`) as a transitional
  bridge, because the existing font/shader providers still read them. These globals are
  removed in Phase 13.
- `gl.component` installs a module-level resolver on the `gl` module and clears it on
  release; this is the one remaining module-global accessor in the service path.
- Service registration is retained until Phase 13 per the phase notes.

**Verification**

- `make` rebuilt the embedded `runtime`/`sdl3x`/`mesh`/`shader`/`font`/`gl` modules.
- `make test`: 41 files passed, 0 failed (new `tests/runtime_services_test.lua`: 6/6).

---

## 2026-10-23 — Phase 12 complete: convenience bundles

**Done**

- Added bundles:
  - `sdl3x.bundle_sdl3`, `sdl3x.bundle_sdl3_gl`, `sdl3x.bundle_sdl3_gpu`;
  - `uv.bundle_uv`;
  - `runtime.headless_bundle`.
- Each bundle attaches its own plugin(s) and adds components explicitly; `:use` alone
  still adds no behavior.
- Added `tests/runtime_bundle_test.lua` with 6 cases.
- Documented the bundles in `sdl3x.md`, `uv.md`, and `runtime.md`.

**Behavior implemented**

- `bundle_sdl3` reproduces the renderer stack; `bundle_sdl3_gl` the OpenGL stack (window
  gets the OpenGL property automatically); `bundle_sdl3_gpu` the GPU stack.
- `bundle_uv` reproduces the async stack (clock/timer/scheduler/loop).
- `headless_bundle` provides a scheduler with no I/O.
- The `:use`-only test asserts `plan.components` stays empty.

**Deliberate boundary choices (recorded as D29)**

- Bundles are functions that mutate and return a builder rather than a new builder
  type, so they compose with the existing fluent API.
- Bundles own their plugin instances; attaching the same plugin id separately errors,
  as designed.

**Verification**

- `make` rebuilt the embedded `runtime`/`sdl3x`/`uv` modules.
- `make test`: 42 files passed, 0 failed (new `tests/runtime_bundle_test.lua`: 6/6).

---

## 2026-10-23 — Phase 13 complete: legacy runtime removed

**Done**

- Removed from `rig.lua`: `rig.run`, `rig.App`, `rig.Runtime`,
  `rig.register_runtime_driver`, `rig.register_runtime_preset`,
  `rig.register_runtime_hook`, `rig.register_service`,
  `rig.register_service_provider`, `rig.require_service`, and
  `rig.get_module_config`. `rig.ResourceScope` is retained as a generic utility used by
  `scenegraph` and `sdl3x`.
- Removed the `sdl3x` runtime drivers/presets/scheduler machinery and driver-config
  helpers; removed the `uv` runtime driver and preset.
- `time` is now a plain wrapper over `uv.now()` / `uv.monotonic()` (no service).
- `mesh`, `shader`, `font`, and `gl` no longer register services; their dispatch
  functions take a required provider argument.
- `sdl3x` graphics/window components set the transitional `runtime_window`,
  `runtime_renderer`, `runtime_gl_context`, and `runtime_gpu_device` values used by the
  remaining module helpers.
- `sdl3x`/`animator` `App` classes are plain `rig.Class()` values; `init(context)`
  receives the runtime context and app configuration comes from `context.options`.
  `animator.App` ticks in `before_frame`; profiler subclasses call
  `self:super().before_frame(self)` first. `sdl3x.SceneApp` combines both.
- Added `sdl3x.bundle_sdl3*` scheduler wiring (`runtime.scheduler_plugin` + SDL
  clock/timer/scheduler), `sdl3x.gl_resolver_component` installs the `gl` resolver,
  and the input component stops the runtime on `sdl3.close`.
- Migrated `scripts/run_all_tests.lua` and `tests/test.lua` runner to
  `rig.runtime()` + `uv.bundle_uv`.
- Migrated `examples/` to the builder model (Lua and Fennel).
- Migrated `tests/`: removed the old `rig.run`/driver/service tests, rewrote
  `time_test`, `mesh_test`, `shader_test`, `gl_test`, `glx_test`, `font_test`,
  `animator_test`, and the `sdl3x_test` driver-config/App cases.
- Updated module `.md` documentation.

**Verification**

- `make test`: 42 files passed, 0 failed.
- Examples run under `./build/rig` (keylogger, keylogger.fnl, ants, scroller,
  renderer_baseline, gl_baseline, spinning_cube_gl all start and run to the timeout).
  `spinning_cube` fails only because this container lacks `libshaderc`.
- `grep` confirms no remaining references to the removed APIs in `src/`, `tests/`,
  `examples/`, or `scripts/`.

**Deliberate boundary choices (recorded as D30)**

- `sdl3x.get_window`/`get_renderer`/`get_gpu_device`/`get_gl_context` and the
  transitional module globals remain, because the renderer font/shader/mesh providers
  and the example helpers still read them. Moving those providers to context-bound
  instances is deferred follow-up work.
- `rig.ResourceScope` remains as a generic scope utility.

---

## HANDOFF

The redesign phases are complete. Optional follow-ups (tracked in `PHASES.md` under
“Deferred beyond Phase 13” and in `PLAN.md`) remain out of scope:

- mixed execution models;
- preemptive or multithreaded scheduling;
- runtime startup arguments;
- source-generating Fennel macros and runtime `eval`;
- static Lua signature/type checking;
- advanced event fan-out semantics;
- descriptor/compiled-plan serialization.

Suggested next cleanup (not required by any phase):

- convert the `sdl3x` font/shader/mesh providers to context-bound instances so the
  transitional module globals can be deleted;
- delete the now-dead `setup`/`setup_gpu`/`setup_gl`/`shutdown` helpers in `sdl3x.lua`;
- add an `sdl3x`-independent clock component if SDL timers should replace libuv timers
  in SDL bundles.

**Constraints to carry forward**

- Rebuild before any `./build/rig ...` smoke test when C, build inputs, or embedded
  module sources change.
- Use `make test` for final verification; smoke tests are supplemental only.

---

## 2026-10-23 — Follow-up: bound capability facades

**Done**

- Added `bind(provider)` to `mesh`, `shader`, and `font`. Each returns a small facade whose
  `:` methods delegate to the validated module entry points:
  - `mesh.bind(p):build_vertex_input(mesh)`
  - `shader.bind(p):create_stage(spec)` / `:destroy_stage(stage)`
  - `font.bind(p):create_text_renderer(atlas)` / `:create_style(face, options)`
- `mesh.component`, `shader.component`, and `font.component` now return the bound facade
  as `ctx.<name>`.
- `sdl3x.provider_component` accepts an optional `bind` and wraps its provider with it, so
  the SDL bundles expose facades too (`sdl3x.mesh_vertex_input_component`,
  `gpu_shader_stage_component`, `gl_shader_stage_component`, `font_renderer_component`,
  `gl_font_renderer_component`).
- Updated `examples/` to call `ctx.mesh:build_vertex_input(cube)`,
  `ctx.shader:create_stage(spec)`, and `ctx.font:create_style(face, options)`, and renamed
  the module-level `app_context` variable to `ctx`.
- Updated `runtime_services_test.lua` and the `mesh`/`shader`/`font` docs to the facade
  call style.

**Rationale**

- The colon form reads like the rest of the capability values (`ctx.graphics:render_frame`,
  `ctx.window:release`) without forcing providers to become stateful self-methods.
- Providers stay value-first strategy tables; normalization/validation stays in the module
  entry points, so a facade cannot skip it.

**Verification**

- `make test`: 42 files passed, 0 failed.
- Examples run under `./build/rig`, including `scroller`, both baselines,
  `spinning_cube_gl`, and `ants`.

---

## 2026-10-23 — Follow-up: D30 finished (context-bound providers, no module globals)

**Done**

- The `sdl3x` service providers are now context-bound factories:
  - `make_sdl3_font_provider(context)` captures the renderer pointer.
  - `make_sdl3_gl_font_provider(context)` captures the window (for pixel size).
  - `make_shader_stage_service_sdl3_gpu(context)` captures the GPU device.
  - `sdl3_gpu_mesh_service` and `gl_resolver_service_sdl3_gl` stay static (they need no
    runtime state).
- `sdl3x.provider_component` accepts `make` and an optional `release`;
  `font_renderer_component`/`gl_font_renderer_component` release the GL font backend
  state on teardown.
- Removed the transitional module globals (`runtime_window`, `runtime_renderer`,
  `runtime_gpu_device`, `runtime_gl_context`, `runtime_owned_init_flags`) and the
  module-global accessors (`sdl3x.get_window`, `get_renderer`, `get_gpu_device`,
  `get_gl_context`) and `sdl3x.clear`.
- Removed the dead old-driver helpers that only existed to populate those globals:
  windowed setup/teardown (`setup`, `setup_gpu`, `setup_gl`, `shutdown`,
  `initialize_windowed_sdl`, `create_window_or_fail`), presentation helpers
  (`present`, `present_gl`), the old poll-and-dispatch loop (`pump_events`,
  `dispatch_*`), the old frame drivers (`render_frame`, `render_gpu_frame`,
  `render_gl_frame`), resize tracking (`get_window_size*`, `dispatch_resize_if_changed`),
  and `merge_props`.
- Added `graphics:clear(r, g, b, a)` to the renderer graphics context.
- `sdl3x.App:set_vsync`/`set_fullscreen` now use `self.graphics`/`self.window`.
- The runtime sets `instance.ctx = ctx` for class executions, so any execution class can
  read `self.ctx`.
- Migrated `examples/`: `sdl3x.get_renderer()` → `ctx.graphics.renderer`,
  `sdl3x.get_window()` → `ctx.window`, `sdl3x.get_gpu_device()` → `ctx.graphics.device`,
  and `sdl3x.clear(...)` → `graphics:clear(...)`. `set_vsync`/`set_fullscreen` use the
  graphics/window values.
- Updated `sdl3x_test.lua` and `sdl3x.md`.

**Verification**

- `make test`: 42 files passed, 0 failed.
- All examples run under `./build/rig` (keylogger, Fennel keylogger, ants, scroller, both
  baselines, spinning_cube_gl); `spinning_cube` still needs `libshaderc`, absent here.
- No references to the removed globals/accessors remain in `src/`, `tests/`, `examples/`,
  or `scripts/`.

---

## 2026-10-23 — Follow-up: object scopes adopted into the runtime root

**Done (option B: attach-time adoption)**

- `runtime.ResourceScope` gained `replace(owner, key, resource, release_fn)` and now
  skips already-replaced entries during release.
- `rig.ResourceScope:release()` now continues past individual failures and returns an
  error list (still reverse order, still idempotent). Standalone `release_tree()` raises
  the aggregated errors.
- The runtime exposes its root scope to executions as `compiled.ctx.resources`.
- `animator.App:after_setup` attaches `self.ctx.resources` to the scene root via
  `Object:set_resource_scope` before `activate_tree`.
- `scenegraph.Object` now:
  - keeps a lazily created `rig.ResourceScope` per object;
  - adopts it into the runtime scope (once) when the scope is attached or when the local
    scope is first created after attach;
  - propagates the runtime scope to children in `add_child`/`set_resource_scope`;
  - skips the local release in `release_tree` when a runtime scope is attached (the
    runtime root releases it), and still releases locally otherwise.
- `sdl3x.App`'s `owned_resources` scope is adopted into `context.resources` when present,
  so App-owned resources share the runtime release path.
- Added `tests/runtime_scenegraph_test.lua` (3 cases): object scopes release through the
  runtime root in child-before-parent order, objects added after activation still reach
  the root, and `runtime.ResourceScope:replace` releases the previous resource.

**Verification**

- `make test`: 43 files passed, 0 failed.
- Examples run under `./build/rig` (keylogger, scroller, both baselines,
  spinning_cube_gl, ants).
