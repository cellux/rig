# Design Decisions

## Purpose

This document records the design decisions that shape the implementation across
phases. Decisions remain in force until explicitly superseded; changed decisions are
retained and marked as superseded rather than deleted. Progress or discussion about a
decision belongs in `DIARY.md`, while ordered implementation work belongs in
`PHASES.md`.

## Status key

- **Accepted** — in force.
- **Superseded by Dn** — retained for history, no longer in force.
- **Proposed** — under review, not yet binding.

---

## D1 — Replace `rig.run` with builder/compiler/start

**Status:** Accepted (2026-10-23)

The immediate `rig.run(options)` model is replaced by a fluent builder that produces a
validated descriptor, a side-effect-free `:compile()`, and a single-use
`runtime:start()`. No backward compatibility layer is provided; the project has a
single author and no external users.

## D2 — Compilation is resource-free; startup acquires resources

**Status:** Accepted (2026-10-23)

All configuration, capability selection, dependency resolution, lifecycle/event graph
construction, and dispatch specialization happen before startup. Resource acquisition
and operational side effects happen only during `:start()`. Compile errors describe
descriptor/graph facts; startup errors describe environment/resource facts and must
name the failing component.

## D3 — Plugins are ordinary `require` values attached with `:use(plugin)`

**Status:** Accepted (2026-10-23)

A plugin is self-contained and does not mutate a global registry. `:use(plugin)` makes
its constructors, capability/requirement definitions, extension-point contracts,
schemas, and resource implementations available to that builder. `:use` alone adds no
runtime behavior. Descriptors are added explicitly with `:add(descriptor)`; adding a
descriptor from an unattached plugin is an error. Duplicate plugin attachment is an
error.

## D4 — Capabilities, bindings, and component identity are distinct

**Status:** Accepted (2026-10-23)

Capabilities are anonymous composition contracts. `name` is the user-visible key
installed in `ctx`. Component identity is separate from both. Capabilities are never
inserted into `ctx` automatically. A component exposes at most one public top-level
object under `name`; sub-objects remain behind that object's API.

## D5 — `ctx` is the only runtime dependency surface

**Status:** Accepted (2026-10-23)

User code receives one plain table `ctx`, indexed by configured names, whose values
expose component-specific APIs. `rig.require_service` and module-global runtime
accessors are replaced by named `ctx` bindings. Top-level plugin modules expose only
pure builder helpers, schemas, constants, and compile-time metadata.

## D6 — Runtime behavior must not depend on module load order

**Status:** Accepted (2026-10-23)

Components are explicitly added by the builder. The compiler never silently
instantiates components from merely attached plugins; convenience bundles add several
components explicitly.

## D7 — A compiled runtime is single-use and receives no startup options

**Status:** Accepted (2026-10-23)

All configuration is frozen before `:start()`. A runtime transitions through
`compiled`, `starting`, `running`, `stopping`, and `stopped`, with `failed` for
startup/run errors. Double start and use after stopped/failed are rejected.

## D8 — Cooperative, single-threaded scheduling

**Status:** Accepted (2026-10-23)

Scheduling is cooperative and single-threaded. Preemptive and multithreaded scheduling
are out of scope. `scheduler:spawn(fn)` creates a foreground task by default, with an
explicit background option. Completion of the last foreground task requests shutdown;
background tasks do not keep the runtime alive and are cancelled on shutdown after an
opportunity to run cleanup/finally behavior.

## D9 — Three execution forms, with strict initial validation

**Status:** Accepted (2026-10-23)

`:execute(function)`, `:execute(AppClass)`, and inferred hook-driven execution via
`:on(...)` are supported. Standalone builder handlers may not be mixed with a supplied
function/class execution form initially. Class methods are part of class-driven
execution. Mixing execution models is deferred.

## D10 — Function execution selects coroutine semantics by scheduler presence

**Status:** Accepted (2026-10-23)

