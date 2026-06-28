# `glx`

High-level OpenGL helpers layered on top of the raw `gl` module.

## API

- `glx.Shader { stage = "vertex"|"fragment"|"compute", source = ..., source_name? = ... }`
  - Compiles a shader and raises on failure.
  - Fields:
    - `id`
    - `stage`
    - `source`
    - `source_name`
  - Methods:
    - `shader:release()`
- `glx.Program { shaders = { ... } }`
- `glx.Program { vertex_source = ..., fragment_source = ..., vertex_source_name? = ..., fragment_source_name? = ... }`
- `glx.Program { compute_source = ..., compute_source_name? = ... }`
  - Links a program and raises on failure.
  - Owns its shader objects.
  - Fields:
    - `id`
    - `shaders`
    - `uniform_locations`
  - Methods:
    - `program:uniform_location(name)`
    - `program:use()`
    - `program:release()`
- `glx.Buffer { target = ... }`
  - Creates a buffer object for the given binding target.
  - Fields:
    - `id`
    - `target`
  - Methods:
    - `buffer:bind()`
    - `buffer:set_data(data, usage, size?)`
    - `buffer:release()`
- `glx.VertexArray()`
  - Creates a vertex-array object.
  - Fields:
    - `id`
  - Methods:
    - `vao:bind()`
    - `vao:attribute(index, size, type, normalized?, stride?, pointer?)`
    - `vao:release()`
- `glx.get_version_string()`

## Notes

- `glx` is intentionally small. Raw OpenGL entry points and constants stay in `gl`.
- `buffer:set_data(...)` accepts Lua strings, FFI cdata values, or `nil` with an explicit size for allocation-only uploads.
- `shader.create_stage{ language = "glsl", ... }` under `sdl3_gl` returns `glx.Shader` objects.
