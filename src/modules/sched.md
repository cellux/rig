# `sched`

Generic coroutine scheduler primitives for runtime-owned async backends.

## API

- `sched.register_handler(kind, handler)`
  - Registers a handler for a yielded operation kind.
  - Handlers receive `(scheduler, task, payload)`.
- `sched.create(label?)`
  - Creates a scheduler instance.
- `sched.build_request(kind, payload)`
  - Creates a generic scheduler request object.
- `sched.await(kind, payload)`
  - Yields a scheduler-managed operation from the current task.
  - Must be called from a scheduler-managed coroutine.
- `sched.yield()`
  - Suspends the current scheduler-managed coroutine and reschedules it for the next scheduler drain.
- `sched.sleep(seconds)`
  - Suspends the current scheduler-managed coroutine for at least the requested number of seconds.
  - Requires the active runtime to provide a sleep backend.
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
- `sched.yield()` is for cooperative next-tick rescheduling.
- `sched.sleep()` is for runtime-provided timed suspension.
- `sched.park()` is for indefinite suspension until some other code resumes the task.