A function passed to `:execute` is called directly with `ctx` when no scheduler is
assembled. When a scheduler is assembled, the same function is spawned as the initial
foreground coroutine. No second execution API is introduced.

## D11 — One lean progress engine owns the top-level loop

**Status:** Accepted (2026-10-23)

Exactly one progress engine is selected per runtime. It owns top-level progress,
termination, and extension points for scheduler draining, event polling, timer
deadlines, async waiting, frame production/presentation, and stop detection. It
contains no SDL-, UV-, or graphics-specific behavior.

## D12 — All runtime resources are owned and released deterministically

**Status:** Accepted (2026-10-23)

Every runtime-created resource belongs to a runtime ownership graph. Resources are
rolled back on startup failure and released in reverse acquisition order on shutdown.
Cleanup continues past errors and aggregates them.

## D13 — Capability selection is declarative first, predicate second, priority last

**Status:** Accepted (2026-10-23)

Selection uses declarative properties, then optional pure plugin predicates, then
deterministic candidate priorities. Compilation rejects absence, ambiguity, ties,
contradictory constraints, and unsupported combinations.

## D14 — Non-core events and hooks use qualified names with declared contracts

**Status:** Accepted (2026-10-23)

Each extension point declares qualified name, lifecycle timing, payload schema,
accepted handler form, fan-out support, ordering semantics, and failure behavior.
Core phases use a reserved namespace. The compiler validates existence, callability,
payload/declaration, and cardinality; Lua signatures are not inferred. Fan-out and
handler-ordering policy beyond declarations is deferred.

## D15 — Keep the old model alive until migration completes

**Status:** Accepted (2026-10-23)

`rig.run`, the service registry, and driver/preset/hook registration remain functional
through Phase 12 while new machinery is built and verified. New components must not
depend on them. They are removed in Phase 13, after every in-repo caller is migrated.

## D16 — Phase ordering prioritizes testable vertical slices

**Status:** Accepted (2026-10-23)

Foundations (builder/graph/compilation/lifecycle/ownership) are implemented and tested
with fake or headless components before real backends are migrated. Bundles appear
only after their underlying components work independently. See `PHASES.md`.

## D17 — Deferred work is explicitly listed, not silently dropped

**Status:** Accepted (2026-10-23)

Mixed execution models, preemptive/multithreaded scheduling, runtime startup
arguments, source-generating Fennel macros and `eval`, static Lua signature/type
checking, advanced fan-out/ordering policy, and descriptor/plan serialization are
deferred. They are tracked in `PHASES.md` and must not block the initial
implementation.

## D18 — The runtime builder lives in a dedicated `runtime` module

**Status:** Accepted (2026-10-23)

The builder/compiler foundation is implemented in `src/modules/runtime.lua`, listed in
`src/modules/modules.txt` after `rig`. `rig.runtime()` lazily `require`s it, so there is
no load-order dependency and `rig` stays loadable on its own. Plugin values are created
with `runtime.plugin(spec)` and component descriptors with
`runtime.descriptor(plugin, spec)`, which tags each descriptor with its originating
plugin. `builder:compile()` snapshots into `runtime.Compiled`; capability resolution,
dependency ordering, execution, and resource acquisition are added in later phases
without changing this placement.

## D19 — Phase 2 capability-resolution semantics

**Status:** Accepted (2026-10-23)

Capability resolution follows D13 with these concrete interpretations, chosen so the
initial implementation is unambiguous and testable:

- A component is excluded from the candidate set for its own requirements, so a
  component cannot satisfy itself.
- Every capability referenced by `provides`/`requires` must be declared by an attached
  plugin; unknown references are compile errors.
- A requirement whose declarative `properties` match no candidate is reported as a
  constraint conflict, distinct from the absence of any provider.
- Equal top-priority candidates are a tie error; priorities are otherwise numeric with
  default `0`.
- `descriptor.excludes` models unsupported capability combinations: a component may
  declare capability ids it is incompatible with, and compilation fails if another
  component provides one.
