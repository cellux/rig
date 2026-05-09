# `shader`

High-level shader helper layered on top of `dxc`, `shaderc`, `spirvcross`, and `sdl3`.

## API

- `shader.compile{ language="hlsl"|"glsl", stage=..., source?=..., path?=..., entrypoint?=..., source_name?=..., extra_args?=..., preserve_bindings?=..., preserve_interface?=..., glsl_version?=..., optimization?=..., debug_info?=..., macro_definitions?=... }`
  - Loads source from `source` or `path`.
  - Compiles to SPIR-V through `dxc` for HLSL or `shaderc` for GLSL.
  - Reflects the result through `spirvcross`.
  - Returns a normalized compiled shader table.
- `shader.create_sdl_shader(device, compiled, props?)`
  - Builds an `SDL_GPUShader` from a compiled shader result.

## Notes

- Graphics SPIR-V layouts are validated against SDL GPU descriptor-set expectations before shader creation.
