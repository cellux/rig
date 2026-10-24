# `sched`

Generic coroutine scheduler primitives for runtime-owned async backends.

## API

- `sched.register_handler(kind, handler)`
  - Registers a handler for a yielded operation kind.
  - Handlers receive `(scheduler, task, payload)`.
  - Handlers that start external async work may use `scheduler:start_async(task)` to create a one-shot completion ticket.
- `sched.Scheduler(label?)`
  - Creates a scheduler instance.
- `sched.active_scheduler()`
  - Returns the currently active scheduler, or `nil` when no scheduler is active.
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
- `sched.block(fn)`
  - Runs `fn` to completion on the active scheduler and returns its result, from a
    synchronous context (a pre-loop hook, a tool) that is not itself a coroutine.
  - Advances timers and pumps pending I/O between steps; requires a scheduler with a
    runtime blocking driver (the `runtime.Scheduler` behind `sched.active_scheduler`).
  - Must not be called from a scheduler-managed coroutine.

## Notes

- `sched` is intentionally generic.
- Backend modules such as `uv` should register handlers and keep their callback/event-loop details internal.
- `scheduler:start_async(task)` returns a ticket with `:wake(...)`, `:fail(err)`,
  `:cancel()`, and `:is_done()` helpers for balancing pending async work.
  - `:cancel()` completes the ticket without waking its task; a later `:wake()`/`:fail()`
    is then a no-op. Used at shutdown so late backend callbacks do not touch dead tasks.
  - A second `:wake()`/`:fail()` on a non-cancelled ticket is still an error.
- `scheduler:cancel_async()` completes every outstanding ticket (see above).
- User code should usually not construct raw yieldables directly when a higher-level backend API already exists.
- `sched.yield()` is for cooperative next-tick rescheduling.
- `sched.sleep()` is for runtime-provided timed suspension.
- `sched.park()` is for indefinite suspension until some other code resumes the task.
