# Current API and Behavior Inventory

## Purpose

This is the Phase 0 deliverable defined in `PHASES.md`. It inventories every current
public knob and runtime behavior across `src/`, `tests/`, `examples/`, and `scripts/`
and classifies each as:

- **R (Retained)** — concept survives with essentially the same meaning.
- **Rp (Reshaped)** — concept survives but its API, ownership, or location changes.
- **D (Deferred)** — intentionally postponed; not part of the initial implementation.
- **X (Dropped)** — removed; replaced by a different concept or no longer needed.

The classification feeds `PHASES.md`. "Phase N" refers to the phase that performs the
change. Nothing here is deleted before Phase 13; new code must not depend on the old
model (D15 in `DECISIONS.md`).

## How to read the tables

- **Current form** names the concrete option, function, or method and where it lives.
- **Disposition** is one of R/Rp/D/X.
- **Where / rationale** points to the governing phase and the reason.

---

## 1. Runtime-level knobs

| Item | Current form | Disposition | Where / rationale |
| --- | --- | --- | --- |
| Mode selection | `rig.run{ mode = "sdl3" \| "sdl3_gl" \| "sdl3_gpu" \| "uv" }` | X | Phase 12–13. Replaced by explicit `rig.runtime():use(...):add(...)` bundles. |
| Explicit driver selection | `rig.run{ driver = "<id>" }` | X | Phase 13. Replaced by explicitly added components. |
| Service/provider mapping | `rig.run{ providers = { service_id = provider_id } }` | X | Phase 11/13. Replaced by capability selection and explicit component choice. |
| Runtime module config | `rig.run{ module_config = { <module> = {...} } }` | Rp | Phases 5–12. Becomes the owning component's options. |
| Runtime driver config | `rig.run{ driver_config = { <driver> = {...} } }` | Rp | Phases 8–10. Split into window/input/graphics/presentation component options. |
| App selection | `rig.run{ app = AppClass }` | Rp | Phase 3. Becomes `builder:execute(AppClass)` or `builder:execute(function)`. |
| `rig.App` base class | `rig.App` (also `animator.App`, `sdl3x.App`, `sdl3x.SceneApp`) | Rp | Phases 3/6/10. Class execution + extension-point contracts replace base-class phase methods. |
| `rig.Runtime` | `rig.Runtime` instance created by `rig.run` | Rp | Phases 3/4. Replaced by the compiled runtime object and state machine. |
| `rig.run` | top-level entry point | X | Phase 13, after all callers migrate. |
| `rig.register_runtime_hook` | global phase hooks | X | Phase 6/13. Replaced by `builder:on(...)` and component-contributed extension points. |
| Driver-declared phases | `driver.driver_phases` | Rp | Phase 6. Becomes declared extension-point contracts (qualified where non-core). |
| Driver-declared events | `driver.events` (`key`, `mouse`, `resize`) | Rp | Phase 6/8. Becomes normalized event contracts owned by the input source component. |
| `rig.register_runtime_driver` | driver registry | X | Phase 13. Replaced by components. |
| `rig.register_runtime_preset` | preset registry (driver + providers) | Rp | Phase 12. Becomes convenience bundle helpers, then removed. |
| `sdl3x` runtime accessors | `sdl3x.get_window/get_renderer/get_gpu_device/get_gl_context` | Rp | Phases 8–11. Values move into `ctx.window`/`ctx.graphics` (etc.); module-global accessors removed. |
| `rig.require_service` | global service lookup | X | Phase 11/13. Replaced by named `ctx` bindings. |
| `rig.register_service` | service definition registry | X | Phase 11/13. Replaced by capability definitions. |
| `rig.register_service_provider` | provider registry | X | Phase 11/13. Replaced by component capability providers. |
| `mode` provider overrides | preset `providers` + `options.providers` merge | X | Phase 12/13. Replaced by explicit component selection. |

## 2. `rig.run` lifecycle and driver phases

Core phases from `rig.Runtime`: `before_setup`, `after_setup`, `before_shutdown`,
`after_shutdown`.

