# `screenshot`

Optional PNG frame capture. The facility is disabled unless
`RIG_ENABLE_SCREENSHOTS` is set to a truthy value (`1`, `true`, `yes`, `on`, ...).
The normal render path is unchanged; sketches only run the per-frame flush when the
flag is enabled, so ordinary runs pay no capture cost.

Capture is a capability, not a hard-coded backend check. The `screenshot` module
declares `screenshot.capture`; each backend provides its own implementation through a
provider component. The OpenGL, SDL renderer, and SDL GPU providers live in `sdl3x`.

## Enabling

```sh
RIG_ENABLE_SCREENSHOTS=1 ./build/rig examples/Cordoba/spike.lua
```

The flag is read once when the `screenshot` module loads.

## Capability and providers

- `screenshot.plugin([spec])` — declares the `screenshot.capture` capability.
- `screenshot.component(plugin, options)` — consumes `screenshot.capture`, installs
  the provider for the module-level helpers, and clears it on release.
- A provider is a table with `capture(surface, options) -> image`, where `image` is
  top-down RGBA8 `{ width, height, channels = 4, pixels }`.
- `sdl3x.gl_screenshot_component`, `sdl3x.renderer_screenshot_component`, and
  `sdl3x.gpu_screenshot_component` provide the backend implementations. The SDL
  bundles add the matching component automatically.
- `screenshot.bind(provider)` — validates a provider.
- `screenshot.set_provider(provider)` / `screenshot.clear_provider()` /
  `screenshot.provider()` — direct provider control for hand-built runtimes and tests.

## API

- `screenshot.enabled()` — true when `RIG_ENABLE_SCREENSHOTS` is enabled.
- `screenshot.request(path?, options?)` — queues a capture for the end of the
  current frame. `path` defaults to `screenshot-NNNN.png` in the working directory.
  When the first argument is a table it is treated as the options table. Returns the
  request table.
- `screenshot.flush(app?, frame?)` — captures and writes every queued request using
  `app.surface`/`frame.surface`. Called automatically by the `sketch` overlay phase.
  Safe with an empty queue and a no-op when disabled.
- `screenshot.capture(surface, options?)` — captures immediately through the active
  provider and returns a top-down RGBA image. Must run before the backend presents
  the frame.
- `screenshot.write(path, image)` — PNG-encodes and writes an image. Returns `path`.
- `screenshot.save(surface, path?, options?)` — immediate capture plus write. Returns
  `path, image`.
- `screenshot.clear()` — drops queued requests and resets the auto-name counter.
  Intended for tests and tools.

## Options

- `path` — output filename.
- `width`, `height` — capture size; defaults to the scene's current pixel size.
- `x`, `y` — capture origin in the backend framebuffer.
- `flip_y` — OpenGL reads bottom-up; the GL provider flips rows by default so saved
  images are top-down. Set `false` to keep raw framebuffer order. The renderer and
  GPU providers already return top-down pixels.

## Backend behaviour

- **OpenGL:** `gl.ReadPixels` on the current framebuffer, with row flipping. The
  scene size comes from the current GL viewport.
- **SDL renderer:** `SDL_RenderReadPixels` returns an `SDL_Surface`; the provider
  converts it to `SDL_PIXELFORMAT_RGBA32`, copies the rows (honouring pitch), and
  destroys both surfaces.
- **SDL GPU:** ends the scene pass, copies the swapchain texture into a download
  transfer buffer, submits the frame command buffer, waits for the GPU, maps the
  buffer, and swizzles BGRA swapchains to RGBA. One readback is shared by multiple
  requests in the same frame; a second, differently cropped GPU request in the same
  frame is rejected because the swapchain has already been presented. The GPU frame
  loop skips its own submit when capture already submitted the command buffer.

## Sketch integration

```lua
rig.run {
   build = function(app)
      app:on_update(function(_, frame)
         if frame.input:key_pressed("F12") then
            app:screenshot("frame.png")
         end
      end)
   end,
}
```

`app:screenshot(path?, options?)` queues the capture. The sketch flushes it after
overlays and before presentation, so the saved image includes the finished scene and
HUD. Calling from `on_draw` or `on_overlay` captures the same frame; calling earlier
also captures the current frame because the request is deferred.

## Notes

- `png.encode` performs the encoding; the PNG writer uses libpng's simplified API.
- Captures allocate a `width * height * 4` byte buffer and are intentionally not
  retained after writing.
- A missing provider raises a clear error instead of silently producing an empty
  image.
