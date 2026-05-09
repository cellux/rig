# `dxc`

Runtime HLSL to SPIR-V compilation through `libdxcompiler`.

The DXC shared library is loaded lazily when the module is required.

## API

- `dxc.compile_spirv{ source=..., stage=..., entrypoint?=..., source_name?=..., extra_args?=..., preserve_bindings?=..., preserve_interface?=... }`
  - Compiles HLSL source to SPIR-V in process.
  - Returns a table containing at least:
    - `bytecode`
    - `entrypoint`
    - `stage`
    - `target_profile`
    - `messages`

## Stage Constants

- `dxc.SHADERSTAGE_VERTEX`
- `dxc.SHADERSTAGE_FRAGMENT`
- `dxc.SHADERSTAGE_COMPUTE`

## Current Limits

- No `#include` support yet.
- DXC argument strings are currently ASCII-only.