| Item | Current form | Disposition | Where / rationale |
| --- | --- | --- | --- |
| `before_setup` | global then app hook | Rp | Phase 3/6. Startup ordering is owned by the dependency graph; user hook becomes an extension point. |
| `after_setup` | app hook, after resources | R | Phase 3/6. Preserved as an extension point with the same timing. |
| `before_shutdown` | app hook | R | Phase 4/6. Preserved; runs before resource release. |
| `after_shutdown` | app hook | R | Phase 4/6. Preserved; runs after release. |
| `before_poll` / `after_poll` | SDL driver phases | Rp | Phase 8. Moved to the input event source / progress engine extension points. |
| `before_drain` / `after_drain` | SDL driver phases | Rp | Phase 5/10. Moved to scheduler drain extension points. |
| `before_frame` / `after_frame` | SDL driver phases | R | Phase 10. Preserved as frame lifecycle extension points. |
| Driver event `key` | `runtime:handle_event("key", info)` | Rp | Phase 8. Normalized by the input source component. |
| Driver event `mouse` | `runtime:handle_event("mouse", info)` | Rp | Phase 8. Same. |
| Driver event `resize` | `runtime:handle_event("resize", info)` | Rp | Phase 8/10. Same; initial resize dispatch retained. |

## 3. Execution and scheduling behavior

| Item | Current form | Disposition | Where / rationale |
| --- | --- | --- | --- |
| UV main coroutine | `module_config.uv.main(options)` spawned as task | Rp | Phase 3/7. Becomes `:execute(function)`; scheduler presence selects coroutine semantics (D10). |
| UV task-draining termination | loop runs while `has_active_tasks` | Rp | Phase 5. Becomes foreground-task lifetime rules in the progress engine. |
| SDL frame/event polling loop | `sdl3`/`sdl3_gl`/`sdl3_gpu` driver `loop` | Rp | Phase 8–10. Split across input source, scheduler drain, and presentation. |
| SDL scheduler drain once per frame | `drain_scheduler()` in driver loop | R | Phase 5/10. Preserved as a progress-engine step. |
| `sched.sleep` (UV) | uv timer callback via `sched.sleep` handler | R | Phase 5/7. Preserved; re-homed to the timer/wakeup capability. |
| `sched.sleep` (SDL) | sleep until monotonic deadline | R | Phase 5. Preserved. |
| `sched` scheduler | `sched.Scheduler`, `spawn`, `await`, `yield`, `park`, `join`, async tickets | R | Phase 5. Reused; ownership moves into a runtime-scoped component. |
| `sched` global active scheduler | `sched.active_scheduler` module global | Rp | Phase 5. Becomes scheduler-instance state in `ctx`. |
| `uv.spawn` | `sched.await("uv.spawn", spec)` | R | Phase 7. Preserved semantics behind an async capability. |
| `uv.scandir` | `sched.await("uv.scandir", path)` | R | Phase 7. Preserved. |
| `uv.stop` / `uv.get_loop` | module globals `M._loop` | Rp | Phase 7. Loop becomes a resource; `stop` becomes a component/ctx method. |
| Scheduler deadlock detection | `uv` loop raises on idle-wait | R | Phase 5. Preserved in the progress engine. |
| `rig.ResourceScope` | adopt/replace/release scope | Rp | Phase 4. Becomes the runtime root ownership graph. |
| Per-component release | drivers/app release their own resources | Rp | Phase 4. Unified into one ownership graph with rollback. |

## 4. Time and event behavior

| Item | Current form | Disposition | Where / rationale |
| --- | --- | --- | --- |
| `time` service | `rig.register_service("time", {"now","monotonic"})` | X | Phase 5/11. Replaced by a clock capability. |
| `time.now` / `time.monotonic` | wrappers over the active provider | Rp | Phase 5/7. Move to `ctx` clock object. |
| SDL wall/monotonic clock | `sdl3x` time provider | R | Phase 5/8. Preserved as the SDL clock component. |
| UV wall/monotonic clock | `uv` time provider | R | Phase 7. Preserved as the UV clock component. |
| SDL key normalization | `pump_events` key handling | R | Phase 8. Preserved in the input source. |
| SDL mouse normalization | `pump_events` mouse handling | R | Phase 8. Preserved. |
| Resize detection + initial dispatch | `dispatch_resize_if_changed(runtime, "initial", 0)` | R | Phase 8/10. Preserved. |
| App event forwarding | `runtime:handle_event` calls `app.on_<event>` | Rp | Phase 6. Replaced by qualified extension points + class adapter. |
| Poll/drain/frame phases | see §2 | Rp | Phases 6/8/10. |

## 5. Window and graphics behavior

