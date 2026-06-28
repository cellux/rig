# `shader`

High-level shader helper layered on top of `dxc`, `shaderc`, and `spirvcross`.

## API

- `shader.compile{ language="hlsl"|"glsl", stage=..., source?=..., path?=..., entrypoint?=..., source_name?=..., extra_args?=..., preserve_bindings?=..., preserve_interface?=..., glsl_version?=..., optimization?=..., debug_info?=..., macro_definitions?=... }`
  - Loads source from `source` or `path`.
  - Compiles to SPIR-V through `dxc` for HLSL or `shaderc` for GLSL.
  - Reflects the result through `spirvcross`.
  - Returns a normalized shader artifact table with:
    - `artifact_kind = "spirv"`
    - `stage`
    - `entrypoint`
    - `bytecode`
    - `reflection`
    - `format = "spirv"`
  - Raises on compilation or reflection failure.
- `shader.create_stage(spec_or_artifact)`
  - Resolves the active `shader.stage` service and creates a runtime-specific shader stage object.
  - Accepts either:
    - a source specification with `language`, `stage`, and `source` or `path`
    - or a normalized artifact such as the result of `shader.compile(...)`
- `shader.destroy_stage(stage)`
  - Resolves the active `shader.stage` service and destroys a runtime-specific shader stage object.

## Notes

- `shader` owns the `shader.stage` service namespace.
- Runtime-specific stage creation stays in service providers, not in the `gl` or `sdl3` module namespaces.
- Under the `sdl3_gl` runtime mode, `shader.create_stage(...)` returns `glx.Shader` objects that can be linked through `glx.Program { shaders = { ... } }`.
- Under the `sdl3_gpu` runtime mode, `shader.create_stage(...)` returns `sdl3x.GPUShader` objects.
- SDL GPU descriptor-set validation happens when the SDL GPU runtime creates shader objects, not during generic SPIR-V compilation.
