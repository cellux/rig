# `app`

Generic application execution base, independent of any window or graphics backend.

The `app` module owns the lifecycle conveniences shared by executable applications:
the frame profiler, app-owned resources, font faces, render invocation, presentation
toggles, and resize bookkeeping. Backends provide the actual window and graphics
context; `app` drives them through their duck-typed interfaces. SDL-specific
applications come from `sdl3x.App`.

## `app.App`

`app.App` extends `rig.Class()` and is instantiated as a runtime execution class, so
`init(context)` receives the runtime context and `context.window` /
`context.graphics`.

Instances expose:

- `window_width`
- `window_height`
- `pixel_width`
- `pixel_height`
- `fullscreen_enabled`
- `vsync_enabled`
- `focused`
- `mouse_grab_requested`
- `mouse_grab_enabled`
- `frame_profiler`
- `frame_profiler_enabled`
- `font_faces`
- `owned_resources`

Methods:

- `app:set_vsync(enabled)` / `app:toggle_vsync()`
- `app:set_fullscreen(enabled)` / `app:toggle_fullscreen()`
- `app:can_mouse_grab()` — whether the active window supports relative mouse mode
- `app:set_mouse_grab(enabled)` / `app:toggle_mouse_grab()` — set or toggle
  relative mouse mode and mouse grab together; returns the applied state
- `app:apply_mouse_grab()` — re-applies the requested state, taking focus into
  account (grab is active only while `focused` is true)
- `app:set_frame_profiler_enabled(enabled)` / `app:toggle_frame_profiler()`
- `app:own(resource, release_fn)`
- `app:replace_owned(key, resource, release_fn)`
- `app:create_owned_scope(label?)`
- `app:release_owned_resources()`
- `app:load_font_face(name, path[, face_index])`
- `app:get_font_face(name)`
- `app:invoke_render(...)`
- `app:on_resize(resize_info)`

Lifecycle hooks (also usable by subclasses):

- `init(context)` — records the window/graphics context, builds the config-driven
  profiler, and creates the owned-resource scope (adopted into `context.resources`
  when present).
- `after_setup()` — applies the `vsync`/`fullscreen` configuration toggles.
- `before_shutdown()` — releases the owned-resource scope.
- `before_frame()` / `after_frame()` — bound the frame profiler.

`set_vsync` uses `graphics.set_vsync` or `graphics.set_swap_interval` when present.
`set_fullscreen` uses `window:set_fullscreen(enabled)` and `window:sync()`.
`set_mouse_grab` uses `window:set_relative_mouse_mode(enabled)` and, when
available, `window:set_mouse_grab(enabled)`. Releasing focus clears the actual
grab while preserving the requested state; gaining focus reapplies it. Shutdown
releases the grab before the window is destroyed.

Subclasses may override `app_name` (used in error messages), `config_namespace`
(config table key under `context.options`), and `scope_label`.

## Notes

- `app` contains no SDL- or GL-specific behavior; `runtime` stays core-platform only.
