# Rig

Rig is a customized version of LuaJIT providing a lot of bells and whistles through an assorted set of modules built into the interpreter.

## Usage

```
rig <scriptfile>
```

The file passed to `rig` typically has a `.lua` extension.

## Modules

Rig modules are loaded in the order they are listed in `src/modules/modules.txt`.

For a module name `M`:
- `src/modules/M.c` (optional): compiled into the binary and initialized by calling `rig_register_M(lua_State *L)`.
- `src/modules/M.lua` (optional): compiled to LuaJIT bytecode at build time, embedded into the binary, and executed at interpreter startup.

For each module, initialization is interleaved:
- Run `rig_register_M(...)` from `M.c` if present.
- Then execute embedded `M.lua` if present.

Each Lua module chunk runs with the module table as its chunk environment,
with `_G` fallback for unresolved names. This means plain assignments and
function declarations in `M.lua` write into global module table `_G[M]`.

Rig uses SDL3 callback entry points (`SDL_AppInit`, `SDL_AppEvent`, `SDL_AppIterate`, `SDL_AppQuit`) from `src/main.c`.
The script is loaded in `SDL_AppInit`.

If global `on_render()` is defined, Rig continues running and:
- `on_key(key_info)` is called from SDL event dispatch.
- `on_render()` is called each iterate tick.

If `on_render()` is not defined, Rig exits after the script loads.
