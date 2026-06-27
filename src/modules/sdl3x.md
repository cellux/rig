# `sdl3x`

Higher-level SDL app helpers layered on top of the `sdl3` runtime drivers.

Unlike `sdl3`, this module is not a raw binding surface. It provides app classes and convenience lifecycle behavior for SDL-backed Rig apps.

## Exports

- `sdl3x.App`
- `sdl3x.SceneApp`

## Module Configuration

Use `rig.run { module_config = { sdl3x = { ... } } }` for optional SDL app defaults:

- `frame_profiler`
  - `true` to create a default `profiler.FrameProfiler`.
  - A table to pass through to `profiler.FrameProfiler(...)`.
- `vsync`
  - Optional boolean initial state applied during `after_setup()`.
  - Currently supported by `mode = "sdl3"` and `mode = "sdl3_gl"`.
- `fullscreen`
  - Optional boolean initial fullscreen state applied during `after_setup()`.

## `sdl3x.App`

`sdl3x.App` extends `rig.App` with SDL window/event/render conveniences:

- `window_width`
- `window_height`
- `pixel_width`
- `pixel_height`
- `fullscreen_enabled`
- `vsync_enabled`
- `frame_profiler`
- `frame_profiler_enabled`
- `font_faces`
- `owned_resources`

Methods:

- `app:set_vsync(enabled)`
- `app:toggle_vsync()`
- `app:set_fullscreen(enabled)`
- `app:toggle_fullscreen()`
- `app:set_frame_profiler_enabled(enabled)`
- `app:toggle_frame_profiler()`
- `app:own(resource, release_fn)`
- `app:replace_owned(key, resource, release_fn)`
- `app:create_owned_scope(label?)`
- `app:release_owned_resources()`
- `app:load_font_face(name, path[, face_index])`
- `app:get_font_face(name)`
- `app:invoke_render(...)`

Optional overridable methods:

- `app:render(...)`
- `app:on_key(key_info)`
- `app:on_mouse(mouse_info)`
- `app:on_resize(resize_info)`

The default `on_resize(...)` implementation stores the latest logical and pixel window sizes on the app instance.

When frame profiling is enabled:

- `before_frame()` calls `frame_profiler:begin_frame()`
- `after_frame()` calls `frame_profiler:end_frame()`
- `invoke_render(...)` brackets `render(...)` with `begin_cpu()` / `end_cpu()`

## `sdl3x.SceneApp`

`sdl3x.SceneApp` extends `animator.App` with the same SDL/window/render conveniences as `sdl3x.App`.

It is intended for apps that combine:

- SDL window and event handling
- a render loop
- a scenegraph root
- an `animator.Animator`
- app-owned resources such as font faces or render assets

Typical usage:

```lua
local sdl3x = require("sdl3x")

local App = rig.Class(sdl3x.SceneApp)

function App:init(options)
   self:super().init(self, options)
end

function App:create_root()
   return Scene()
end

function App:render()
   if self.root ~= nil then
      self.root:draw_tree({
         renderer = sdl3.get_renderer(),
      })
   end
end
```
