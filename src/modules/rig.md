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

- The global `hooks` table is created during `rig` module load if it does not already exist.
- Custom script languages can be added by appending loader functions to `rig.script_loaders`.
