# `rig`

Core runtime helpers that are always loaded at interpreter startup.

## API

- `rig.tostring(value)`
  - Serializes tables into Lua-like source text.
  - Falls back to the normal global `tostring` for non-table values.
- `rig.print(...)`
  - Writes arguments to `stdout` separated by spaces.
  - Does not append a trailing newline.
- `rig.println(...)`
  - Same as `rig.print(...)`, but appends `\n`.
- `rig.register_runtime_mode(name, mode)`
  - Registers a named runtime mode that can be selected explicitly by `rig.run(...)`.
- `rig.register_runtime_hook(phase, hook)`
  - Registers a hook function for a named runtime phase.
  - Current built-in phases used by the `sdl3` modes are:
    - `before_setup`
    - `after_setup`
    - `before_poll`
    - `after_poll`
    - `before_frame`
    - `after_frame`
    - `before_shutdown`
    - `after_shutdown`
- `rig.run(options?)`
  - Starts the explicitly selected runtime mode.
  - `options.mode` is mandatory.
  - All built-in runtime modes create and own a scheduler.
  - The current first version ships with `sdl3`-owned modes such as `"sdl3"`, `"sdl3_gl"`, and `"sdl3_gpu"` when the `sdl3` module has been loaded.
  - Mode-specific configuration should live under a namespaced key such as `options.sdl3`, `options.sdl3_gl`, or `options.sdl3_gpu`.
  - Optional per-run hooks may be passed under `options.hooks`.
  - `options.hooks.<phase>` may be either a function or an array of functions.
  - Global hooks registered through `rig.register_runtime_hook(...)` run first, then the per-run hooks for the same phase.
- `rig.resource_scope(context, label?)`
  - Creates a generic ownership scope.
  - `scope:adopt(resource, release_fn)` tracks a resource with a custom release function.
  - `scope:replace(key, resource, release_fn)` replaces a named resource, releasing the old one immediately.
  - `scope:release()` releases tracked resources in reverse order.
  - `release_fn` receives `(context, resource)`.
- `rig.executable_path`
  - String path used to launch the current Rig executable.
  - Initialized from `argv[0]` at process startup.
- `rig.script_loaders`
  - Ordered list of script loader functions.
  - Built in with Lua first and Fennel second.
  - Each loader receives `(script_path, source)` and should return either a compiled chunk or `nil, err`.
- `rig.load_script(script_path, source)`
  - Runs `rig.script_loaders` in order until one returns a compiled chunk.
  - Executes the first accepted chunk.
  - Raises a combined error if no loader accepts the source.
- `rig.run_script_file(script_path)`
  - Reads the file with `io.open(..., "rb")` and forwards the contents to `rig.load_script(...)`.

## Notes

- Custom script languages can be added by appending loader functions to `rig.script_loaders`.
