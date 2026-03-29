# Rig

Rig is a customized version of LuaJIT providing a lot of bells and whistles through an assorted set of modules built into the interpreter.

## Usage

```
rig <scriptfile>
```

The script file may be written in Lua or Fennel. Its extension must be `.lua` or `.fnl` respectively.

## Modules

Rig modules are loaded in the order they are listed in `src/modules/modules.txt`.

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
Builtin module initialization has access to LuaJIT `ffi`; Rig removes global `ffi` before loading the user script.

Rig uses SDL3 callback entry points (`SDL_AppInit`, `SDL_AppEvent`, `SDL_AppIterate`, `SDL_AppQuit`) from `src/main.c`.
The script is loaded in `SDL_AppInit`.

If global `on_render()` is defined, Rig continues running and:
- `on_key(key_info)` is called from SDL event dispatch.
- `on_render()` is called on each iterate tick.

If `on_render()` is not defined, Rig exits after the script loads.
