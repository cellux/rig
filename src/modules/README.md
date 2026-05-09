# Modules

Rig modules are registered in the order they are listed in [`modules.txt`](modules.txt).

For a module name `M`:
- `M.c` (optional): compiled into the binary and initialized by calling `rig_register_M(lua_State *L)`.
- `M.lua` (optional): compiled to LuaJIT bytecode at build time, embedded into the binary, and executed at interpreter startup.
- `M.fnl` (optional): compiled to Lua, then handled as a Lua module.

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
Any other module is loaded only when the script calls `require(...)`.

Detailed module docs live beside the module sources in `M.md`.
