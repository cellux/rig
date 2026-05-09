# Rig

Rig is a customized version of LuaJIT providing a lot of bells and whistles through an assorted set of modules built into the interpreter.

## Usage

Build with:

```
make
```

This configures CMake in `build/` and builds the `rig` target there.

Run with:

```
rig <scriptfile>
```

The script file may be written in Lua or Fennel.
`rig.run_script_file(script_path)` reads the file contents and passes them through the loader functions listed in `rig.script_loaders`.
Each loader receives the script path and source text, and should return either a compiled Lua chunk or an error string.
`rig.load_script(script_path, source)` stops at the first loader that returns a chunk, executes it, and reports all loader errors if none accept the source.

## Modules

Rig modules are registered in the order they are listed in `src/modules/modules.txt`.

For a module name `M`:
- `src/modules/M.c` (optional): compiled into the binary and initialized by calling `rig_register_M(lua_State *L)`.
- `src/modules/M.lua` (optional): compiled to LuaJIT bytecode at build time, embedded into the binary, and executed at interpreter startup.
- `src/modules/M.fnl` (optional): compiled to Lua, then handled as a Lua module.

For each module, initialization is interleaved:
- Run `rig_register_M(...)` from `M.c` if present.
- Then execute embedded `M.lua` if present.
- Then execute embedded `M.fnl` if present.

Each Lua module chunk runs in the normal global environment (`_G`).
The chunk must return a table containing module exports; Rig assigns that returned table to global `_G[M]`.
Rig passes the current module table as the first chunk argument, so modules can preserve existing exports with `local M = ... or {}`.
Rig keeps the standard `package`/`require` loader and LuaJIT `ffi` available in the global environment for builtin modules and user scripts.
Rig also loads the standard `io` library.

At interpreter startup Rig registers every module from `modules.txt` into `package.preload`.
Then it explicitly loads the builtin `fennel` and `rig` modules.
Any other module, such as `sdl3`, is loaded only when the script calls `require(...)`.
The `shadercross` module follows the same pattern and loads `libSDL3_shadercross`
through LuaJIT FFI only when required.
The `dxc` module also loads `libdxcompiler` lazily through LuaJIT FFI when required.
The `spirvcross` module also loads `libspirv-cross-c-shared` lazily through LuaJIT FFI when required.
The `shader` module layers on top of `dxc`, `spirvcross`, and `sdl3`.
The `time` module exposes wall-clock and monotonic clocks.

The builtin `rig` module defines `rig.script_loaders` at module load time with Lua and Fennel script loaders, in that order.

Rig loads the SDL3 shared library lazily through LuaJIT FFI from `src/modules/sdl3.lua`.
If a script never calls `require("sdl3")`, SDL is never loaded.

`shadercross.lua` provides runtime shader compilation helpers on top of
`SDL3_shadercross`, including HLSL-to-SPIR-V compilation and SPIR-V reflection.
Its main entrypoints are:
- `shadercross.init()` / `shadercross.quit()`
- `shadercross.compile_spirv_from_hlsl{ ... }`
- `shadercross.reflect_graphics_spirv(bytecode[, props])`
- `shadercross.reflect_compute_spirv(bytecode[, props])`

`dxc.lua` provides a direct runtime HLSL-to-SPIR-V path via `libdxcompiler`.
Its first entrypoint is:
- `dxc.compile_spirv{ source=..., stage=..., entrypoint?=..., extra_args?=... }`

Current `dxc` limitations:
- no `#include` support yet
- command-line argument strings are currently ASCII-only

`spirvcross.lua` provides direct SPIR-V reflection via `spirv-cross-c-shared`.
Its first entrypoints are:
- `spirvcross.reflect_spirv(bytecode_or_compile_result)`
- `spirvcross.reflect_graphics_spirv(bytecode_or_compile_result)`
- `spirvcross.reflect_compute_spirv(bytecode_or_compile_result)`

The first version returns:
- shader stage / execution model
- SDL-relevant resource counts
- stage input/output metadata
- descriptor set / binding data for reflected resources
- compute local size metadata

`shader.lua` provides a small user-facing shader pipeline.
Its first entrypoints are:
- `shader.compile{ language="hlsl", stage=..., source=... }`
- `shader.create_sdl_shader(device, compiled[, props])`

`time.lua` provides:
- `time.now()` -> epoch seconds as a Lua number
- `time.monotonic()` -> monotonic seconds as a Lua number
- `time.now_ns()` -> epoch nanoseconds as a Lua number
- `time.monotonic_ns()` -> monotonic nanoseconds as a Lua number

The builtin `rig` module also ensures a global `hooks` table exists before the user script runs.
`sdl3.lua` installs default implementations for:
- `hooks.sdl_init_flags` (defaults to `sdl3.INIT_VIDEO + sdl3.INIT_EVENTS`)
- `hooks.create_window() -> window_ptr | nil, err`
- `hooks.create_renderer(window_ptr) -> renderer_ptr | nil, err`
User scripts can override either hook before entering the render loop.
By default, `hooks.create_window` uses `SDL_CreateWindowWithProperties` and
merges:
- `sdl3.default_window_props`
- `hooks.window_props` (if set by the user script)
Window property tables are converted to an `SDL_PropertiesID` via
`sdl3.build_properties(...)`.
The `window_ptr` / `renderer_ptr` values are LuaJIT FFI cdata pointers.

The SDL lifecycle is explicit:
- `sdl3.setup()` initializes SDL and creates the window/renderer.
- `sdl3.setup_gpu()` initializes SDL, creates the window, creates an SDL GPU device, and claims the window for it.
- `sdl3.pump_events()` dispatches queued SDL events and returns `false` after a quit event.
- `sdl3.render_frame()` runs `hooks.render()` and presents the frame.
- `sdl3.shutdown()` destroys the renderer/window and releases any SDL subsystems initialized by `sdl3.setup()`.
- `sdl3.run()` is the convenience entrypoint that wraps `setup`, a `pump_events`/`render_frame` loop, and `shutdown`.

Additional GPU helpers currently exposed from `sdl3.lua`:
- `sdl3.get_window()`
- `sdl3.get_gpu_device()`
- `sdl3.upload_to_gpu_buffer(device, buffer, data_string)`
- `sdl3.choose_depth_format(device)`
- `sdl3.create_depth_texture(device, width, height[, format])`

`hooks.handle_key(key_info)` is called from `sdl3.pump_events()` for keyboard events.
Rig exits after the script finishes running; scripts that need an SDL loop must call `sdl3.run()` or drive the loop explicitly.

## GPU Example

The first SDL GPU example is:
- `examples/spinning_cube.lua`

It demonstrates:
- runtime HLSL -> SPIR-V compilation via `dxc`
- SPIR-V reflection via `spirvcross`
- SDL GPU shader/pipeline creation
- vertex buffer upload
- pushed vertex uniform data for the transform matrix
- monotonic animation timing via `time.monotonic()`
- depth-tested rendering to the SDL swapchain
