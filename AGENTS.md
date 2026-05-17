# Notes

- Do not run `make` and any `./build/rig ...` smoke tests in parallel.
- Build first, wait for it to finish, then run smoke tests.

## API Naming

- When exposing a C API through a Lua module, mirror the original C naming after removing the module or library prefix.
- Preserve the original casing style:
  - `CamelCase` stays `CamelCase`
  - `snake_case` stays `snake_case`
- If a C module prefixes all symbols with its module name, expose that prefix as the Lua module name and remove it from the member name.
  - Example:
    - C: `SDL_GetTicks`
    - Lua: `sdl3.GetTicks`
- Any additional Lua-only abstractions layered on top of a C API must use `snake_case`.
- Single-word lowercase names count as `snake_case`.
- Constant names may mirror the original C names exactly after removing the module or library prefix.
  - There is no need for double underscores in constant names.
  - We do not reserve constant names for any separate Rig-owned naming scheme.
- Constants may remain in all-caps when mirroring foreign APIs or representing enum-like values.
- If a Rig C module loads symbols dynamically via `dlsym`, each bound symbol should use a `rig_X__NAME` identifier in `X.c`.
  - Use a double underscore for dynamically bound symbols from the underlying C library.
- If a Rig C module implements its own Lua-facing abstraction in `X.c`, its identifier should use `rig_X_NAME`.
  - Use a single underscore for Rig-owned wrapper or abstraction names.
