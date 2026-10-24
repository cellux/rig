# `rig`

Core runtime helpers that are always loaded at interpreter startup.

## API

- `rig.repr(value[, options])`
  - Alias for `repr.repr(value[, options])`.
  - Returns a best-effort Lua-readable representation for any value.
- `rig.set(values)`
  - Alias for `prelude.set(values)`.
  - Builds a membership set table from the array part of `values`.
- `rig.Class`
  - Alias for `prelude.Class`.
  - Metaclass shared by all class tables created by `rig.Class(...)`.
  - Calling `rig.Class(parent?)` creates a new callable class table.
  - Calling a class constructs one instance whose metatable is the class table.
  - Instances expose `:super()` to return the immediate parent class table, if any.
  - Class tables expose `:is_descendant(ancestor)` to test inheritance against a parent class.
  - Class tables expose `:is_ancestor(descendant)` to test whether another class inherits from them.
  - All class tables use `rig.Class` as their metaclass.
- `rig.is_class(value)`
  - Alias for `prelude.is_class(value)`.
  - Returns `true` when `value` is a class table created by `rig.Class(...)`.
  - Returns `true` for `rig.Class` itself.
  - Returns `false` for ordinary instances.
- `rig.raise(message[, ...])`
  - Alias for `prelude.raise(message[, ...])`.
  - Raises an error without adding Lua stack-location prefixes.
  - If extra arguments are provided, formats the message through `string.format(...)` first.
- `rig.create_ffi_library_loader(options)`
  - Builds a lazy `ffi.load(...)` wrapper with cached success and cached failure.
  - `options.label` is required and is used in the cached error message.
  - `options.candidates` is a required array of library names to try in order.
  - Returns a function that loads the first matching candidate on first call and returns the cached library handle on later calls.
- `rig.runtime()`
  - Returns a new `runtime.Builder` for the compositional runtime model.
  - Lazily requires the `runtime` module (`require("runtime").Builder()`).
  - See `runtime.md` for the builder/compiler/start API.
- `rig.run(options?, build?)`
  - Code-first sketch entrypoint. Assembles a default composition (bundle, scene
    with camera, entities, frame callbacks) on top of the builder/compiler/
    component runtime, so a demo can be a single Lua file.
  - `rig.run(build)` is shorthand for `rig.run { build = build }`.
  - Blocks until the sketch exits; returns the `sketch.App`.
  - Lazily requires `sketch`, so core `rig` stays independent of the graphics
    backends at load time. See `sketch.md`.
- `rig.ResourceScope(context, label?)`
  - Callable class constructor for generic ownership scopes.
  - Instances provide `:adopt(...)`, `:replace(...)`, and `:release()`.
  - `:release()` releases in reverse acquisition order, continues past individual
    failures, and returns a list of error strings.
- `rig.tostring(value)`
  - Returns `tostring(value)` for values with a `__tostring` metamethod.
  - Returns `rig.repr(value)` for other tables.
  - Falls back to the builtin global `tostring(value)` for non-table values.
- `rig.print(...)`
  - Writes arguments to `stdout` separated by spaces.
  - Formats each argument through `rig.tostring(...)`.
  - Does not append a trailing newline.
- `rig.printf(format_string, ...)`
  - Formats the arguments through `string.format(...)`.
  - Writes the result through `rig.print(...)`.
- `rig.fprint(stream, ...)`
  - Writes arguments to the given stream separated by spaces.
  - Formats each argument through `rig.tostring(...)`.
  - Does not append a trailing newline.
- `rig.fprintf(stream, format_string, ...)`
  - Formats the arguments through `string.format(...)`.
  - Writes the result through `rig.fprint(stream, ...)`.
- `rig.fprintln(stream, ...)`
  - Same as `rig.fprint(stream, ...)`, but appends `\n`.
- `rig.println(...)`
  - Same as `rig.print(...)`, but appends `\n`.
- `rig.argv`
  - Table mirroring the raw C `argv` array for the current Rig process.
  - `rig.argv[0]` is the interpreter path from `argv[0]`.
  - `rig.argv[1]` is the script path, followed by script arguments at higher indices.
- `rig.script_loaders`
  - Ordered list of script loader functions.
  - Built in with Lua first and Fennel second.
  - Each loader receives `(source, script_path)` and should return either a compiled chunk or `nil, err`.
- `rig.load_script(source, script_path)`
  - Runs `rig.script_loaders` in order until one returns a compiled chunk.
  - Executes the first accepted chunk.
  - Raises a combined error if no loader accepts the source.
- `rig.run_script_file(script_path)`
  - Reads the file with `io.open(..., "rb")` and forwards the contents to `rig.load_script(...)`.
- `rig.require(module_name)`
  - Loads a module. When `module_name` begins with `.` it is resolved against the
    directory of the calling script file, so `rig.require("./helper")` loads a
    sibling `helper.lua`/`helper.fnl` (or `helper/init.lua`/`helper/init.fnl`).
  - Relative modules are executed through `rig.load_script` and cached in a
    rig-private table keyed by canonical absolute path (`rig.realpath`), so
    equivalent spellings and symlinks share one instance and the modules never
    enter -- or conflict with -- the stock Lua `require` cache. Nested relative
    requires resolve against their own file.
  - Every other name is forwarded unchanged to the stock Lua `require`.
- `rig.realpath(path)`
  - Returns the canonical absolute path for `path`, resolving symlinks and
    relative components.
  - Returns `nil, message` when the path does not exist or cannot be resolved.
  - Backed by `realpath` on POSIX and `_fullpath` on Windows; no async backend is
    required.
- `rig.source_of(info)`
  - Parses the file path out of a `debug.getinfo(...)` result (`info.source`),
    returning `nil` for chunks loaded from strings. Used to resolve paths relative
    to a calling script.
- `rig.dirname(path)`
  - Returns `path`'s directory including the trailing separator, or `""`.
- `rig.join_path(directory, path)`
  - Joins `directory` and `path`; absolute paths and Windows drive paths pass
    through unchanged.
- `rig.file_exists(path)`
  - Returns whether `path` can be opened for reading.
- `rig.read_file(path)`
  - Returns the file contents as a binary string, or `nil, message`.
  - Used by `rig.require`, `shader`, and `asset`.

## Notes

- Custom script languages can be added by appending loader functions to `rig.script_loaders`.
- The current runtime model is the builder/compiler/start API in `runtime.md`; the legacy `rig.run`/driver/preset/service-registry API has been removed.