| Item | Current form | Disposition | Where / rationale |
| --- | --- | --- | --- |
| SDL init flags | `driver_config.<mode>.init_flags` (default `INIT_VIDEO+INIT_EVENTS`) | R | Phase 8. Becomes the SDL subsystem component option. |
| SDL subsystem ownership | `owned_init_flags` + `QuitSubSystem` | R | Phase 8. Preserved; owned by the subsystem component. |
| Window properties | `driver_config.<mode>.window_props` | R | Phase 8. Window component option; same `sdl3x.Properties` semantics. |
| Window creation / defaults | `sdl3x.Window(options)` | R | Phase 8. Preserved as the window resource. |
| `create_renderer` override | `driver_config.sdl3.create_renderer` | Rp | Phase 9. Becomes a graphics-context provider override. |
| Renderer creation/presentation | `renderer` + `present()` | Rp | Phase 9/10. Split into graphics context and presentation. |
| GL attributes | `driver_config.sdl3_gl.gl_attributes` | R | Phase 9. GL context component option. |
| GL context profile / version | same (`context_major_version`, `context_minor_version`, `context_profile`, ...) | R | Phase 9. Preserved. |
| GL swap interval | `driver_config.sdl3_gl.swap_interval` | R | Phase 9. Preserved. |
| GL context creation/ownership | `setup_gl`, `shutdown` | Rp | Phase 9. Owned by the GL context component with rollback. |
| GPU shader formats | `driver_config.sdl3_gpu.shader_formats` | R | Phase 9. GPU device component option. |
| GPU debug mode | `driver_config.sdl3_gpu.debug_mode` | R | Phase 9. Preserved. |
| GPU backend name | `driver_config.sdl3_gpu.backend_name` | R | Phase 9. Preserved. |
| GPU device setup/teardown | `setup_gpu`, `shutdown` (`WaitForGPUIdle`, destroy) | R | Phase 9. Owned by the GPU device component. |
| Fullscreen toggle | `sdl3x.App:set_fullscreen` / `toggle_fullscreen` | Rp | Phase 8/10. Becomes a window/presentation component method on `ctx`. |
| Vsync toggle | `sdl3x.App:set_vsync` / `toggle_vsync` | Rp | Phase 9/10. Becomes a presentation descriptor capability. |
| Render callback selection | `driver_config.<mode>.render` or app `render`/`invoke_render` | Rp | Phase 3/10. Becomes class execution/frame-lifecycle wiring. |
| Frame profiler | `module_config.sdl3x.frame_profiler` + App begin/end hooks | Rp | Phase 10. Attached to frame lifecycle extension points. |
| Profiler enable/fullscreen/vsync module config | `module_config.sdl3x.{frame_profiler,fullscreen,vsync}` | Rp | Phase 8–10. Split into component options. |
| App-owned resources | `sdl3x.App:own/replace_owned/create_owned_scope` | Rp | Phase 4. Becomes runtime/component ownership. |
| App font faces | `sdl3x.App:load_font_face/get_font_face` | Rp | Phase 11. Becomes font rendering capability usage + ownership. |
| `sdl3x.ResourceScope` | GPU-resource scope subclass | Rp | Phase 4/9. Becomes component-scoped ownership on the GPU context. |
| `sdl3x.Properties` | owning property wrapper | R | Phase 8/9. Preserved as a resource helper. |
| `sdl3x.Window` | owning window wrapper | R | Phase 8. Preserved. |
| `sdl3x.GPUShader` | owning shader wrapper | R | Phase 9/11. Preserved. |
| `sdl3x.get_gl_proc_address` | GL proc lookup | R | Phase 9/11. Becomes a GL context/GL-resolver capability method. |
| GPU builder helpers | `build_vertex_*`, `build_color_target_*`, `create_gpu_shader`, depth helpers, buffer upload | R | Phase 9/11. Pure helpers retained. |

## 6. Ordinary module / resource knobs

