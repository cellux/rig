# scenegraph

`scenegraph` provides a small scene-graph base class for examples and applications.

## Exports

- `scenegraph.Object`
  - `add_child(child)`
  - `own(resource, release_fn)`
  - `replace_owned(key, resource, release_fn)`
  - `create_owned_scope(label?)`
  - `set_resource_scope(scope)`
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
When a runtime resource scope is attached with `set_resource_scope(scope)` (the animator
app does this from `ctx.resources` before activating the tree), each object's lazy scope is
adopted into that runtime root and released by the runtime at teardown. New children added
after activation inherit the scope through `add_child(...)`.
During `activate_tree(...)`, the object's own `activate(...)` method runs before its children.
During `release_tree()`, child nodes are released first, then the node's own `release()` method runs.
When no runtime scope is attached, `release_tree()` also releases the object's lazily owned scope locally.
