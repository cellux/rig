# Rig

Rig is a customized version of LuaJIT providing a lot of bells and whistles through an assorted set of modules built into the interpreter.

## How to build

Build dependencies:

- `make`
- `cmake`
- `pkg-config`
- LuaJIT development files with a `luajit` pkg-config entry
- the `luajit` executable
- SDL3 development files with an `sdl3` pkg-config entry
- FreeType development files with a `freetype2` pkg-config entry
- libuv development files with a `libuv` pkg-config entry

Current build and runtime split:

- At build time Rig links against:
  - LuaJIT
  - the platform dynamic loader (`dl`)
- At build time Rig also uses compile-time headers and flags from:
  - SDL3
  - FreeType
  - libuv
- The `rig` binary is currently not linked against the SDL3, libuv, or FreeType shared libraries.
- Those libraries are loaded dynamically at runtime by the corresponding modules:
  - `sdl3`
  - `uv`
  - `freetype`

Build with:

```
make
```

This configures CMake in `build/` and builds the `rig` target there.

Run the test suite with:

```
make test
```

This rebuilds `rig` if needed and then runs `ctest`, which invokes the repo-local test runner in [`scripts/run_all_tests.lua`](scripts/run_all_tests.lua).

Notes:

- The built executable is `build/rig`.
- `make test` currently assumes the runtime-loadable libraries needed by the exercised modules are installed on the host.

## How to use

Run with:

```
rig <scriptfile>
```

The script file may be written in Lua or Fennel.

## Modules

Module system overview: [`src/modules/README.md`](src/modules/README.md)

Available modules:

- `rig`: [`src/modules/rig.md`](src/modules/rig.md)
- `dl`: [`src/modules/dl.md`](src/modules/dl.md)
- `freetype`: [`src/modules/freetype.md`](src/modules/freetype.md)
- `harfbuzz`: [`src/modules/harfbuzz.md`](src/modules/harfbuzz.md)
- `sched`: [`src/modules/sched.md`](src/modules/sched.md)
- `uv`: [`src/modules/uv.md`](src/modules/uv.md)
- `test`: [`src/modules/test.md`](src/modules/test.md)
- `sdl3`: [`src/modules/sdl3.md`](src/modules/sdl3.md)
- `gl`: [`src/modules/gl.md`](src/modules/gl.md)
- `shadercross`: [`src/modules/shadercross.md`](src/modules/shadercross.md)
- `shaderc`: [`src/modules/shaderc.md`](src/modules/shaderc.md)
- `dxc`: [`src/modules/dxc.md`](src/modules/dxc.md)
- `spirvcross`: [`src/modules/spirvcross.md`](src/modules/spirvcross.md)
- `shader`: [`src/modules/shader.md`](src/modules/shader.md)
- `time`: [`src/modules/time.md`](src/modules/time.md)
- `math3d`: [`src/modules/math3d.md`](src/modules/math3d.md)
- `mesh3d`: [`src/modules/mesh3d.md`](src/modules/mesh3d.md)
