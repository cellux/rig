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

At build time Rig links against LuaJIT and uses SDL3 only for compile-time headers and flags. The `rig` binary is not linked against the SDL3 shared library.

Build with:

```
make
```

This configures CMake in `build/` and builds the `rig` target there.

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
- `sdl3`: [`src/modules/sdl3.md`](src/modules/sdl3.md)
- `shadercross`: [`src/modules/shadercross.md`](src/modules/shadercross.md)
- `shaderc`: [`src/modules/shaderc.md`](src/modules/shaderc.md)
- `dxc`: [`src/modules/dxc.md`](src/modules/dxc.md)
- `spirvcross`: [`src/modules/spirvcross.md`](src/modules/spirvcross.md)
- `shader`: [`src/modules/shader.md`](src/modules/shader.md)
- `time`: [`src/modules/time.md`](src/modules/time.md)
- `math3d`: [`src/modules/math3d.md`](src/modules/math3d.md)
- `mesh3d`: [`src/modules/mesh3d.md`](src/modules/mesh3d.md)
