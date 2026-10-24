# asset

Path-relative, cached asset loading. Paths resolve against the directory of the script
that calls the asset function, so a demo and its assets can live together and run from
anywhere. Loaded data is cached by canonical path (`rig.realpath`).

Reads are **asynchronous**: the loaders await `uv.fs_read`, so call them from a
scheduler-managed coroutine (for example a sketch `start`/`on_start` hook). In a
synchronous pre-loop context, wrap the call in `sched.block`; decoding and parsing stay
synchronous.

## API

- `asset.path(path)` — resolves `path` against the calling script and returns the
  resolved path string (synchronous; no I/O).
- `asset.read(path)` — awaits the file contents as a Lua string (cached).
- `asset.text(path)` / `asset.bytes(path)` — aliases for `asset.read`.
- `asset.image(path)` — loads and decodes a PNG or JPEG (chosen by extension, with a
  PNG-then-JPEG fallback) into `{ width, height, channels, pixels }`, cached.
- `asset.material(spec)` — loads `spec.vertex` and `spec.fragment` GLSL files relative
  to the script and returns a `render.material`. `spec.name`, `spec.language`, and
  `spec.texture` are forwarded.
- `asset.mesh(path, options?)` — loads a Wavefront OBJ relative to the script and
  parses it through `mesh.parse_obj` into a `position_color_uv_f32` mesh, cached by
  path. `options.color` tints the whole mesh.

## Decoders

Images are decoded by `png` (libpng simplified API) and `jpeg` (a minimal C helper plus
FFI). If JPEG support was not built, `asset.image` on a `.jpg`/`.jpeg` raises the
decoder's message.

## Example

```lua
local asset = require("asset")

rig.run {
   build = function(app)
      app:on_draw(function(_, frame) frame.surface:draw_mesh(mesh, mvp, material) end)
   end,
   start = function()
      material = asset.material {
         name = "tint",
         vertex = "assets/tint.vert",
         fragment = "assets/tint.frag",
      }
      local logo = asset.image("assets/logo.png")
      local logo_texture = render.texture { image = logo }
      local rock = asset.mesh("assets/rock.obj")
   end,
}
```

Synchronous pre-loop use:

```lua
local text = sched.block(function() return asset.read("assets/data.txt") end)
```
