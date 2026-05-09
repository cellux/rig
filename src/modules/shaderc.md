# `shaderc`

Runtime GLSL to SPIR-V compilation through `libshaderc_shared`.

The shared library is loaded lazily when the module is required.

## API

- `shaderc.compile_spirv{ source=..., stage=..., entrypoint?=..., source_name?=..., glsl_version?=..., optimization?=..., debug_info?=..., preserve_bindings?=..., macro_definitions?=... }`
  - Compiles GLSL source to SPIR-V in process.
  - Returns a table containing at least:
    - `bytecode`
    - `entrypoint`
    - `stage`
    - `source_name`
    - `warnings`
    - `errors`
    - `messages`

## Stage Constants

- `shaderc.SHADERSTAGE_VERTEX`
- `shaderc.SHADERSTAGE_FRAGMENT`
- `shaderc.SHADERSTAGE_COMPUTE`

## Notes

- The current implementation targets Vulkan/SPIR-V.
- Binding and location auto-assignment are disabled. Shaders should use explicit `layout(...)` declarations.
