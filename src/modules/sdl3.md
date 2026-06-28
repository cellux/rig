# `sdl3`

Lazy SDL3 binding built on LuaJIT FFI.

The SDL shared library is loaded only when the module is required.

## Scope

`sdl3` is the low-level binding layer:

- raw SDL functions
- raw SDL constants
- FFI-exposed SDL types used by higher-level modules

Higher-level Rig integration lives in `sdl3x`, including:

- SDL runtime modes for `rig.run(...)`
- window creation defaults
- SDL event translation
- font renderer providers
- GPU convenience builders and resource scopes
- OpenGL and SDL GPU convenience helpers

## Raw SDL Surface

The module exports bound SDL entry points with their SDL names minus the `SDL_` prefix.

Examples:

- `sdl3.Init(...)`
- `sdl3.QuitSubSystem(...)`
- `sdl3.WasInit(...)`
- `sdl3.GetError()`
- `sdl3.CreateWindowWithProperties(...)`
- `sdl3.CreateRenderer(...)`
- `sdl3.RenderPresent(...)`
- `sdl3.GL_CreateContext(...)`
- `sdl3.CreateGPUDevice(...)`
- `sdl3.CreateGPUShader(...)`
- `sdl3.CreateGPUGraphicsPipeline(...)`

This module also exposes the raw SDL property setters and lifecycle functions:

- `sdl3.CreateProperties()`
- `sdl3.DestroyProperties(props)`
- `sdl3.SetPointerProperty(props, name, value)`
- `sdl3.SetStringProperty(props, name, value)`
- `sdl3.SetNumberProperty(props, name, value)`
- `sdl3.SetFloatProperty(props, name, value)`
- `sdl3.SetBooleanProperty(props, name, value)`
- `sdl3.ClearProperty(props, name)`

## Notes

- If you want SDL runtimes, require `sdl3x`.
- If you want owning `SDL_PropertiesID` wrappers, use `sdl3x.Properties`.
- If you want GPU descriptor builders or runtime-owned GPU resource scopes, use `sdl3x`.
