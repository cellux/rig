# Rig Runtime Composition Redesign

## Purpose

This document is the initial implementation plan for replacing Rig's immediate `rig.run(options)` runtime model with a compositional builder/compiler/start model. It records the intended architecture, scope, migration strategy, and verification approach for review before implementation begins.

## Goal

Replace the current driver-owned `rig.run` model with a Lua-first runtime composition system in which:

1. plugins are loaded explicitly and attached to a fluent builder;
2. builder calls perform only data transformations and local registration;
3. `:compile()` validates and lowers the descriptor into a single-use runtime object without acquiring external resources;
4. `runtime:start()` initializes all resources, constructs the runtime dependency context, runs the selected execution model, and performs deterministic cleanup;
5. current behavior is reassembled from smaller composable components rather than preserved through a compatibility layer.

The design should make partial evaluation concrete: configuration, capability selection, dependency resolution, event/lifecycle graph construction, and dispatch specialization happen before startup, while resource acquisition and operational side effects happen only at startup.

## Design principles

- Lua remains the initial implementation language. Fennel migration, source-generating macros, and runtime `eval` are optional future work, not prerequisites.
- The builder is mutable for convenience, but compilation is side-effect-free with respect to external resources.
- A compiled runtime is single-use and receives no startup options initially; all configuration is frozen before `:start()`.
- Runtime behavior must not depend on module load order.
- Plugins are ordinary values returned by top-level `require`; `:use(plugin)` attaches them to a particular builder/runtime composition.
- The core builder remains generic. Plugins provide helper constructors and bundles that return component descriptors.
- Capability contracts and dependency bindings are distinct. Capabilities are anonymous contracts used for composition; `name` is the user-visible key installed in `ctx`.
- User application code receives one plain table `ctx`, indexed by configured names. Values in that table expose component-specific APIs.
- Scheduling is cooperative and single-threaded; preemptive scheduling is out of scope.
- All runtime-created resources belong to a runtime ownership graph and are rolled back on startup failure or released in reverse order on shutdown.
- A single lean progress engine owns top-level progress and termination; selected components fill its extension points for polling, draining, deadlines, waiting, presenting, and stop detection.
- Compilation errors concern descriptor/graph facts; startup errors concern environment and resource acquisition facts, and startup errors must identify the failing component.

## Target user experience

The exact helper names are provisional, but the intended shape is:

```lua
local rig = require("rig")
local sdl3x = require("sdl3x")
local uv = require("uv")

local runtime = rig.runtime()
   :use(sdl3x)
   :use(uv)
   :add(sdl3x.window {
      name = "window",
   })
   :add(sdl3x.input {
      name = "input",
   })
   :add(sdl3x.opengl {
      name = "graphics",
   })
   :execute(function(ctx)
      -- Application code may pass ctx or selected values onward.
      local window = ctx.window
      local graphics = ctx.graphics
   end)
   :compile()

runtime:start()
```

The three initial execution forms are:

- `:execute(function)` for function-driven execution;
- `:execute(AppClass)` for class-driven execution, with the instance created only after dependencies and resources are initialized;
- inferred hook-driven execution when the user attaches `:on(qualified-name, handler)` handlers without calling `:execute`.

The initial compiler rejects missing execution configuration and rejects mixing standalone builder handlers with a supplied function/class execution form. Class methods remain part of class-driven execution. Mixed execution may be added later.

Termination rules are initially:

- returning from a function-driven `main(ctx)` requests runtime shutdown;
- class- and hook-driven runtimes continue until an explicit stop request or a supplied event/source requests termination;
- the initial coroutine `main` task is foreground by default;
- foreground tasks keep the runtime alive, while background tasks do not;
- `scheduler:spawn(fn)` creates a foreground task by default, with an explicit background option;
- completion of the last foreground task requests shutdown;
- shutdown cancels remaining background tasks and gives them an opportunity to run cleanup/finally behavior before resource teardown.

## Runtime composition model

### Plugins

A plugin returned by `require` should be self-contained and should not mutate a global runtime registry. Attaching it with `builder:use(plugin)` makes its component constructors, capability definitions, extension-point contracts, schemas, and lifecycle/resource implementations available to that builder.

`:use(plugin)` makes definitions available but adds no runtime behavior. A plugin helper returns a descriptor; `:add(descriptor)` is required to add that behavior. Descriptors record their originating plugin, and adding a descriptor from an unattached plugin is an error. Duplicate plugin attachment is an error. The strict rules may be loosened later, but are intentional initially.

