# scenegraph

`scenegraph` provides a small scene-graph base class for examples and applications.

## Exports

- `scenegraph.Object`
  - `add_child(child)`
  - `set_animator(animator)`
  - `update_tree(dt)`
  - `draw_tree(context)`
  - `spawn_drive_tasks(tasks)`
  - `release_tree()`

Concrete scene nodes typically subclass `scenegraph.Object` and provide any of:

- `draw(context)`
- `update(dt)`
- `drive()`
- `release()`
