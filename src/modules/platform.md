# `platform`

Small platform-detection helpers built on top of LuaJIT's `jit.os`.

## API

- `platform.os`
  - the current `jit.os` string
- `platform.is_windows()`
- `platform.is_linux()`
- `platform.is_osx()`
- `platform.is_bsd()`
- `platform.is_posix()`
- `platform.is_other()`
- `platform.is_unix()`

## Notes

- `platform.is_unix()` returns `true` for `Linux`, `OSX`, `BSD`, and `POSIX`.
