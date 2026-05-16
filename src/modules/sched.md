# `sched`

Generic coroutine scheduler primitives for runtime-owned async backends.

## API

- `sched.register_handler(kind, handler)`
  - Registers a handler for a yielded operation kind.
  - Handlers receive `(scheduler, task, payload)`.
- `sched.create(label?)`
  - Creates a scheduler instance.
- `sched.yieldable(kind, payload)`
  - Creates a generic yieldable object.
- `sched.await(kind, payload)`
  - Yields a scheduler-managed operation from the current task.
  - Must be called from a scheduler-managed coroutine.
- `sched.park()`
  - Suspends the current scheduler-managed coroutine until something else resumes it later.
- `sched.spawn(fn, ...)`
  - Schedules a new coroutine task on the active scheduler.
  - Requires an active scheduler.
- `sched.join(tasks)`
  - Suspends the current scheduler-managed coroutine until all listed tasks have finished.

## Notes

- `sched` is intentionally generic.
- Backend modules such as `uv` should register handlers and keep their callback/event-loop details internal.
- User code should usually not construct raw yieldables directly when a higher-level backend API already exists.
