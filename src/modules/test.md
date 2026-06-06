# `test`

Async test-runner helpers built on top of `uv` and `sched`.

## API

- `test.case(name, fn)`
  - Registers one named test case in the current test file.
  - Registered cases are executed automatically after a `*_test.lua` or `*_test.fnl` file finishes loading.
- `test.serial(name, fn)`
  - Registers one named serial test case in the current test file.
  - Serial cases act as ordering barriers: previously declared non-serial cases run to completion first, then the serial case runs alone, then later non-serial cases may run concurrently again.
- `test.fail(message)`
  - Fails the current test case immediately with an explicit message.
- `test.truthy(value[, message])`
  - Fails unless `value` is truthy.
- `test.falsey(value[, message])`
  - Fails unless `value` is falsey.
- `test.equal(actual, expected[, message])`
  - Fails unless `actual == expected`.
  - On failure it prints both values using `rig.tostring(...)` when available.
- `test.match(value, pattern[, message])`
  - Fails unless `value:match(pattern)` succeeds.
  - `value` must be a string.
  - `pattern` is a Lua pattern string.
- `test.contains_line(value, expected_line[, message])`
  - Fails unless `value` contains one line exactly equal to `expected_line`.
  - Useful for child-process stdout/stderr assertions.
- `test.fixture(setup[, teardown])`
  - Creates a reusable fixture wrapper.
  - Returns a function that accepts one case body function and returns a wrapped case function.
  - Example:
    - `local with_temp = test.fixture(setup, teardown)`
    - `test.case("...", with_temp(function(temp) ... end))`
- `test.discover(options?)`
  - Discovers `*_test.lua` and `*_test.fnl` files.
  - `options.roots` may specify one or more root directories; default is `{ "." }`.
  - Must be called from a scheduler-managed coroutine under `preset = "uv"` because discovery uses `uv.scandir(...)`.
- `test.run(options?)`
  - Discovers test files and runs them in child `rig` processes.
  - Returns a summary table containing:
    - `files`
    - `passed`
    - `failed`
    - `total`
    - `success`
    - `duration`
  - Options:
    - `roots`
    - `files`
    - `jobs`

## Notes

- The current first version runs one child process per test file.
- Parallelism is bounded by `jobs`.
- Within one test file, registered cases are currently executed under `preset = "uv"`, so they may use coroutine-based `uv` APIs such as `uv.spawn(...)` and `uv.scandir(...)`.
- Use `test.serial(...)` for cases that rely on shared mutable state or ordering.
- Each registered case records its own elapsed monotonic duration and prints it in the `PASS` / `FAIL` line.
- Each file run recorded by `test.run(...)` also carries `duration` in seconds as a Lua number.
- Test files without any registered cases still work as plain pass/fail scripts: exiting normally passes, and raising an error fails the file.
