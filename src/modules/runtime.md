# `runtime`

Builder/compiler foundation for the compositional runtime model.

This module is the implementation behind `rig.runtime()`. It provides plugin values,
component descriptors, a mutable builder, and a side-effect-free `:compile()` that
produces a compiled runtime object. It intentionally performs no capability resolution,
dependency ordering, execution, or resource acquisition yet; those arrive in later
phases.

## API

- `rig.runtime()`
  - Returns a fresh `runtime.Builder` in state `"building"`.
- `runtime.Builder`
  - Builder class. Instances expose `state` and the fluent methods below.
- `runtime.Compiled`
  - Compiled runtime class returned by `builder:compile()`.
  - Instances expose `state` (`"compiled"`), `plugins`, `descriptors`, `handlers`, and
    `execution`.
  - `compiled:startup(fn)` registers the async startup phase: `fn(ctx)` is spawned as a
    background scheduler task and frames are withheld until it completes.
  - `compiled:startup_pending()` reports whether that task is still running;
    `compiled:startup_stalled()` reports a pending startup with no progress possible.
- `runtime.plugin(spec)`
  - Validates and returns a plugin value.
  - `spec.id` is required and must be a non-empty string.
  - Optional table fields: `components`, `capabilities`, `requirements`,
    `extension_points`, `schemas`, `resources`.
- `runtime.descriptor(plugin, spec)`
  - Builds a component descriptor tagged with its originating `plugin`.
  - `spec` is copied; `spec.name` is optional but must be a non-empty string when
    present.

## Builder methods

- `builder:use(plugin)`
  - Attaches a plugin to this builder.
  - Duplicate attachment (same plugin value or same `id`) is an error.
  - Attaching makes the plugin available; it adds no runtime behavior by itself.
- `builder:add(descriptor)`
  - Records a component descriptor.
  - The descriptor must originate from a plugin attached to this builder.
  - `descriptor.name`, when present, must be a non-empty string.
- `builder:on(name, handler)`
  - Records a named handler registration. Dispatch is added in a later phase.
- `builder:execute(fn_or_class)`
  - Records the single execution form. Only one may be selected.
- `builder:compile()`
  - Freezes the builder and returns a `runtime.Compiled` snapshot.
  - Performs no external side effects and acquires no resources.
  - Code must not call it twice, and the builder rejects all mutation afterwards.

## Capability declarations

A plugin may declare the capabilities it owns through `plugin.capabilities`, a map from
capability id (non-empty string) to a declaration table:

```lua
plugin.capabilities = {
   ["graphics.context"] = {},
}
```

Capabilities are anonymous composition contracts; they are not installed into `ctx`.
Every capability referenced by a component's `provides` or `requires` must be declared
by some attached plugin.

## Component descriptors

Beyond `name`, `runtime.descriptor` accepts these fields, normalized and validated at
compile time:

- `provides`
  - Array of capability ids or `{ capability, priority?, properties? }`.
  - `priority` defaults to `0` and is used to select among candidates.
  - `properties` are declarative facts used for requirement matching.
- `requires`
  - Array of capability ids or `{ capability, properties?, predicate?, optional? }`.
  - `properties` must match the provider's properties exactly.
  - `predicate(descriptor)` is an optional pure filter over a candidate descriptor.
  - `optional` allows the requirement to remain unresolved.
- `excludes`
  - Array of capability ids this component is incompatible with. If another component
    in the composition provides one, compilation fails.
- `config` / `config_schema`
  - `config` is validated through `config_schema` (a `schema` object) at compile time
    and normalized into `plan.components[i].config`.

## Extension points

A plugin may declare extension points through `plugin.extension_points`, a map from
qualified name to a declaration table:

- `cardinality` is `"many"` (default) or `"single"`.
- `order` is `"registration"` (default) or `"reverse"`.
- `method` maps the extension point to a class method name for class execution.
- `payload` is an optional schema object describing the handler payload.

The following core extension points are always available and use the reserved `core.`
namespace: `core.before_setup`, `core.after_setup`, `core.before_shutdown`,
`core.after_shutdown`. Plugin extension points must not redeclare them; each maps to
its matching class method.

`builder:on(name, handler)` registrations are validated at compile time: the name must
exist, and `"single"` extension points reject more than one handler.

## Event dispatch

`compiled:emit(name[, payload])` dispatches an extension point:

- the name must be a declared extension point;
- if the declaration has a `payload` schema, the payload is validated through it;
- registered handlers run in registration or reverse order as declared;
- under class execution, the declaration's `method` is invoked on `compiled.instance`
  when it is implemented.

