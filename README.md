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

Initialization order is deterministic by module name (sorted).
For each module, initialization is interleaved:
- Run `rig_register_M(...)` from `M.c` if present.
- Then execute embedded `M.lua` if present.

Each Lua module chunk is called like:

```lua
-- inside M.lua
local rig, M = ...
```

Where:
- `rig` is the global rig table.
- `M` is `rig.M` (created automatically before loading C/Lua parts).