- Compilation validates `config` through `config_schema` and lowers it into the plan.
- Extension-point `payload` is accepted as a schema-like table but is not applied until
  dispatch is implemented in Phase 6.

## D20 — Phase 3 execution and progress-engine semantics

**Status:** Accepted (2026-10-23)

- Exactly one execution form is selected at compile time: `function`, `class`, or
  `hooks`. No execution plus no handlers is an error; handlers plus `:execute` is an
  error until mixed execution is deliberately added later.
- Only function execution runs to completion directly. Class and hook execution run the
  progress engine until a stop is requested.
- `descriptor.create(context)` is the Phase 3 in-memory instantiation hook. It receives
  the in-progress `ctx`, resolved provider values, and its component record. Resource
  ownership and release are Phase 4.
- The built-in `runtime.ProgressEngine` consumes per-component
  `descriptor.progress` operations. `poll`, `drain`, and `frame` run once per step in
  component order; `should_stop` terminates the loop. `wait` and `deadline` are
  reserved for the scheduler/timer phases.
- Hooks are collected and validated but **not dispatched** and class lifecycle methods
  are **not** invoked yet; dispatch is Phase 6.
- The runtime exposes `compiled:start()` / `compiled:stop()` with a single-use state
  machine, and startup/run failures transition to `failed` and re-raise the original
  error.

## D21 — Phase 4 resource-ownership semantics

**Status:** Accepted (2026-10-23)

- Every compiled runtime owns one `runtime.ResourceScope` (`compiled.resources`);
  resources are adopted in acquisition order and released in reverse order.
- A component registers resources through `descriptor.release(value)` (auto-adopted
  when `create` yields a non-nil value) and/or `context.adopt(resource, release_fn)`.
- `ResourceScope:release()` is idempotent, continues past individual failures, and
  returns a list of error strings rather than raising.
- Startup failure rolls back all adopted resources, then transitions to `failed`. The
  re-raised error is the original component-labelled startup error, optionally
  combined with aggregated cleanup errors.
- A release failure during normal shutdown transitions the runtime to `failed` and
  raises the aggregated cleanup error.
- Component `create`/`release` types are validated at compile time.

## D22 — Phase 5 scheduler and timer semantics

**Status:** Accepted (2026-10-23)

- The runtime reuses the existing `sched.Scheduler` (retained by the inventory). A
  `runtime.Scheduler` wraps it to add clock/timer integration, foreground/background
  tracking, deadlock detection, and cancellation, and activates it for the runtime's
  duration so `sched.sleep`/`yield`/`park`/`join` work inside tasks.
- The scheduler requires `sched.clock` and `sched.timer` capabilities with
  `protocol = "sched"`. Incompatible implementations are a compile-time constraint
  conflict.
- `scheduler:spawn` creates a foreground task; `scheduler:spawn_background` does not
  keep the runtime alive. Completion of the last foreground task requests shutdown.
- Function `:execute(fn)` is spawned as the initial foreground coroutine when a
  scheduler is assembled; without a scheduler it is called directly.
- `sched.sleep` is implemented through the timer capability rather than
  `sched.Scheduler:sleep_until`.
- Background tasks are cancelled on shutdown by waking them with `runtime.CANCELLED`
  and draining once, giving them an opportunity to run cleanup. LuaJIT cannot inject
  errors into a coroutine, so tasks that ignore the sentinel are dropped.
- Foreground tasks waiting with no ready work, pending async, or timer deadline are a
  deadlock and fail the runtime.
- The progress engine's `wait` step advances a `ManualClock` to the next deadline;
  real blocking waits are supplied by backend clock components in later phases.

## D23 — Phase 6 extension-point dispatch and class adapter

**Status:** Accepted (2026-10-23)

- Handlers receive one payload/context value. Core lifecycle phases pass
  `{ runtime, ctx }`; plugin events pass whatever the emitter provides. Positional
  arguments are not used.
