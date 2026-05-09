# `shadercross`

LuaJIT FFI wrapper around `SDL3_shadercross`.

The shared library is loaded lazily when the module is required.

## API

- `shadercross.init()` / `shadercross.quit()`
- `shadercross.compile_spirv_from_hlsl{ ... }`
- `shadercross.reflect_graphics_spirv(bytecode[, props])`
- `shadercross.reflect_compute_spirv(bytecode[, props])`
- `shadercross.compile_graphics_shader_from_spirv(options)`
- `shadercross.compile_compute_pipeline_from_spirv(options)`

## Notes

- This module is still useful as a direct SDL shadercross binding.
- On this project’s current host setup, the `HLSL -> SPIR-V` runtime path in upstream `SDL3_shadercross` has been unstable with the packaged DXC stack, so the `dxc` + `spirvcross` path is the more reliable one right now.
