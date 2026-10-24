# Design Decisions

## Purpose

This document records the design decisions that shape the demo-engine evolution.
Decisions remain in force until explicitly superseded. Progress belongs in `DIARY.md`;
ordered implementation work belongs in `PHASES.md`.

## Status key

- **Accepted** — in force.
- **Superseded by Dn** — retained for history, no longer in force.
- **Proposed** — under review, not yet binding.

---

## D1 — Rig is a code-first demo/creative-coding runtime

**Status:** Accepted (2026-10-24)

The product is a small, single-executable runtime for building one-off demos, effects,
and architectural visualizations from code (usually one Lua file) plus external assets.
"Full-fledged" means complete media coverage and a strong live workflow, not an editor,
ECS, reflection/serialization, networking, or a general physics engine. Larger systems
built with `rig.require` are welcome but are not the target.

## D2 — The simple API is a facade over the builder, not a second runtime

**Status:** Accepted (2026-10-24)

`rig.run` assembles a default composition (bundle, clock, scene, entities, frame
callbacks) using the same builder/compiler/component machinery and the same
`scene`/`render`/`sdl3x.App` objects as a hand-written assembly. It introduces no
parallel runtime and no parallel rendering path. The front door is thin; power users
drop down to `rig.runtime()`.

## D3 — The render scene owns one frame clock

**Status:** Accepted (2026-10-24)

`scene.RenderScene` owns an optional clock and exposes `time` (seconds since scene
start) and `dt`. Motions, behaviors, and `on_update`/`on_draw` callbacks all sample the
same frame context `{ scene, surface, time, dt }`. This removes the earlier split where
the scene path used frame `dt` while the animator used a fixed step. Without a clock
the scene is frozen at time 0, so stills and tests are deterministic.

## D4 — Motion is a node-level transform contributor, pre-multiplied

**Status:** Accepted (2026-10-24)

Transform animation is not a property of `render.Entity`; it is a `motion` object
attached to any `scene.Node`. A node pre-multiplies its motions in list order, so
`local = m1 * m2 * ... * base`. Pre-multiplication makes a rotation motion spin a node
about its own origin instead of orbiting its parent; parent-space effects are achieved
by nesting nodes. `render.Entity` shrinks to "node + mesh/backend".

## D5 — Closed-form procedural animation is the default

**Status:** Accepted (2026-10-24)

Ambient motion is expressed as `f(time)` where possible: deterministic, scrubbable, and
recordable without simulation history. Integration over `dt` is not forbidden; it is
placed on `Node:step(surface, frame)` as behavior, not inside a closed-form motion.

## D6 — Reactive worlds are state plus closed-form, not a rejection of it

**Status:** Accepted (2026-10-24)

Interaction and walk-through worlds require mutable state, an ordered behavior layer,
events/picking, and local clocks. That state does not conflict with closed-form motion:
a motion's `anchor` is set by interaction, after which the motion is again a pure
function of local time (`f(time - anchor)`). Determinism is preserved by fixed timestep
plus recorded input, so closed-form is a convenience for scrubbing, not a prerequisite
for reproducibility.

## D7 — Engine structure is optional for demos

**Status:** Accepted (2026-10-24)

The plugin/descriptor/capability/bundle model remains the runtime's engine and is kept,
but it is not required to draw a demo. The code-first facade is the default entrypoint;
structured composition is reached for as a demo grows. The retained node tree stays
lean; DI is reserved for runtime-scoped services and larger systems.

## D8 — Layers on the node tree

**Status:** Accepted (2026-10-24)

Four concerns share the same node tree and grow independently: **motion** (transform
contribution), **behavior/step** (state mutation), **interaction/event** (triggers,
picking, messages), and **world model** (identity, extraction, culling). Interaction
and world layers are planned, not built.

## D9 — Backend-agnostic transform concerns live in `motion`

**Status:** Accepted (2026-10-24)

`motion` is a `mathx`-level module, independent of graphics backends, and owns transform
contributors. Backend scene/mesh shapes stay behind `render.scene.impl`/`render.mesh`
capabilities resolved from the bundle. This keeps the layering "backend-agnostic in
`rig`-level modules, backend-specific behind capabilities".

## D10 — This effort follows the `20261023-redesign` document convention

**Status:** Accepted (2026-10-24)

Design work is recorded as a dated folder with `PLAN.md`, `DECISIONS.md`, `PHASES.md`,
`INVENTORY.md`, and `DIARY.md`, mirroring `docs/20261023-redesign`. Phases are ordered
and independently testable; each is complete only when `make test` passes after a
rebuild.

## D11 — Immediate drawing lives on the scene and uses the mesh factory

**Status:** Accepted (2026-10-24)