Plugins may provide:

- component helper constructors and common bundles;
- capability and requirement definitions;
- resource factories and cleanup logic;
- event sources and event contracts;
- lifecycle phases and ordering constraints;
- scheduler operations and wakeup integrations;
- clock/timer implementations;
- asynchronous operations;
- window/input/graphics/presentation components;
- dependency bindings and default provider priorities.

### Components and capabilities

A component descriptor should internally declare its capabilities and standard requirements; users should normally provide only its `name` and domain-specific options. Advanced overrides may add constraints or alter selection without requiring users to repeat `provides` metadata.

Component identity, capability identity, and context binding name are separate. A component may expose no public object, or one public top-level object under `name`; sub-objects remain behind that object's component-specific API. Capabilities are anonymous contracts used for composition and are not automatically inserted into `ctx`.

Components can:

- provide capabilities;
- require capabilities or named dependencies;
- expose one or more named objects in `ctx`;
- define pure compatibility predicates in addition to declarative properties;
- contribute lifecycle phases, events, handlers, or scheduler operations;
- create runtime-scoped resources during startup;
- register cleanup in the runtime ownership graph.

Capability selection should first use declarative properties and then optional pure plugin predicates. Candidate implementations have deterministic priorities. Compilation rejects absence, ambiguity, ties, contradictory constraints, and unsupported combinations.

### Dependency context

The compiler builds a dependency graph and determines a valid initialization order. At startup, each component receives access to already initialized prerequisites and produces its runtime object. The resulting `ctx` is a plain table keyed by configured component `name` values; components that have no public object do not add a binding. Sub-objects are accessed through the top-level component API. Runtime-scoped dependencies are initialized once per runtime and released in reverse dependency/acquisition order.

Top-level plugin modules expose pure builder helpers, schemas, constants, and compile-time metadata. Runtime-dependent operations are exposed through objects installed in `ctx`; no runtime resource should require a module-global accessor. Pure utilities may remain ordinary functions.

The design should support dependency requirements such as:

- a monotonic clock;
- a timer/wakeup mechanism compatible with the selected scheduler;
- event dispatch or a particular event source;
- a graphics API or presentation capability;
- asynchronous operation families;
- services formerly represented by the global service/provider registry.

### Execution

Execution is a component selected by the builder/compiler:

- function execution calls the user function with `ctx` directly when no scheduler is assembled;
- when a cooperative scheduler is assembled, the same function is spawned as the initial foreground coroutine, so scheduler composition selects coroutine semantics without a second execution API;
- class execution constructs the user class at startup with `ctx`, then dispatches its declared lifecycle/event methods;
- hook-driven execution uses builder-attached handlers and runtime-provided extension points.

Function and class execution forms are accepted directly by `:execute`. For a function, the presence of a scheduler selects coroutine execution; its absence selects direct execution. Hook-driven execution is inferred from `:on(...)` registrations when no explicit execution form is supplied. Standalone builder hooks cannot be combined with function/class execution initially. The design must preserve the ability to combine a scheduler with event sources and timers when their declared capabilities are compatible, while rejecting unsupported combinations before startup.

The class adapter consumes the same qualified extension-point contracts as hook-driven execution. Each plugin defines the mapping from qualified extension-point IDs to ergonomic class method names; duplicate mappings and method-name clashes are compile errors. Qualified IDs remain the external contract even when class methods use names such as `on_resize`.

A single lean progress engine owns the top-level loop. It exposes extension points for selected components to contribute scheduler draining, event polling, timer deadlines, async waiting, frame production/presentation, and stop detection. It contains no SDL-, UV-, or graphics-specific behavior.

## Progress engine

The compiler selects exactly one progress engine for an assembled runtime. The engine is intentionally small and policy-oriented. It coordinates component-provided operations such as:

- draining ready scheduler work;
- polling event sources;
- waking due timers;
- waiting for asynchronous progress until a deadline or event;
- running frame lifecycle/presentation work;
- observing explicit stop requests and foreground-task completion.

Components explicitly added to the builder contribute these operations. The compiler does not silently instantiate additional components from attached plugins. Convenience bundles may add several components explicitly, but `:use(plugin)` alone never changes runtime behavior.

