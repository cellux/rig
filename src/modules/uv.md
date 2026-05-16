# `uv`

Minimal libuv integration for Rig.

## API

- `uv.get_loop()`
  - Returns the current active libuv loop handle for `mode = "uv"`, or `nil` if no uv runtime is active.
- `uv.stop()`
  - Requests the current uv loop to stop.
  - Requires an active `mode = "uv"` runtime.
- `uv.spawn(spec)`
  - Suspends the current scheduler-managed coroutine, spawns a child process on the current uv loop, and resumes the coroutine later with the captured result.
  - `spec.file` is required.
  - `spec.args` is optional; if omitted, it defaults to `{ spec.file }`.
  - `spec.cwd` is optional.
  - Returns a `result` table containing:
    - `exit_status`
    - `term_signal`
    - `stdout`
    - `stderr`
    - `success`
- `uv.scandir(path)`
  - Suspends the current scheduler-managed coroutine, scans one directory on the current uv loop, and resumes the coroutine later with the directory entries.
  - Returns `entries` on success, or `nil, err` on failure.
  - Each entry is a table containing:
    - `name`
    - `type`

## Constants

- `uv.DIRENT_UNKNOWN`
- `uv.DIRENT_FILE`
- `uv.DIRENT_DIR`
- `uv.DIRENT_LINK`
- `uv.DIRENT_FIFO`
- `uv.DIRENT_SOCKET`
- `uv.DIRENT_CHAR`
- `uv.DIRENT_BLOCK`

## Runtime Mode

`uv` registers the runtime mode `"uv"`.

Use it through:

```lua
local uv = require("uv")

rig.run {
   mode = "uv",
   uv = {
      main = function()
         local result = uv.spawn {
            file = "./build/rig",
            args = { "./build/rig", "script.lua" },
         }
         rig.println(result.stdout)
      end,
   },
}
```

`uv.main` is optional. If provided, it runs as a scheduler-managed coroutine after setup and before the libuv loop starts blocking.

## Notes

- The current first version is intentionally narrow.
- It is designed to support subprocess orchestration first, which is the main building block needed for a future async test runner.
- The callback boundary remains internal to the module; user code should use the straight-line coroutine API.
