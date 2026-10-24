# `graphics`

Backend-neutral graphics-context and frame/presentation contract.

The `graphics` module owns the `graphics.context` capability abstractly. Concrete
graphics backends (for example `sdl3x`) provide implementations; `graphics` contains
no SDL- or GL-specific behavior.

## API

- `graphics.plugin([spec])`
  - Declares the `graphics.context` capability.
- `graphics.provider_component(plugin, options, config)`
  - Builds a component that provides `config.capability` from a provider service.
  - It requires a `graphics.context` with `properties = { backend = config.backend }`.
  - `config.make(context)` creates the provider (defaulting to `config.provider`).
  - `config.bind(provider)` wraps the provider before it is exposed (defaults to the
    provider itself).
  - `config.requires` is an optional list of extra requirements appended after the
    `graphics.context` one (for example `{ { capability = "gl.resolver" } }`), used to
    order the provider against other components it depends on.
  - `config.release()` is called when the component is released, when present.
  - `options.name` names the component.
- `graphics.frame_component(plugin, options)`
  - Provides the backend-neutral per-frame loop.
  - It requires `graphics.context` and contributes a `frame` progress operation that:
    1. emits `core.before_frame`;
    2. calls the render callback;
    3. presents through the graphics context (`graphics:render_frame(render)`);
    4. emits `core.after_frame`.
  - `options.render` is an optional render callback. When omitted, class execution
    uses `instance:render(...)`; if that is also absent, the runtime uses the
    component providing `render.scene` (see the `scene` module) as the render
    callback.
  - `options.frame_profiler` may be `true` or a `profiler.FrameProfiler` options
    table; the frame profiler wraps the whole frame and the render call.

`core.before_frame` maps to the class method `before_frame`, and `core.after_frame`
to `after_frame`.

## Graphics Context Contract

A `graphics.context` provider exposes at least:

- `backend`
  - One of `"renderer"`, `"gl"`, `"gpu"` for the SDL-backed providers.
- `window`
- `render_frame(render_fn)`
  - Presents a frame. `renderer` and `gl` call `render_fn()` then present/swap; `gpu`
    acquires a command buffer and swapchain texture, calls
    `render_fn(command_buffer, swapchain_texture, width, height)`, then submits.
- `release()`

Backends are selected through capability properties, so consumers require a specific
backend (`{ capability = "graphics.context", properties = { backend = "gl" } }`)
without naming a component. `sdl3x` provides the SDL variants.
