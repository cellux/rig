# Rig Demo-Engine Evolution

## Purpose

This document is the design plan for evolving Rig from a low-level runtime into a
small, code-first engine for building one-off demos, effects, and architectural
visualizations from Lua — typically a single file plus external assets. It records the
intended product shape, the layering, the animation model, and how the simple front
door relates to the builder/compiler/component machinery built in the earlier
`20261023-redesign` work.

## Goal

Make Rig a LÖVE/raylib/p5/nannou-class runtime: small, immediate, and complete enough
to produce visual work from code, while remaining a powerful compositional runtime for
larger systems.

Concretely:

1. a code-first entrypoint (`rig.run`) with almost no ceremony;
2. a frame context (`time`, `dt`, `scene`, `surface`) shared by animation and
   callbacks;
3. transform animation as composable `motion` contributors on `scene.Node`, not
   hard-coded into entities;
4. closed-form procedural animation by default, with stateful behavior expressed on
   `Node:step`, so reactive, walk-through worlds remain possible;
5. everything implemented on top of the existing builder/compiler/component runtime,
   never as a parallel engine.

## What "full-fledged" means here

Not editor, ECS, reflection, or networking. For this product it means **complete media
coverage plus a great live workflow**: one lifecycle, direct 2D/3D drawing, a camera,
time as a first-class thing, shaders and render targets as ordinary objects, assets by
path, input, text, audio, a dev overlay, hot reload/REPL, and offline/headless
recording. The runtime loop is a small part; ergonomics and iteration are the product.

## Design principles

- **Small front door, real machinery.** `rig.run` is a facade that assembles a default
  composition. It adds no second runtime and no parallel rendering path. Power users
  drop down to `rig.runtime()` with the same components.
- **Optional structure.** The plugin/descriptor/capability model is a power tool for
  larger systems, not a requirement for a one-file demo.
- **One time source.** The render scene owns the frame clock; motions, behaviors, and
  callbacks sample the same `time`/`dt`.
- **Closed-form first.** Ambient motion is `f(time)`: deterministic, scrubbable,
  recordable. State and integration are introduced only where interaction requires
  them.
- **Reactive worlds are state + closed-form.** Interaction sets state (for example a
  motion's anchor); the resulting animation is still a function of local time.
- **Layered concerns.** motion, behavior/step, interaction/event, and world model are
  separate layers on the same node tree.
- **Backend-agnostic stays in `rig`-level modules.** Transform motion is `mathx`-level
  and lives in `motion`; rendering and scene shape stay behind capabilities resolved
  from the bundle.
- **No backward compatibility.** Sole author; old APIs are removed once in-repo
  callers are migrated.

## Target user experience

A complete sketch is one file:

```lua
local rig = require("rig")
local mesh = require("mesh")
local motion = require("motion")

rig.run {
   title = "Spinning Cube",
   build = function(app)
      app:add_entity {
         mesh = mesh.make_cube { size = 2.0, colors = ... },
         motion = motion.spin { x = 0.7, y = 1.0 },
      }
   end,
}
```

Larger work keeps using the builder:

```lua
local builder = rig.runtime()
sdl3x.bundle_sdl3_gl(builder, { window_props = ... })
builder:use(scene.plugin())
builder:use(render.plugin())
builder:add(scene.container_component(scene.plugin(), { name = "scene", camera = ... }))
builder:add(render.entity_component(render.plugin(), { name = "cube", mesh = ..., motion = ... }))
builder:execute(sdl3x.App):compile():start()
```

## Architecture

### Layers

```
sketch facade        rig.run { build, update, draw }  (ergonomic defaults)
        |
builder / components runtime (plugins, capabilities, descriptors, compile/start)
        |
scene + render       transform tree, entities, camera, frame clock
        |
motion / behavior    transform contributors f(time, state) and step behaviors
        |
sdl3x / gl / gpu     backend scene implementations and mesh factories
```

### Frame context

`scene.RenderScene` owns an optional clock and maintains `time` (seconds since scene
start) and `dt`. Each `render` advances time, builds a frame context, calls
`on_update`, opens the backend frame, updates view/projection, calls `on_draw`, renders
the children, and closes the frame. The frame context is
`{ scene, surface, time, dt }`. Without a clock the scene is frozen at time 0, which
keeps stills and unit tests deterministic.

### Motion

A `motion` is a transform contributor with `contribute(out, node, frame)`. A node
pre-multiplies its motions in list order:

```
local = m1 * m2 * ... * base
```

Pre-multiplication makes a rotation motion spin a node about its own origin rather
than orbit its parent. `motion.Spin` is closed-form and samples `frame.time`; a motion's
`anchor` is the state an interaction uses to start a local animation. Integrated
behavior belongs on `Node:step(surface, frame)`.

### Reactive worlds

Nothing about closed-form motion blocks interaction. The two axes are independent:
*expression* (closed-form vs integrated) and *source* (time, input, state). A reactive
world adds mutable state, an ordered behavior layer, events/picking, and local clocks;
motions then read that state. A door is `f(time - state.opened_at)`, still closed-form.
Determinism is preserved by a fixed timestep plus recorded input, not by avoiding
state.

## Scope

**In scope (this effort).** `motion` and the frame context; `render.Entity` as motion
consumer; `rig.run` facade; migrating examples; drawing surface; camera controls;
assets; render-to-texture; params overlay; recording/headless; hot reload/REPL; audio.

**Out of scope.** Editor, ECS, general reflection/serialization, networking, general
physics, an asset-cooking pipeline.

## Relationship to `20261023-redesign`

That redesign replaced the legacy immediate `rig.run` with the builder/compiler/start
model and is the foundation this plan builds on. This effort reintroduces a *new*
`rig.run` whose meaning is a facade over that builder model, not the removed legacy
driver API. It keeps the earlier decisions (single-author, no compatibility layer,
capability/descriptor composition, single runtime entrypoint) and adds a product-level
opinion about closed-form animation, one clock, and a code-first front door.