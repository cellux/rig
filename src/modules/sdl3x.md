# `sdl3x`

Higher-level SDL app helpers layered on top of the `sdl3` runtime drivers.

Unlike `sdl3`, this module is not a raw binding surface. It provides app classes and convenience lifecycle behavior for SDL-backed Rig apps.

## Exports

- `sdl3x.get_error([fallback])`
- `sdl3x.free(ptr)`
- `sdl3x.Properties`
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

## Helpers

- `sdl3x.get_error([fallback])`
  - Returns the current SDL error string.
  - Returns `fallback` when SDL has no current error string.
  - Defaults to `"unknown SDL error"` when no fallback is provided.
- `sdl3x.free(ptr)`
  - Frees SDL-owned memory returned by SDL APIs that require `SDL_free(...)`.
  - Ignores `nil` and `ffi.NULL`.

## `sdl3x.Properties`

`sdl3x.Properties` is a higher-level owning wrapper around `SDL_PropertiesID`.

Instances expose the live SDL handle directly as:

- `props.id`

Methods:

- `props:set(name, value)`
- `props:clear(name)`
- `props:merge(values_or_props)`
- `props:get(name[, default])`
- `props:has(name)`
- `props:to_table()`
- `props:clone()`
- `props:release()`

Supported value types mirror the current SDL property setter surface in `sdl3.lua`:

- `boolean`
- integer or floating-point `number`
- `string`
- pointer-like `cdata`

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
