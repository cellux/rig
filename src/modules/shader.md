# `shader`

High-level shader helper layered on top of `dxc`, `spirvcross`, and `sdl3`.

## API

- `shader.compile{ language="hlsl", stage=..., source?=..., path?=..., entrypoint?=..., source_name?=..., extra_args?=..., preserve_bindings?=..., preserve_interface?=... }`
  - Loads source from `source` or `path`.
  - Compiles to SPIR-V through `dxc`.
  - Reflects the result through `spirvcross`.
  - Returns a normalized compiled shader table.
- `shader.create_sdl_shader(device, compiled, props?)`
  - Builds an `SDL_GPUShader` from a compiled shader result.

## Notes

- The current implementation supports only `language = "hlsl"`.
- Graphics SPIR-V layouts are validated against SDL GPU descriptor-set expectations before shader creation.
