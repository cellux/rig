# Implementation Phases

## Purpose

This document turns the approved specification in `PLAN.md` into an ordered set of
independently testable implementation phases. Each phase defines a finished, stable
slice of work. Progress and day-to-day discoveries belong in `DIARY.md`; enduring
design choices belong in `DECISIONS.md`.

## Conventions

- Phases are ordered and cumulative. A phase should not depend on work scheduled for a
  later phase.
- Each phase lists: goal, deliverables, out of scope, dependencies, and verification.
- A phase is complete only when its verification passes via `make test` (rebuilding
  first when C code, build inputs, or embedded module sources change) and no earlier
  phase regresses.
- New public Lua/C module sources under `src/modules/` require a rebuild before any
  `./build/rig ...` smoke test, per `AGENTS.md`.
- No backward compatibility layer is required. Old APIs may be removed once all
  in-repository callers are migrated.
- The plan intentionally keeps `rig.run`, the service registry, and the driver/preset
  registration alive until Phase 13 so that behavior remains verifiable throughout
  the migration. New machinery must not depend on them.

## Phase 0 — Inventory and classification (documentation only)

**Goal.** Freeze the migration surface by inventorying every current public knob and
runtime behavior across the repository and classifying each as retained, reshaped,
deferred, or dropped.

**Deliverables.**

- `INVENTORY.md` listing, at minimum:
  - runtime-level options (`mode`, `driver`, `providers`, `module_config`,
    `driver_config`, `app`);
  - `rig.run` lifecycle phases, driver phases, and event names;
  - `rig.register_runtime_driver` / `register_runtime_preset` / `register_runtime_hook`
    and every in-repo registration site;
  - service definitions and providers (`time`, `font.renderer`, `gl.resolver`,
    `mesh.vertex_input`, `shader.stage`);
  - the `sdl3`, `sdl3_gl`, `sdl3_gpu`, and `uv` drivers and their setup/loop/shutdown
    behavior;
  - `animator`, `sdl3x`, `profiler`, `stat`, `font`, `mesh`, `shader`, and `scenegraph`
    resource/option knobs;
  - app class overrides and event methods used by `examples/` and `tests/`.
- A classification column with a one-line rationale per entry.

**Search scope.** `src/`, `tests/`, `examples/`, and `scripts/` (not `src/` alone).

**Out of scope.** Any code change.

**Dependencies.** None.

**Verification.** Review against `PLAN.md`'s inventory checklist; every checklist
bullet maps to at least one inventory row.

## Phase 1 — Plugin value, builder, and descriptor core

**Goal.** Establish the fluent builder and the strict plugin/descriptor rules without
any execution or resource behavior.

**Deliverables.**

- `rig.runtime()` returning a mutable builder.
- `builder:use(plugin)` attaching a plugin value; duplicate attachment errors.
- `builder:add(descriptor)`; descriptors record their originating plugin and adding a
  descriptor from an unattached plugin errors.
- `builder:on(name, handler)` recording a handler registration (no dispatch yet).
- `builder:execute(fn_or_class)` recording the execution selection.
- `builder:compile()` returning a compiled runtime object with `state == "compiled"`,
  performing no external side effects.
- Plugin record shape: component helper constructors, capability/requirement
  definitions, extension-point declarations, schemas, and resource factories, all
  inert until used.
- Post-compile builder mutation errors (frozen descriptor).

**Out of scope.** Capability resolution, dependency graph, execution, resources,
progress engine.

**Dependencies.** Phase 0.

**Verification.** Unit tests for attach/duplicate/descriptor-ownership/freeze/compile
state; compile must not touch SDL, UV, or the filesystem.

## Phase 2 — Capability, requirement, and dependency graph compilation

**Goal.** Compile a descriptor into a validated, deterministically ordered plan
without acquiring resources.

**Deliverables.**

- Capability and requirement record shapes with declarative properties and optional
  pure predicates; deterministic candidate priorities.
- Plugin schemas for component configuration; compile-time validation errors that name
  the offending component and field.
- Capability resolution producing missing-capability, ambiguity, and priority-tie
  errors.
- Contradictory-constraint and unsupported-combination detection.
- Dependency graph with cycle detection and a deterministic initialization order.
- Context binding validation: duplicate `name` and empty/invalid `name` errors.
- Extension-point existence, handler callability, payload declaration, and cardinality
  validation.
- Lowering to a runtime plan (precomputed component order and operation tables), still
  with no resource acquisition.

**Out of scope.** Resource creation, execution, event dispatch, progress engine.

**Dependencies.** Phase 1.

**Verification.** Unit tests for selection, priorities, ties, absence, cycles,
duplicate names, invalid extension points, and deterministic ordering across repeated
compiles.