- Extension-point declarations carry `cardinality`, `order`, `method`, and an optional
  `payload` schema object. Ordering is `registration` (default) or `reverse`;
  advanced fan-out/ordering policy remains deferred.
- `compiled:emit(name, payload)` validates the payload against the declaration schema,
  rejects unknown extension points, invokes handlers in declared order, and then
  invokes the mapped class method for class execution.
- Core phases are emitted automatically: `before_setup` before instantiation,
  `after_setup` after class construction, `before_shutdown` before teardown, and
  `after_shutdown` after teardown.
- The class adapter maps extension points to class methods at compile time; duplicate
  mappings and mappings to reserved `init`/`super` are errors.
- Event sources declare the qualified events they may emit (validated against declared
  extension points) and are polled once per engine step, before component progress
  operations, with an `emit` function in the step context.

## D24 — Phase 7 uv component semantics

**Status:** Accepted (2026-10-23)

- The `uv` module keeps its legacy `mode = "uv"` driver and helpers until Phase 13 and
  additionally exposes composable components (`uv.plugin`, `uv.clock_component`,
  `uv.loop_component`, `uv.UvLoop`).
- All uv runtime state (loop handle, callback registry, pending count) lives on the
  `UvLoop` instance; no module globals are used by the components.
- The loop component requires `sched.scheduler` and installs `uv.spawn`/`uv.scandir`
  handlers on that scheduler instance. Async completions wake the awaiting task and
  stop the loop, which is driven by the component's `wait` operation.
- The loop is released through the resource graph, which drains and deletes it.
- The uv clock provides real `now`/`monotonic` but no blocking `wait`; `sched.sleep`
  under a uv clock busy-spins until the deadline. Blocking clock waits are deferred.
- `compiled.capability_values` exposes the first provider value per capability so
  component progress operations can reach sibling components generically.

## D25 — Phase 8 SDL component semantics

**Status:** Accepted (2026-10-23)

- SDL is decomposed into subsystem, window, and input components that require each
  other through capabilities (`sdl3.subsystem` -> `sdl3.window` -> `sdl3.input`), so a
  window composes with or without graphics.
- The subsystem component owns only the init flags it actually initialized and quits
  only those on release.
- The window component delegates creation to `sdl3x.Window`, preserving default
  properties and sizing.
- The input component emits qualified `sdl3.key`/`mouse`/`resize`/`close`/`focus`
  events mapped to the class methods `on_key`/`on_mouse`/`on_resize`/`on_close`/
  `on_focus`, plus an initial `sdl3.resize` on first poll.
- `sdl3.c` registers the additional event constants
  (`EVENT_WINDOW_CLOSE_REQUESTED`, `EVENT_WINDOW_FOCUS_GAINED`,
  `EVENT_WINDOW_FOCUS_LOST`) required by the input component.
- Component state lives on `SdlSubsystem`/`SdlInput` instances and on the `Window`
  resource; the legacy `sdl3x` driver globals remain until Phase 13.

## D26 — Phase 9 graphics context semantics

**Status:** Accepted (2026-10-23)

- Graphics contexts provide the `graphics.context` capability and publish their backend
  (`renderer`, `gl`, `gpu`) as capability `properties`, so consumers select by
  constraint rather than by component name.
- Every context requires `sdl3.window` and releases its own resources when creation
  fails partway, giving deterministic rollback without a shared graphics global.
- The OpenGL context assumes the window was created with the OpenGL window property;
  this is supplied through the window component's `window_props`.
- GPU frame acquisition/presentation (swapchain and command submission) is deferred to
  Phase 10; Phase 9 creates and owns the device and claims the window.
- Renderer/GL/GPU smoke tests are guarded so they skip cleanly when a backend is
  unavailable.

## D27 — Phase 10 frame lifecycle and presentation semantics

**Status:** Accepted (2026-10-23)

