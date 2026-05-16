# `uv`

Minimal libuv integration for Rig.

## API

- `uv.get_loop()`
  - Returns the current active libuv loop handle for `mode = "uv"`, or `nil` if no uv runtime is active.
- `uv.stop()`
  - Requests the current uv loop to stop.
  - Requires an active `mode = "uv"` runtime.
- `uv.spawn(spec)`
  - Spawns a child process on the current uv loop and captures its `stdout` and `stderr`.
  - `spec.file` is required.
  - `spec.args` is optional; if omitted, it defaults to `{ spec.file }`.
  - `spec.cwd` is optional.
  - `spec.on_exit(result)` is required.
  - `result` contains:
    - `exit_status`
    - `term_signal`
    - `stdout`
    - `stderr`
    - `success`

## Runtime Mode

`uv` registers the runtime mode `"uv"`.

Use it through:

```lua
local uv = require("uv")

rig.run {
   mode = "uv",
   uv = {
      main = function()
         uv.spawn {
            file = "./build/rig",
            args = { "./build/rig", "script.lua" },
            on_exit = function(result)
               rig.println(result.stdout)
            end,
         }
      end,
   },
}
```

`uv.main` is optional. If provided, it runs after setup and before the libuv loop starts blocking.

## Notes

- The current first version is intentionally narrow.
- It is designed to support subprocess orchestration first, which is the main building block needed for a future async test runner.
