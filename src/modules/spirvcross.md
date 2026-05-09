# `spirvcross`

SPIR-V reflection through `spirv-cross-c-shared`.

The shared library is loaded lazily when the module is required.

## API

- `spirvcross.reflect_spirv(bytecode_or_compile_result)`
  - Reflects general SPIR-V metadata.
- `spirvcross.reflect_graphics_spirv(bytecode_or_compile_result)`
  - Reflects graphics-stage metadata with SDL-oriented resource counts.
- `spirvcross.reflect_compute_spirv(bytecode_or_compile_result)`
  - Reflects compute-stage metadata and local workgroup size.
- `spirvcross.get_version()`
- `spirvcross.get_commit_revision_and_timestamp()`

Inputs may be raw SPIR-V byte strings or tables with a `bytecode` field.

## Returned Metadata

The reflection result includes:

- shader stage / execution model
- resource counts relevant to SDL GPU shader creation
- stage input/output metadata
- descriptor set and binding metadata for reflected resources
- compute local size for compute shaders