- `core.before_frame` and `core.after_frame` are core extension points mapped to the
  class methods `before_frame`/`after_frame`.
- The frame component contributes one `frame` progress operation that emits the frame
  phases around a render callback and a `graphics:render_frame(render)` call.
- Presentation is backend-agnostic through `render_frame`: renderer/GL call the render
  callback then present/swap; GPU acquires a command buffer and swapchain texture,
  calls back with them, and submits. There is no separate presentation capability yet.
- The render callback is `options.render` when supplied, otherwise
  `instance:render(...)`, with GPU arguments forwarded.
- `options.frame_profiler` (`true` or a table) attaches profiling around the frame and
  render call while the observable hook points remain the core extension points.
- Vsync is exposed by the graphics context and fullscreen by the window resource.

## D28 — Phase 11 rendering-service capability semantics

**Status:** Accepted (2026-10-23)

- `font.renderer`, `shader.stage`, `mesh.vertex_input`, and `gl.resolver` are
  capabilities declared by `sdl3x.plugin` and provided by components that require a
  specific `graphics.context` backend.
- Consumer components (`mesh.component`, `shader.component`, `font.component`,
  `gl.component`) require the capability and expose the resolved provider as
  `ctx.<name>`; module functions accept the provider explicitly so no global lookup is
  needed.
- `context:capability(id)` is available to component `create` functions for resolving
  requirement values by capability id.
- As a transitional bridge, the `sdl3x` graphics context components set
  `runtime_renderer`/`runtime_gl_context`/`runtime_gpu_device`, because the existing
  font/shader providers still read them; these globals are removed in Phase 13.
- `gl.component` installs a module-level resolver on the `gl` module and clears it on
  release; this is the only remaining module-global accessor in the service path.
- The service registry and its registrations remain until Phase 13.

## D29 — Phase 12 bundle semantics

**Status:** Accepted (2026-10-23)

- Bundles are functions `(builder, options) -> builder` that attach their own plugins
  and add components explicitly, so they compose with the existing fluent API and
  `:use` alone still adds no behavior.
- `sdl3x.bundle_sdl3`/`bundle_sdl3_gl`/`bundle_sdl3_gpu` assemble the renderer/OpenGL/
  GPU stacks (the GL bundle injects the OpenGL window property); `uv.bundle_uv`
  assembles the async stack; `runtime.headless_bundle` provides a scheduler without I/O.
- Bundles own their plugin instances; attaching a plugin with the same id elsewhere is a
  duplicate-attachment error, as designed.

## D30 — Phase 13 legacy-removal boundaries

**Status:** Accepted (2026-10-23)

- `rig.run`, `rig.App`, `rig.Runtime`, driver/preset/hook registration, the service
  registry, `rig.require_service`, and `rig.get_module_config` are removed.
- Service dispatch functions (`mesh.build_vertex_input`, `shader.create_stage`,
  `shader.destroy_stage`, `font.create_text_renderer`, `font.create_style`) take the
  provider explicitly; there is no global fallback.
- `sdl3x`/`animator` `App` classes are plain `rig.Class()` values. The runtime
  instantiates them with `init(context)`, and app configuration is read from
  `context.options` (optionally nested under `animator`/`sdl3x`).
- `animator.App` ticks in `before_frame`; profiler subclasses call
  `self:super().before_frame(self)` first; `sdl3x.SceneApp` combines both.
- `sdl3x` bundles wire `runtime.scheduler_plugin` plus an SDL-backed clock, a timer,
  and a scheduler; `sdl3x.gl_resolver_component` installs the `gl` resolver; the input
  component stops the runtime on `sdl3.close`.
- `rig.ResourceScope` is retained as a generic utility (used by `scenegraph` and
  `sdl3x`).
- The transitional `sdl3x` module globals (`runtime_window`, `runtime_renderer`,
  `runtime_gl_context`, `runtime_gpu_device`) and their accessors remain as follow-up
  work, because the font/shader/mesh providers still read them.
