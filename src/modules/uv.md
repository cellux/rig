# `uv`

Minimal libuv integration for Rig.

## API

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
- `uv.fs_read(path)`
  - Suspends the current scheduler-managed coroutine, reads the whole file asynchronously, and resumes with its bytes as a Lua string.
  - Reads in chunks and reassembles them, so files larger than one read are handled.
  - Returns `contents` on success, or `nil, err` on failure.
- `uv.fs_write(path, data)`
  - Suspends the current scheduler-managed coroutine, truncates/creates `path`, and writes the bytes of the Lua string `data`.
  - Returns the number of bytes written on success, or `nil, err` on failure.
- `uv.fs_stat(path)`
  - Suspends the current scheduler-managed coroutine and resumes with file metadata.
  - Returns `stat` on success, or `nil, err` on failure. `stat` contains:
    - `size` (bytes)
    - `mtime` (epoch seconds, fractional)
    - `mode`
    - `is_file` / `is_dir` / `is_symlink`
- `uv.sleep(seconds)`
  - Suspends the current scheduler-managed coroutine for at least the requested number of seconds on the current uv loop.
- `uv.now()`
  - Returns epoch seconds as a Lua number through libuv.
- `uv.monotonic()`
  - Returns monotonic seconds as a Lua number through libuv.

## Constants

- `uv.DIRENT_UNKNOWN`
- `uv.DIRENT_FILE`
- `uv.DIRENT_DIR`
- `uv.DIRENT_LINK`
- `uv.DIRENT_FIFO`
- `uv.DIRENT_SOCKET`
- `uv.DIRENT_CHAR`
- `uv.DIRENT_BLOCK`

## Runtime Bundle

`uv` exposes the `uv.bundle_uv(builder, options)` convenience bundle, which attaches
the runtime scheduler plugin and the uv plugin and adds the uv clock, timer,
scheduler, and loop components:

```lua
local uv = require("uv")

local builder = rig.runtime()
uv.bundle_uv(builder)
builder:execute(function(ctx)
   local result = uv.spawn {
      file = "./build/rig",
      args = { "./build/rig", "script.lua" },
   }
   rig.println(result.stdout)
end):compile():start()
```

The uv loop component requires an existing scheduler; it does not create one. The
`sketch` facade (`rig.run`) uses `uv.plugin()` + `uv.loop_component()` to layer uv on
top of the scheduler assembled by the backend bundle, so every sketch has a loop.

## Runtime Components

`uv` also exposes composable components for the runtime model (see
`runtime.md`). They reuse the same FFI bindings but keep all state in component
instances instead of module globals.

- `uv.plugin([spec])`
  - Returns a plugin declaring the `sched.clock` and `uv.loop` capabilities.
- `uv.clock_component(plugin, options)`
  - Provides `sched.clock` (`protocol = "sched"`) backed by libuv time.
- `uv.loop_component(plugin, options)`
  - Requires `sched.scheduler`; creates a `uv.UvLoop`, installs the `uv.spawn`,
    `uv.scandir`, `uv.fs_read`, `uv.fs_write`, and `uv.fs_stat` handlers on that
    scheduler, and contributes a `wait` operation that runs the loop while async work
    is pending.
  - The created loop is owned by the runtime and released on shutdown.
- `uv.UvLoop`
  - Component object exposing `spawn(spec)`, `scandir(path)`, `fs_read(path)`,
    `fs_write(path, data)`, `fs_stat(path)`, `sleep(seconds)`, `stop()`, `now()`,
    `monotonic()`, and `release()`.

Example:

```lua
local rig = require("rig")
local runtime = require("runtime")
local uv = require("uv")

local core = runtime.scheduler_plugin()
local uv_plugin = uv.plugin()

local compiled = rig.runtime()
   :use(core)
   :use(uv_plugin)
   :add(uv.clock_component(uv_plugin, { name = "clock" }))
   :add(runtime.timer_component(core, { name = "timer" }))
   :add(runtime.scheduler_component(core, { name = "scheduler" }))
   :add(uv.loop_component(uv_plugin, { name = "uv" }))
   :execute(function(ctx)
      local result = ctx.uv:spawn {
         file = "sh",
         args = { "sh", "-c", "printf hello" },
      }
      rig.println(result.stdout)
   end)
   :compile()

compiled:start()
```

## Notes

- The current first version is intentionally narrow.
- It is designed to support subprocess orchestration first, which is the main building block needed for a future async test runner.
- The callback boundary remains internal to the module; user code should use the straight-line coroutine API.

## Convenience Bundle

`uv.bundle_uv(builder, options)` attaches the scheduler and uv plugins and adds the uv
clock, timer, scheduler, and loop components. `options.timer` may supply a timer
instance.

```lua
local builder = rig.runtime()
uv.bundle_uv(builder)
builder:execute(function(ctx)
   ctx.uv:spawn { file = "sh", args = { "sh", "-c", "printf hi" } }
end):compile():start()
```
