# `shader`

High-level shader helper layered on top of `dxc`, `shaderc`, and `spirvcross`.

## API

- `shader.compile{ language="hlsl"|"glsl", stage=..., source=..., entrypoint?=..., source_name?=..., extra_args?=..., preserve_bindings?=..., preserve_interface?=..., glsl_version?=..., optimization?=..., debug_info?=..., macro_definitions?=... }`
  - Compiles the in-memory `source` to SPIR-V through `dxc` for HLSL or `shaderc` for GLSL.
  - File-backed source is read through the async `asset` path first (`asset.text(path)`),
    then passed here as `source`; `shader` performs no file I/O itself.
  - Reflects the result through `spirvcross`.
  - Returns a normalized shader artifact table with:
    - `artifact_kind = "spirv"`
    - `stage`
    - `entrypoint`
    - `bytecode`
    - `reflection`
    - `format = "spirv"`
  - Raises on compilation or reflection failure.
- `shader.create_stage(spec_or_artifact, provider)`
  - Dispatches through a `shader.stage` provider and creates a runtime-specific shader stage object.
  - Accepts either:
    - a source specification with `language`, `stage`, and in-memory `source`
    - or a normalized artifact such as the result of `shader.compile(...)`
- `shader.destroy_stage(stage, provider)`
  - Dispatches through a `shader.stage` provider and destroys a runtime-specific shader stage object.

## Notes

- `shader` declares the `shader.stage` capability.
- Runtime-specific stage creation stays in providers, not in the `gl` or `sdl3` module namespaces.
- `sdl3x.bundle_sdl3_gl` provides a GLSL source provider returning `glx.Shader` objects.
- `sdl3x.bundle_sdl3_gpu` provides a SPIR-V provider returning `sdl3x.GPUShader` objects.
- SDL GPU descriptor-set validation happens when the SDL GPU provider creates shader objects, not during generic SPIR-V compilation.

## Runtime Components

`shader.plugin([spec])` declares the `shader.stage` capability for the compositional runtime.

`shader.component(plugin, options)` requires `shader.stage` and exposes a bound facade as
`ctx.<name>`. `shader.bind(provider)` builds it, with `:create_stage(spec)` and
`:destroy_stage(stage)` delegating to the validated module entry points:

```lua
local sp = shader.plugin()
local compiled = rig.runtime()
   :use(sp)
   :add(provider)
   :add(shader.component(sp, { name = "shader" }))
   :execute(function(ctx)
      local stage = ctx.shader:create_stage(spec)
   end)
   :compile()
```
