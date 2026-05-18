# Notes

- Do not run `make` and any `./build/rig ...` smoke tests in parallel.
- Build first, wait for it to finish, then run smoke tests.
- If you only change a Lua or Fennel script such as an example or test file, you do not need to rebuild `rig`.
  - Rebuild only when changing C code, build files, or embedded builtin module sources that are compiled into the executable.

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
- If a Rig C module loads symbols dynamically via `dlsym`, each bound symbol should use a `rig_X__NAME` identifier in `X.c`.
  - Use a double underscore for dynamically bound symbols from the underlying C library.
- If a Rig C module implements its own Lua-facing abstraction in `X.c`, its identifier should use `rig_X_NAME`.
  - Use a single underscore for Rig-owned wrapper or abstraction names.
- Constant names may mirror the original C names exactly after removing the module or library prefix.
  - There is no need for double underscores in constant names.
  - We do not reserve constant names for any separate Rig-owned naming scheme.
- Constants may remain in all-caps when mirroring foreign APIs or representing enum-like values.

## Runtime And API Design

- `rig.run(...)` is the only public runtime entrypoint.
  - Runtime-aware modules should register modes and hooks with `rig`.
  - Backend modules should not expose their own public main-loop driver.
- Per-run startup and runtime configuration should go through `rig.run(...)` options.
  - Avoid monkey-patching module globals to control runtime behavior.
  - Use module-scoped option tables such as `sdl3 = { ... }`, `sdl3_gpu = { ... }`, and `uv = { ... }`.
  - Use `options.hooks` for run-local hooks and `rig.register_runtime_hook(...)` for persistent module-level hooks.
- Public async APIs should be coroutine-based.
  - Callback-style async APIs are internal implementation details.
  - User-facing async operations should suspend through `sched`.
- `sched` is the generic scheduler layer.
  - Backend-specific yield protocol details should be hidden behind module APIs.
  - Users should not have to call `sched.await("backend.op", ...)` directly when a proper wrapper exists.
- If a utility is backend-agnostic, put it in `rig`.
  - Backend-specific modules may wrap it with backend-specific convenience methods.
- Runtime behavior must not depend on module load order.
  - Use explicit runtime mode ownership via `mode = "..."`.