The progress engine must support the execution-specific termination rules while keeping component-specific progress logic outside the engine.

## Composable runtime parts

The first architecture should model these as separate parts, with convenience bundles reassembling common configurations:

1. **Execution** — function, coroutine, class, or inferred hook-driven execution.
2. **Coroutine scheduler** — cooperative, single-threaded task execution and suspension.
3. **Event definitions and dispatch** — qualified event names, payload contracts, handler attachment, cardinality, and ordering.
4. **Event sources** — producers that poll or emit normalized events.
5. **Clock** — wall-clock and/or monotonic time access.
6. **Timers/wakeups** — deadline scheduling compatible with the selected scheduler; preferably bundled with compatible scheduler implementations but conceptually separate.
7. **Asynchronous operations** — named scheduler capabilities such as process spawning, directory scanning, and future I/O families.
8. **Window resources** — creation, ownership, state, and window-specific capabilities.
9. **Input/window event sources** — normalized key, mouse, resize, close, focus, and related events.
10. **Graphics context/device** — renderer, GPU device, or OpenGL context resources.
11. **Rendering services** — shader, mesh, texture, font, and related capabilities.
12. **Frame lifecycle and presentation** — frame phases and presentation independent from a particular graphics API.
13. **Lifecycle phase graph** — qualified phases, ordering constraints, and handler contracts.
14. **Dependency container** — runtime-scoped named bindings and initialization/cleanup graph.
15. **Resource ownership** — rollback and reverse-order release for all startup resources.

The compiler should treat the composition as a graph rather than as a monolithic driver. A common SDL desktop configuration, a UV async configuration, a headless test configuration, and future combinations should be bundles of explicitly added parts. The compiler selects among implementations contributed by those parts; it does not invent missing runtime behavior from merely attached plugins.

## Event and extension-point contracts

Non-core events and hooks use qualified names owned by their contributing plugin/component. Core phases use a reserved namespace and helper constants. Each extension point declares:

- qualified name;
- lifecycle timing;
- payload schema;
- accepted handler form;
- whether fan-out is supported;
- ordering semantics;
- failure behavior.

The initial compiler verifies event existence, handler callability, payload/extension-point declarations, and cardinality rules. Lua function signatures are not inferred; richer signature validation can be added later through explicit wrappers or annotations. Handler fan-out and duplicate-handler ordering policy remain deferred, but extension points must declare what they accept and the compiler must validate the declared contract.

## Current implementation inventory and migration work

The implementation must inventory the current public knobs across the full repository and classify each as retained, reshaped, deferred, or dropped before removing the old model. The inventory should include at least:

### Current runtime-level knobs

- `mode`/preset selection;
- explicit driver selection;
- service/provider mappings;
- runtime module configuration;
- driver configuration;
- app class selection;
- app lifecycle methods and event methods;
- global runtime hooks;
- driver-defined phases and event names;
- current `uv.main` entrypoint;
- current SDL render callback selection.

### Current execution and scheduling behavior

- UV main coroutine startup and task-draining termination;
- SDL frame/event polling loop;
- SDL scheduler draining once per frame;
- `sched.sleep` implementations for UV and SDL;
- async operations (`uv.spawn`, `uv.scandir`, and related handler registration);
- scheduler activation/deactivation and deadlock behavior.

### Current time and event behavior

- `time.now` and `time.monotonic` providers;
- SDL input normalization for key and mouse events;
- resize detection and initial resize dispatch;
- runtime event forwarding to app methods;
- poll/drain/frame lifecycle phases.

### Current window and graphics behavior

- SDL initialization flags and subsystem ownership;
- window properties and creation callbacks;
- fullscreen and vsync options;
- renderer creation and presentation;
- GPU shader formats, debug mode, backend name, and device setup;
- OpenGL attributes, context profile, swap interval, and context setup;
- frame profiling;
- app-owned resources and font faces.

### Current ordinary module/resource knobs

- animator fixed timestep, maximum delta, maximum steps, and startup behavior;
- shader source/path/language/stage/include/macro/property configuration;
- shader compiler and shader-cross compilation options;
- profiler FPS/history configuration;
- statistics metric bundles;
- resource and service APIs exposed by font, mesh, scenegraph, shader, SDL, GL, and related modules.

The inventory should also search `tests/`, `examples/`, and `scripts/`, not only `src/`, so that existing use cases and implicit public APIs are accounted for.