| Item | Current form | Disposition | Where / rationale |
| --- | --- | --- | --- |
| Animator timing config | `module_config.animator.{fixed_dt,max_dt,max_steps_per_frame,start}` | Rp | Phase 12. Becomes animator component options. |
| `animator.Animator` | scene animator class | R | Retained as a plain class; ownership moves to the app/component. |
| `animator.App` | app base wiring root/animator lifecycle | Rp | Phase 3/12. Lifecycle moves to extension points; becomes an execution class or component bundle. |
| Shader compile options | `shader.compile{...}` (`source`, `path`, `language`, `stage`, `entrypoint`, `source_name`, `extra_args`, `preserve_*`, `glsl_version`, `optimization`, `debug_info`, `macro_definitions`) | R | Retained as a pure compile API. |
| Shader service dispatch | `shader.create_stage` / `destroy_stage` via `shader.stage` service | Rp | Phase 11. Becomes a shader-stage capability; providers become components. |
| SPIR-V reflection | `spirvcross.reflect_*` | R | Pure; retained. |
| Shader compiler libs | `shaderc.compile_spirv`, `dxc.compile_spirv`, `shadercross.*` | R | Pure; retained. |
| Profiler options | `profiler.FrameProfiler{fps, history_seconds}` | R | Pure; retained (Phase 10 re-homes attachment only). |
| Profiler metric bundle | internal `stat.MetricBundle` setup | R | Pure; retained. |
| `stat.MetricBundle` | stored/derived/window metrics | R | Pure; retained. |
| Font service | `font.renderer` service + providers | Rp | Phase 11. Becomes a font-rendering capability. |
| Font resource API | `font.load_face`, `face:create_sized_face`, `create_atlas`, `shape`, `create_text_renderer` | R | Retained; consumption via `ctx` capability. |
| Mesh service | `mesh.vertex_input` service + provider | Rp | Phase 11. Becomes a mesh-vertex-input capability. |
| Mesh resource API | `mesh.make_cube`, `mesh.build_vertex_input` | R | Retained; `build_vertex_input` resolves via `ctx`. |
| GL resolver service | `gl.resolver` service + provider | Rp | Phase 11. Becomes a GL-resolver capability. |
| GL module API | `gl.*` entry points resolved via resolver | R | Retained; resolution source changes to `ctx`. |
| Scenegraph resource API | `scenegraph.Object` tree, `activate_tree`, `release_tree`, `draw_tree` | R | Pure; retained. |
| SDL3 module | raw `sdl3.*` bindings + constants | R | Retained; constants unavailable on the installed 3.2.10 headers were already removed. |
| Freetype/HarfBuzz/color/mathx/repr/schema/prelude | pure helper modules | R | Retained unchanged. |

## 7. Tests, examples, and scripts

| Item | Current form | Disposition | Where / rationale |
| --- | --- | --- | --- |
| Test runner | `test.lua` `rig.run{ mode="uv", module_config.uv.main }` + `uv.scandir`/`uv.spawn` | Rp | Phase 7/13. Rebuilt from the async component + scheduler. |
| `test.lua` `run_registered_cases` | executed under `mode="uv"` | R | Retained behaviorally; re-homed. |
| `scripts/run_all_tests.lua` | uv-mode parallel test driver | Rp | Phase 7/13. Migrated to new async bundle. |
| Per-service test drivers | `tests/{rig,gl,glx,shader,font,mesh}_test.lua` register fake drivers/providers | X | Phase 13. Replaced by headless/fake components and `:execute(function)`. |
| `tests/rig_test.lua` runtime tests | `rig.run` option validation, hooks, app, events, services | Rp | Phases 1–6/13. Rewritten against builder/compiler/runtime semantics. |
| `tests/animator_test.lua` | `animator.App` lifecycle via app methods | Rp | Phases 3/6/12. Rewritten against execution classes/extension points. |
| `tests/sdl3x_test.lua` | `sdl3x.App` methods + runtime option validation | Rp | Phases 8–10/13. Component + `ctx` APIs. |
| Examples (all) | `rig.run{ mode=..., driver_config=..., app=... }` | Rp | Phase 13. Rewritten to builder/compiler/start, all three execution forms. |
| `examples/keylogger.fnl` | Fennel `(rig.run {:mode "sdl3" :app App})` | Rp | Phase 13. Rewritten; Fennel loader retained. |

## 8. Deferred (tracked, not implemented initially)

| Item | Disposition | Note |
| --- | --- | --- |
| Mixed execution models | D | Rejected at compile time initially; may be added later. |
| Preemptive/multithreaded scheduling | D | Cooperative single-threaded only (D8). |
| Runtime startup arguments | D | Compiled runtimes take no options (D7). |
| Source-generating Fennel macros / runtime `eval` | D | Lua-first implementation only. |
| Static Lua function signature/type checking | D | Contract declarations only; no inference. |
| Advanced event fan-out and handler ordering policy | D | Declared contracts validated; policy beyond declaration deferred. |
| Descriptor / compiled-plan serialization | D | Out of scope. |

---

## Coverage check against `PLAN.md`

- Runtime-level knobs (§1) ✔
- Execution and scheduling behavior (§3) ✔
- Time and event behavior (§4) ✔
- Window and graphics behavior (§5) ✔
- Ordinary module/resource knobs (§6) ✔
- `tests/`, `examples/`, `scripts/` searched and inventoried (§7) ✔
- Deferred work explicitly listed (§8) ✔

## Follow-up verification of inventory claims

Several rows will change behavior and must be re-checked during implementation. Keep
these as review checkpoints rather than assumptions:

- Confirm nothing outside `uv`/`test`/`scripts` depends on `uv.get_loop()`/`uv.stop()`
  before Phase 7 changes them.
- Confirm no example relies on the exact `driver_config` key names after Phase 8–10.
- Confirm `sdl3x` module-global accessors are not referenced after Phase 11.
- Confirm no test relies on `rig.run` option-validation error strings after Phase 13.