Core lifecycle phases are emitted automatically: `core.before_setup` before component
instantiation, `core.after_setup` after the class instance is constructed,
`core.before_shutdown` before scheduler/resource teardown, and `core.after_shutdown`
after teardown.

Components may contribute an event source through `descriptor.event_source`:

- `events` is an optional array of qualified names the source may emit; each must be a
  declared extension point.
- `poll(context)` is called once per progress-engine step with a context whose `emit`
  method forwards to `compiled:emit`.

## Compilation

`builder:compile()` produces `compiled.plan`:

- `order`
  - Dependency-ordered component array (providers before consumers), deterministic.
- `components`
  - Component records in descriptor order, with normalized `provides`, `requires`,
    `excludes`, and optional `config`.
- `bindings`
  - Map from context binding `name` to component.
- `capabilities`
  - Declared capabilities across attached plugins.
- `providers`
  - Map from capability id to candidate `{ component, entry }` providers.
- `resolved`
  - Map from component to its resolved requirements (`{ requirement, provider?, ... }`).
- `dependencies` / `dependents`
  - Adjacency maps derived from resolved requirements.
- `extension_points`
  - Merged extension-point declarations, including core ones.
- `handlers`
  - Map from extension-point name to handler array in registration order.

Compile failures leave the builder in `"building"` state so it can be corrected and
recompiled; no resources are acquired at any point.

## Execution forms

The compiler selects exactly one execution form:

- `function` — `:execute(function)` with no handlers. The function is called with `ctx`;
  returning from it requests shutdown.
- `class` — `:execute(AppClass)`. The class is constructed with `ctx` at startup, and
  the instance is stored as `compiled.instance`.
- `hooks` — no `:execute(...)` but one or more `:on(...)` handlers. The progress engine
  runs until a stop is requested.

Compilation rejects missing execution configuration (no execution and no handlers) and
mixing builder handlers with a function/class execution form.

## Startup and lifecycle

`compiled:start()` drives the runtime state machine:

`compiled` -> `starting` -> `running` -> `stopping` -> `stopped`, or `failed` on any
startup or run error. A failed start re-raises the original error and records it as
`compiled.error`. Starting a runtime that is not `compiled` (including double start and
start after `stopped`/`failed`) is rejected. `compiled:stop()` is only valid while
`running` and requests orderly termination.

### Async startup phase

A class may register `compiled:startup(fn)` from its `after_setup` hook. `fn(ctx)` runs
as a **background** scheduler coroutine, so returning from it does not stop the runtime;
it may `sched.await`/`sched.sleep` like any other task. While it is pending, the
progress engine skips `frame` handlers, so the first frame is produced only after
startup completes. Errors raised inside the startup task surface from `compiled:start()`.
If a startup task waits with no ready work, pending async, or timer deadline, the runtime
fails fast (`runtime startup task is waiting but no progress is pending`) instead of
spinning.

## Context and component instantiation

At startup the runtime creates `ctx` and instantiates components in `plan.order`
(provider-first):

- `descriptor.create(context)` is optional and returns the component's runtime value.
- If a component has a `name` and `create` returns a non-nil value, it is installed as
  `ctx[name]`. Components without a value add no binding.
- The `context` passed to `create` exposes `plan`, `ctx` (bindings created so far),
  `values`, `component`, and `requires`.