`draw_mesh`, `push_transform`, `pop_transform`, and `mesh_drawable` are methods on
`scene.RenderScene`, inherited by the backend scene implementations. They draw through
the composition's resolved `render.mesh` factory (lazily creating and caching one
backend drawable per mesh) rather than introducing a parallel drawing path. The factory
is optional: a scene without `render.mesh` simply cannot draw meshes immediately. This
keeps the immediate API on `frame.surface`, which is the scene already handed to
callbacks.

## D12 — Meshes carry topology; materials are optional shader overrides

**Status:** Accepted (2026-10-24)

Meshes declare a `topology` (`"triangles"` or `"lines"`) so backend factories choose
the matching primitive type; line meshes do not need pixels-as-triangles hacks. A
`render.material` is an optional GLSL vertex/fragment override for the built-in unlit
position/color material, sharing the same `u_mvp` uniform contract. Drawables are
cached per `(mesh, material)`. Materials are values (sources), not a parameter system;
uniform/parameter binding beyond `u_mvp` is deferred.

## D13 — Camera controls are optional opt-in controllers

**Status:** Accepted (2026-10-24)

Camera navigation is never enabled automatically. `camera` provides backend-agnostic
`Orbit`/`Fly` controller values; a sketch opts in with `app:add_camera_controls` or the
`camera_controls` run option, and hand-built apps wire the controllers themselves. The
facade routes `sdl3.key`/`sdl3.mouse`/`sdl3.resize` through a per-run execution
subclass, so input is available to sketches without requiring every demo to define an
`App` class.

## D14 — Assets are path-relative and decoder-backed

**Status:** Accepted (2026-10-24)

Asset paths resolve against the directory of the calling script (via
`debug.getinfo` + `rig.source_of`/`rig.dirname`), so demos ship next to their assets
and run from anywhere. Loaded data is cached by canonical path (`rig.realpath`).
Decoding is layered: `png` uses libpng's simplified API directly through FFI (it
avoids `setjmp`), while `jpeg` needs a minimal `jpeg.c` for the `setjmp`-guarded
libjpeg call and keeps everything else in FFI. JPEG is an optional build dependency;
a stub keeps builds without libjpeg headers working. These expand the existing toolbar
without adding a mandatory dependency.

## D15 — Textures are values; sampling is a material concern

**Status:** Accepted (2026-10-24)

A `render.texture` is a backend-neutral value wrapping a decoded image plus filter and
wrap options. Backend `render.texture` factories upload it and share one backend
texture per value; the mesh factory resolves and binds it, so a `render.material` can
carry a texture without knowing the backend. Materials bind the texture at slot 0 and
expose a `u_texture` uniform to both the built-in textured shader and custom shaders.
Texturing requires UVs, so textured meshes use a separate `position_color_uv_f32`
layout rather than overloading the position/color layout; generators without
meaningful UVs stay on `position_color_f32`. OBJ parsing and `asset.mesh` build the UV
layout.

## D16 — Render targets are values; passes chain through the scene

**Status:** Accepted (2026-10-24)

A `render.target` is a backend-neutral offscreen surface value, like `render.texture`.
Backend factories create one surface per value and expose its `.texture` handle, so a
material that samples a target and the pass that renders into it share one object
without the user wiring backend handles. `scene.RenderScene:render_to(target, draw)`
owns the offscreen pass (sizing the view/projection and restoring the window), with
backend `enter_target`/`leave_target` hooks; `draw_fullscreen` is the matching
screen-space pass. Backends normalize orientation themselves: because GL offscreen
textures are bottom-up, the GL hook flips clip-space Y while rendering into a target
so all sampled surfaces are top-down. A general render graph stays out of scope.

## D17 — Input is consolidated state; overlays are immediate, not retained

**Status:** Accepted (2026-10-24)

The runtime already emits `sdl3.key`/`sdl3.mouse` payloads; `input.Input` consolidates
them into held/pressed/released state and mouse deltas, addressed by scancode or
name, and exposes it as `frame.input`. Edges are cleared at the end of the frame so
all callbacks see the same events. Live parameters are a plain clamped store
(`params`), and the overlay is immediate: it draws screen-space bars through
`RenderScene:draw_screen` from a post-children `on_overlay` hook and edits values
from `input`. It is explicitly not a retained UI toolkit; labels are an optional
`draw_text` callback rather than built-in text.

## D18 — Audio is one stream per voice, with graceful degradation

**Status:** Accepted (2026-10-24)

Audio playback is deliberately minimal: `audio.load` returns a refcounted WAV
`Clip`, and `audio.play` opens one `SDL_AudioStream` per `Voice` (no mixer or DSP
graph). Looping is refilled from `audio.update()` each frame, which the sketch
facade calls; hand-built apps call it themselves. Lifetimes are deterministic:
clips are refcounted and a `Scope` releases the clips and voices it holds. The
subsystem initializes lazily, and loading or playing returns `nil, error` when no
device is available, so a demo runs silently rather than failing on a machine without
audio.