## Migration strategy

No backward compatibility layer is required. The implementation may change or remove public APIs freely because the project has a single author and no external users.

The migration should reshape the modules themselves where practical:

- replace global service/provider registration with per-plugin capability/component definitions;
- remove driver-owned monolithic loops in favor of composable execution, scheduler, event, timer, graphics, and presentation parts;
- move module-global runtime state into runtime-scoped component instances;
- replace `rig.require_service` with named `ctx` bindings;
- turn current runtime presets into convenience bundle helpers;
- adapt or rewrite examples and tests to use the builder/compiler/start model;
- remove `rig.run` once the new path is verified;
- retain ordinary resource concepts only where they fit the new dependency and ownership model, reshaping their APIs when necessary.

## Compiler and startup pipeline

The planned pipeline is:

1. **Load plugins** with top-level `require`.
2. **Construct descriptor** through a mutable fluent builder.
3. **Freeze/read the descriptor** for compilation without acquiring resources.
4. **Validate component configuration** using plugin schemas.
5. **Collect capabilities, requirements, bindings, events, phases, and scheduler operations.**
6. **Resolve capability candidates** using declarative constraints, pure predicates, and priorities.
7. **Detect missing capabilities, ambiguity, incompatible combinations, cycles, invalid extension points, class method clashes, invalid plugin attachment, and invalid execution selection.**
8. **Build deterministic dependency, lifecycle, event, progress-engine, and resource graphs.**
9. **Lower the graph** into a single-use runtime plan with precomputed dispatch and operation tables/closures.
10. **Return a compiled runtime object** with explicit state `compiled`; no external side effects occur.
11. **Start the runtime** by transitioning through `starting`, creating a root ownership scope, initializing resources in graph order, assembling `ctx`, constructing the selected application execution object, and entering the progress engine.
12. **On startup failure**, identify the failing component, aggregate cleanup errors while continuing all cleanup, transition to `failed`, and release every acquired resource.
13. **On normal termination**, transition through `stopping`, cancel remaining background tasks, run cleanup/finally behavior, release resources in reverse order, and transition to `stopped`.
14. **Reject invalid state transitions**, including double start and use after stopped/failed.

Source-code generation and `eval` are explicitly not required for this pipeline. They may be considered later if measurements show that generated dispatch or specialized scheduler code is valuable.

## Initial implementation boundaries

The first implementation should establish the graph, plugin, builder, compiler, runtime, context, lifecycle, progress-engine, and ownership foundations using fake/headless components before migrating representative current configurations:

- plugin attachment and strict descriptor ownership rules;
- a minimal direct function runtime;
- a cooperative scheduler with `sleep`;
- a UV-like async runtime;
- a hook-driven event runtime;
- a class-driven SDL-like window/input/frame runtime;
- at least one graphics variant;
- a headless/test runtime.

Each migrated vertical slice must demonstrate that the same generic composition machinery handles it. Common bundles should be added only after their underlying components work independently.

Potentially deferred work includes:

- mixed execution models;
- preemptive or multithreaded scheduling;
- runtime startup arguments;
- source-generating Fennel macros and `eval`;
- static Lua function signature/type checking;
- advanced event fan-out semantics and handler ordering policy;
- serialization of descriptors or compiled plans.

## Verification expectations

- Use unit tests for builder mutation, plugin attachment, descriptor validation, capability selection, constraints, priorities, graph ordering, execution selection, context bindings, extension-point contracts, rollback, and cleanup.
- Migrate existing behavior tests for scheduling, time, events, SDL lifecycle, graphics setup, and resource ownership.
- Add negative tests for absent capabilities, ambiguity, priority ties, incompatible scheduler/timer combinations, invalid handler contracts, class method clashes, cycles, duplicate names, mixed execution modes, invalid plugin attachment, startup failure rollback, cleanup-error aggregation, task cancellation, and double start.
- Update examples to demonstrate concise helper-based configurations and the three execution forms.
- Use `make test` for final verification, rebuilding before smoke tests whenever source modules, C code, or build inputs require it, in accordance with repository instructions.

## Open points for review before implementation

- Exact names and shape of plugin, component, capability, requirement, and extension-point records.
- Exact fluent builder core methods and helper naming conventions.
- Event handler fan-out and ordering policy.
- The precise initial inventory classification of every current knob.
- How much of each ordinary resource module must be rewritten in the first implementation.