- `requires` is the component's resolved requirements; each entry has `requirement`,
  `provider` (component record or `nil`), `value` (the provider's created value or
  `nil`), and `binding` (the provider's `name` or `nil`).
- `context.adopt(resource, release_fn)` registers an extra resource in the runtime
  ownership graph.
- `descriptor.release(value)` is optional; when present and the component produced a
  non-nil value, the value is adopted for release.

## Resource ownership

Every runtime owns a `runtime.ResourceScope` (`compiled.resources`). Resources are
adopted in acquisition order and released in reverse order.

- `compiled.ctx.resources` exposes the runtime root scope to the execution class, so
  class-owned resources (for example a scene graph's per-object scopes) can be adopted
  into the same graph and released by the runtime at teardown.
- `runtime.ResourceScope:replace(owner, key, resource, release_fn)` releases the
  previous resource registered under `key` and adopts the new one.

- On normal shutdown, resources are released after execution completes; if any release
  fails, cleanup continues for all remaining resources and the runtime transitions to
  `failed` with an aggregated error.
- On startup failure, all resources acquired so far are rolled back before the runtime
  transitions to `failed`, and the original startup error (which names the failing
  component) is combined with any cleanup errors.
- `runtime.ResourceScope:release()` returns an array of per-entry error strings and is
  idempotent.

## Progress engine

The compiler selects the built-in `runtime.ProgressEngine`. Components may contribute
operations through `descriptor.progress`:

- `poll`, `drain`, `frame`, `wait` — run once each per step, in component order.
- `should_stop(context)` — returns true to terminate the loop.
- `deadline` — reserved for later async phases.

Each operation receives a step context with `runtime`, `plan`, `component`, `form`,
`ctx`, and `step`. Function execution runs `main(ctx)` once and stops when no scheduler
is assembled; when a scheduler is assembled, `main` is spawned as the initial
foreground coroutine instead. Class and hooks execution run the engine until
`should_stop` returns true or `runtime:stop()` is called.

## Clock, timer, and scheduler components

The runtime provides foundational clock/timer/scheduler helpers, all created through a
plugin returned by `runtime.scheduler_plugin()`:

- `runtime.ManualClock([initial])` — deterministic clock with `now()`, `monotonic()`,
  `advance(seconds)`, and `wait(seconds)`.
- `runtime.Clock(options)` — function-backed clock (`now`, `monotonic`, optional
  `wait`); backend modules supply real implementations.
- `runtime.Timer()` — one-shot deadline queue with `schedule(deadline, callback)`,
  `cancel`, `next_deadline()`, and `advance(now)`.
- `runtime.Scheduler(spec)` — cooperative scheduler owning a `sched.Scheduler`, a clock,
  and a timer, with `spawn`, `spawn_background`, `join`, `yield`, `park`, `sleep`,
  `now`, and `monotonic`. `scheduler:block(fn)` runs `fn` to completion in a
  synchronous context (advancing timers and pumping I/O); `scheduler:set_pump(fn)`
  installs the I/O pump it uses (for example the `uv` loop).

Component constructors `runtime.clock_component(plugin, options)`,
`runtime.timer_component(plugin, options)`, and
`runtime.scheduler_component(plugin, options)` produce descriptors that provide the
`sched.clock`, `sched.timer`, and `sched.scheduler` capabilities. The scheduler
requires a clock and timer with `protocol = "sched"`, so incompatible implementations
are rejected at compile time.

### Foreground, background, and shutdown

`should_stop` is `had_foreground and foreground_count == 0`, which drives the rules:

- `spawn` creates a **foreground** task; `spawn_background` creates a task that does not
  keep the runtime alive.
- The runtime stays alive while any foreground task is unfinished; completion of the
  last foreground task requests shutdown.
- Function `:execute(fn)` runs as the initial foreground task. Class/frame apps have no
  foreground task and stay alive through the progress engine's own stop conditions
  (window close, `runtime:stop()`), not through the scheduler.
- The async **startup task is background**, so finishing `startup` does not stop the app
  (D7); a foreground keepalive is not needed.
- A foreground task waiting with no ready work, pending async, or timer deadline is
  reported as a deadlock.

Shutdown order (`compiled:_teardown`): emit `core.before_shutdown`; wake remaining
background tasks with `runtime.CANCELLED` and drain once so they can clean up; complete
all outstanding async tickets (`scheduler:cancel_async`) so later backend callbacks are
no-ops; release resources in reverse order. Releasing the `uv` loop drains in-flight
requests while their Lua callbacks are still rooted, then closes the loop. `_tickets`
and late `ticket:wake`/`:fail` calls are guarded so a callback that lands after its task
has been cancelled or completed cannot wake a dead task.

- `scheduler:block` records the calling script so path-relative helpers (such as
  `asset`) resolve against it, since the blocking function runs in a fresh coroutine.

## Notes

- The runtime builder (`runtime.Builder` / `runtime.Compiled`) is the compositional
  foundation; the legacy `rig.run` model has been removed.
- `descriptor.create` runs during `starting`; resources it acquires should be released
  through `descriptor.release` or `context.adopt`.

- The builder is mutable for convenience; the compiled object is a snapshot with its
  own `plugins`, `descriptors`, and `handlers` arrays.
- Plugin shape validation is structural only at this stage. Component configuration
  schemas and capability resolution are validated at compile time in later phases.

## Convenience Bundles

`runtime.headless_bundle(builder, options)` attaches the scheduler plugin and adds a
clock, timer, and scheduler with no I/O, for tests and headless runtimes.
`options.clock` and `options.timer` may supply instances.
