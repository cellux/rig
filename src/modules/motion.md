# motion

`motion` provides backend-agnostic transform contributors for `scene.Node`. A motion
is a small object with a `contribute(out, node, frame)` method; the node pre-multiplies
each attached motion onto its stored base local matrix, in list order:

```
local = m1 * m2 * ... * base
```

Because motions pre-multiply, a rotation motion spins a node about its own origin
instead of orbiting its parent. Motions read the frame context
`{ time, dt, scene, surface }`.

## Exports

- `motion.Motion`
  - Base class. Subclass it and override `contribute`.
  - `motion:contribute(out, node, frame)` — pre-multiplies the contribution onto `out`
    and returns it. The base implementation is a no-op.
  - `motion:set_anchor(time)` / `motion.anchor` — optional local time origin, in
    scene seconds.
  - `motion:local_time(frame)` — `frame.time - anchor` when anchored, otherwise
    `frame.time`.
- `motion.Spin` / `motion.spin(options)`
  - Closed-form axis rotation.
  - `options.x`, `options.y`, `options.z` — radians per second around each axis.
  - `options.angle` — constant angle added to the time-driven rotation.
  - `options.anchor` — local time origin.
  - When no axis is supplied, defaults to `x = 0.7, y = 1.0` (the classic demo spin).

## Closed form and reactivity

A motion is `f(time, state)`. `Spin` is closed-form: it samples `frame.time`, so it is
deterministic, scrubbable, and needs no integration. Event-driven animation uses the
anchor as the state that starts it, after which it is again a pure function of local
time:

```lua
door_motion:set_anchor(frame.time)   -- when the interaction begins
```

Behavior that genuinely integrates over `dt` (velocity, springs) belongs on
`Node:step(surface, frame)`, not in a closed-form motion.

## Example

```lua
local motion = require("motion")

entity:add_motion(motion.spin { x = 0.7, y = 1.0 })
```