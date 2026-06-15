# scenegraph

`scenegraph` provides a small scene-graph base class for examples and applications.

## Exports

- `scenegraph.Object`
  - `add_child(child)`
  - `own(resource, release_fn)`
  - `replace_owned(key, resource, release_fn)`
  - `create_owned_scope(label?)`
  - `set_animator(animator)`
  - `activate_tree(context?)`
  - `update_tree(dt)`
  - `draw_tree(context)`
  - `spawn_drive_tasks(tasks)`
  - `release_tree()`

Concrete scene nodes typically subclass `scenegraph.Object` and provide any of:

- `activate(context?)`
- `draw(context)`
- `update(dt)`
- `drive()`
- `release()`

Owned-resource scopes are created lazily on first use through `own(...)` / `replace_owned(...)`.
During `activate_tree(...)`, the object's own `activate(...)` method runs before its children.
During `release_tree()`, child nodes are released first, then the node's own `release()` method runs, and finally any lazily owned resources are released.
