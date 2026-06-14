# `windows`

Low-level Windows OS definitions exposed with their original Win32 and COM names.

## API

- The module defines common Windows and COM C types through `ffi.cdef`, including:
  - `BYTE`, `UINT32`, `UINT64`, `UINT`, `ULONG`, `HRESULT`, `SIZE_T`
  - `WCHAR`, `LPWSTR`, `LPCWSTR`, `LPSTR`, `LPCSTR`
  - `LPVOID`, `LPCVOID`, `DWORD`, `HANDLE`, `HMODULE`
  - `GUID`, `CLSID`, `IID`, `IUnknown`, `IUnknownVtbl`, `FARPROC`
- The module exports these constants with their original Windows names:
  - `CP_UTF8`
  - `FORMAT_MESSAGE_IGNORE_INSERTS`
  - `FORMAT_MESSAGE_FROM_SYSTEM`
- On Windows, the module also exports these APIs directly:
  - `GetLastError`
  - `FormatMessageA`
  - `MultiByteToWideChar`
  - `GetModuleHandleW`
  - `LoadLibraryW`
  - `GetProcAddress`
  - `FreeLibrary`

## Notes

- This module does not provide Rig-specific wrapper names.
- On non-Windows hosts, the shared type and constant definitions remain available so modules can still use Windows ABI types in FFI declarations.
