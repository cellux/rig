# Rig

Rig is a customized version of LuaJIT providing a lot of bells and whistles through an assorted set of modules built into the interpreter.

## Usage

```
rig <scriptfile>
```

The file passed to `rig` typically has a `.lua` extension.

## Modules

Rig discovers modules from `src/modules`.

For a module name `M`:
- `src/modules/M.c` (optional): compiled into the binary and initialized by calling `rig_register_M(lua_State *L)`.
- `src/modules/M.lua` (optional): compiled to LuaJIT bytecode at build time, embedded into the binary, and executed at interpreter startup.

Initialization order is deterministic and defined by `src/modules/modules.txt`.
For each module, initialization is interleaved:
- Run `rig_register_M(...)` from `M.c` if present.
- Then execute embedded `M.lua` if present.

Each Lua module chunk runs with the module table as its chunk environment,
with `_G` fallback for unresolved names. This means plain assignments and
function declarations in `M.lua` write into global module table `_G[M]`.

The SDL backend module is also exposed globally as `sdl3` (for example `sdl3.loop()` and `sdl3.clear(...)`).

If your script defines global `on_key(key_info)` and/or `on_render()`, they are automatically used by the SDL event/render loop.