## Phase 3 — Runtime lifecycle, execution forms, and progress-engine skeleton

**Goal.** Make a compiled runtime startable with a direct function execution and a
minimal policy-free progress engine.

**Deliverables.**

- Runtime state machine: `compiled` → `starting` → `running` → `stopping` → `stopped`,
  with `failed` on startup or run error; reject double start and use after
  stopped/failed.
- Direct function execution (`:execute(function)` with no scheduler) calling the
  function with `ctx`; returning from it requests shutdown.
- Class execution constructing the user class at startup with `ctx`; and hook-driven
  execution inferred from `:on(...)` when no execution form is supplied.
- Compile-time rejection of missing execution configuration and of mixing standalone
  handlers with a function/class execution form.
- Lean progress engine interface exposing extension points for scheduler draining,
  event polling, timer deadlines, async waiting, frame work, and stop detection, with a
  minimal engine that runs to completion for the direct function case.
- Headless in-memory components used only by tests.

**Out of scope.** Real scheduler, timers, events, I/O, graphics.

**Dependencies.** Phase 2.

**Verification.** Unit tests for each state transition, rollback to `failed`, direct
and class and hook execution, termination semantics, and mixed-execution rejection.

## Phase 4 — Resource ownership, rollback, and cleanup aggregation

**Goal.** Guarantee deterministic resource release on every exit path.

**Deliverables.**

- A per-runtime root ownership scope with acquisition-ordered entries.
- Reverse-order release on normal shutdown.
- Rollback of all resources acquired before a startup failure, identifying the failing
  component in the error.
- Cleanup-error aggregation: continue releasing all resources, then report collected
  errors.
- Extension of the runtime state machine so `starting` failures unwind through the
  ownership graph.

**Out of scope.** Specific resource types.

**Dependencies.** Phase 3.

**Verification.** Unit tests using fake resources: reverse order, rollback on partial
startup, aggregated cleanup errors, idempotent release, and no leaks across repeated
start/fail cycles.

## Phase 5 — Clock, cooperative scheduler, and timer/wakeup capability

**Goal.** Provide cooperative single-threaded scheduling with timed suspension and
foreground/background lifetime rules.

**Deliverables.**

- Clock component providing wall-clock and monotonic time.
- Scheduler component: task spawn, drain, park, `sched.yield`, `sched.await`, join.
- Timer/wakeup component compatible with the selected scheduler; `sched.sleep`
  implemented through it.
- Foreground tasks keep the runtime alive; background tasks do not; completion of the
  last foreground task requests shutdown.
- Shutdown cancels remaining background tasks and gives them a chance to run
  cleanup/finally behavior.
- Deadlock detection when tasks are waiting with no pending progress.
- Compile-time compatibility checks between scheduler and timer implementations.

**Out of scope.** UV-specific I/O; event sources.

**Dependencies.** Phase 4.

**Verification.** Unit tests for sleep ordering, wakeups, foreground/background
termination, background cancellation, deadlock detection, and incompatible
scheduler/timer rejection.

## Phase 6 — Events, extension points, hook/class dispatch, and class adapter

**Goal.** Generalize event and lifecycle handling into declared contracts with
qualified dispatch.

**Deliverables.**

- Qualified event names with payload schemas, handler cardinality, and ordering
  semantics owned by the contributing plugin/component.
- Reserved core namespace for lifecycle phases with helper constants.
- Extension-point dispatch for hook-driven runtimes.
- Class adapter mapping qualified extension-point IDs to class method names, with
  duplicate-mapping and method-name-clash compile errors.
- Event sources contract: producers poll or emit normalized events.
- Handler fan-out and ordering policy as declared per extension point.

**Out of scope.** Concrete SDL/UV event sources.

**Dependencies.** Phase 5.

**Verification.** Unit tests for qualified dispatch, payload validation, cardinality,
class method mapping and clashes, inferred hook execution, and extension-point
contract violations.

## Phase 7 — UV async component

**Goal.** Rebuild `uv` as composable components on the new graph.

**Deliverables.**

- UV loop resource component with ownership/cleanup.
- UV clock component.
- Asynchronous operation components (`uv.spawn`, `uv.scandir`) as declared scheduler
  capabilities, hiding the callback boundary.
- Sleep handler integrated with the Phase 5 timer contract.
- Shutdown draining and loop teardown through the ownership graph.

**Out of scope.** SDL, graphics.

**Dependencies.** Phase 6.

**Verification.** Unit tests for subprocess capture, directory scanning, error paths,
shutdown while work is pending, and loop re-creation across runs.

## Phase 8 — SDL window, subsystem, and input event source

**Goal.** Decompose the SDL window/input portion of the `sdl3` drivers.

**Deliverables.**

- SDL subsystem/init component owning flags and teardown.
- Window resource component from properties, with default sizing.
- Input event source normalizing key, mouse, resize, close, and focus events.
- Event polling operation contributed to the progress engine.
- Compile-time capability composition so a window can be used with and without
  graphics.

**Out of scope.** Graphics contexts, frame presentation.

**Dependencies.** Phase 7.

**Verification.** Unit/headless tests for event normalization and window lifecycle;
manual smoke via `./build/rig` for a window-only example.

## Phase 9 — Graphics context capabilities (renderer, GL, GPU)

**Goal.** Model renderer, OpenGL, and GPU device resources as capability providers.

**Deliverables.**

- Renderer-as-graphics-context component.
- OpenGL context component (attributes, profile, swap interval).
- GPU device component (shader formats, debug mode, backend name, device setup).
- Capability contracts so frame presentation and rendering services can select a
  graphics context without naming a concrete backend.
- Rollback of partial graphics initialization.

**Out of scope.** Frame lifecycle; font/mesh/shader services.

**Dependencies.** Phase 8.

**Verification.** Compile-time selection tests and headless tests where possible; GPU
and GL smoke tests via `./build/rig`.

## Phase 10 — Frame lifecycle and presentation

**Goal.** Separate frame phases and presentation from a particular graphics API.

**Deliverables.**

- Frame lifecycle phases (`before_frame`/`after_frame`) as extension points.
- Presentation component selected per graphics context.
- Vsync, fullscreen, and resize behavior expressed as component capabilities.
- Frame profiling hooks attached to lifecycle phases rather than app base classes.

**Out of scope.** Rendering services.

**Dependencies.** Phase 9.

**Verification.** Lifecycle ordering tests; resize/vsync/fullscreen smoke tests.

## Phase 11 — Rendering services via capabilities

**Goal.** Replace the service registry with per-plugin capabilities for `font`,
`shader`, `mesh`, and the GL resolver.

**Deliverables.**

- Capability definitions replacing `font.renderer`, `shader.stage`,
  `mesh.vertex_input`, and `gl.resolver`.
- `font`, `shader`, `mesh`, and `glx` rewritten to consume capabilities from `ctx`
  instead of `rig.require_service`.
- Removal of service registration from those modules (compatibility registry may
  remain until Phase 13).

**Out of scope.** Bundles and example migration.

**Dependencies.** Phase 10.

**Verification.** Existing `font`, `shader`, `mesh`, `gl`, and `glx` tests migrated to
the new API and passing.

## Phase 12 — Convenience bundles and preset reassembly

**Goal.** Reassemble current configurations as explicit bundles of components.

**Deliverables.**

- Bundle helpers reproducing the behavior of `sdl3`, `sdl3_gl`, `sdl3_gpu`, `uv`, and a
  headless/test configuration.
- Bundles composed only of explicit components; `:use(plugin)` alone changes no
  behavior.
- Parity tests showing bundles produce the same `ctx` shape and lifecycle as the old
  presets.

**Out of scope.** Deleting the old model.

**Dependencies.** Phase 11.

**Verification.** Bundle parity tests plus the migrated example suite.

## Phase 13 — Migrate examples and tests; remove the old runtime model

**Goal.** Retire `rig.run`, the service registry, and driver/preset/hook registration.

**Deliverables.**

- `examples/` and `tests/` rewritten to the builder/compiler/start model across all
  three execution forms.
- Removal of `rig.run`, `rig.App`, `rig.Runtime`, `rig.register_runtime_driver`,
  `rig.register_runtime_preset`, `rig.register_runtime_hook`, `rig.register_service`,
  `rig.register_service_provider`, and `rig.require_service`.
- Removal of `mode`/`driver`/`providers`/`module_config`/`driver_config` in favor of
  component options.
- Updated module `.md` documentation.

**Out of scope.** Optional/deferred work listed in `PLAN.md`.

**Dependencies.** Phase 12.

**Verification.** `make test` green; every example runs via `./build/rig`; no
remaining references to removed APIs anywhere in `src/`, `tests/`, `examples/`, or
`scripts/`.

## Deferred beyond Phase 13

The following remain explicitly out of scope for the initial implementation and are
tracked here so they are not silently dropped:

- mixed execution models;
- preemptive or multithreaded scheduling;
- runtime startup arguments;
- source-generating Fennel macros and runtime `eval`;
- static Lua function signature/type checking;
- advanced event fan-out semantics and handler ordering policy;
- descriptor or compiled-plan serialization.
