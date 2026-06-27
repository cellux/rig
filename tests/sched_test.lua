local test = require("test")
local sched = require("sched")

test.case("sched.Scheduler constructs scheduler instances", function()
   local scheduler = sched.Scheduler("test scheduler")

   test.truthy(sched.Scheduler:is_instance(scheduler))
   test.equal(scheduler._label, "test scheduler")
end)

test.case("scheduler:start_async rejects task-shaped tables", function()
   local scheduler = sched.Scheduler("task validation scheduler")
   local imposter = {
      co = coroutine.create(function() end),
      _state = "ready",
      _waiters = {},
   }

   local ok, err = pcall(function()
      scheduler:start_async(imposter)
   end)

   test.falsey(ok)
   test.match(err, "scheduler:start_async expects a scheduler task")
end)

test.case("scheduler:start_async rejects tasks from another scheduler", function()
   local scheduler_a = sched.Scheduler("scheduler a")
   local scheduler_b = sched.Scheduler("scheduler b")

   scheduler_a:activate()
   local task = sched.spawn(function()
      sched.park()
   end)
   scheduler_a:drain()
   scheduler_a:deactivate()

   local ok, err = pcall(function()
      scheduler_b:start_async(task)
   end)

   test.falsey(ok)
   test.match(err, "scheduler:start_async expects a task owned by the scheduler")
end)

test.case("scheduler:wake_task rejects tasks from another scheduler", function()
   local scheduler_a = sched.Scheduler("scheduler a")
   local scheduler_b = sched.Scheduler("scheduler b")

   scheduler_a:activate()
   local task = sched.spawn(function()
      sched.park()
   end)
   scheduler_a:drain()
   scheduler_a:deactivate()

   local ok, err = pcall(function()
      scheduler_b:wake_task(task)
   end)

   test.falsey(ok)
   test.match(err, "scheduler:wake_task expects a task owned by the scheduler")
end)

test.case("scheduler:wake_task rejects tasks that are not suspended", function()
   local scheduler = sched.Scheduler("wake state scheduler")

   scheduler:activate()
   local task = sched.spawn(function()
      sched.park()
   end)

   local ok, err = pcall(function()
      scheduler:wake_task(task)
   end)
   scheduler:deactivate()

   test.falsey(ok)
   test.match(err, "cannot make scheduler task ready from state 'ready'")
end)

test.case("sched.yield resumes on the next scheduler drain", function()
   local scheduler = sched.Scheduler("yield scheduler")
   local events = {}
   local task_a
   local task_b

   scheduler:activate()

   task_a = sched.spawn(function()
      table.insert(events, "a1")
      sched.yield()
      table.insert(events, "a2")
   end)

   task_b = sched.spawn(function()
      table.insert(events, "b1")
   end)

   scheduler:drain()
   test.equal(#events, 2)
   test.equal(events[1], "a1")
   test.equal(events[2], "b1")
   test.falsey(task_a:is_done())
   test.truthy(task_b:is_done())

   scheduler:drain()
   scheduler:deactivate()

   test.equal(#events, 3)
   test.equal(events[3], "a2")
   test.truthy(task_a:is_done())
end)

test.case("sched.yield is not starved by completions on the next drain", function()
   local scheduler = sched.Scheduler("yield starvation scheduler")
   local events = {}
   local yielded_task
   local parked_task

   scheduler:activate()

   yielded_task = sched.spawn(function()
      table.insert(events, "yield before")
      sched.yield()
      table.insert(events, "yield after")
   end)

   parked_task = sched.spawn(function()
      table.insert(events, "park before")
      sched.park()
      table.insert(events, "park after")
   end)

   scheduler:drain()
   scheduler:wake_task(parked_task)
   scheduler:drain()
   scheduler:deactivate()

   test.equal(#events, 4)
   test.equal(events[1], "yield before")
   test.equal(events[2], "park before")
   test.equal(events[3], "park after")
   test.equal(events[4], "yield after")
   test.truthy(yielded_task:is_done())
   test.truthy(parked_task:is_done())
end)

test.case("sched.sleep can be implemented with deadline wakeups", function()
   local scheduler = sched.Scheduler("sleep test scheduler")
   local events = {}

   scheduler:set_handler("sched.sleep", function(local_scheduler, task, seconds)
      local_scheduler:sleep_until(task, seconds)
   end)

   scheduler:activate()
   sched.spawn(function()
      table.insert(events, "before")
      sched.sleep(2.0)
      table.insert(events, "after")
   end)

   scheduler:drain()
   test.equal(#events, 1)
   test.equal(events[1], "before")

   scheduler:wake_due_sleepers(1.0)
   scheduler:drain()
   test.equal(#events, 1)

   scheduler:wake_due_sleepers(2.0)
   scheduler:drain()
   scheduler:deactivate()

   test.equal(#events, 2)
   test.equal(events[2], "after")
end)

test.case("async tickets wake tasks and balance pending async state", function()
   local scheduler = sched.Scheduler("async ticket wake scheduler")
   local events = {}

   scheduler:set_handler("sched_test.async_ticket_wake", function(local_scheduler, task, payload)
      local ticket = local_scheduler:start_async(task)
      table.insert(events, { "handler", payload, ticket:is_done() })
      test.equal(local_scheduler:pending_async(), 1)
      ticket:wake("ok", payload + 1)
      test.truthy(ticket:is_done())
      test.equal(local_scheduler:pending_async(), 0)
   end)

   scheduler:activate()
   sched.spawn(function()
      table.insert(events, "before")
      local status, value = sched.await("sched_test.async_ticket_wake", 41)
      table.insert(events, { "after", status, value })
   end)
   scheduler:drain()
   scheduler:deactivate()

   test.equal(#events, 3)
   test.equal(events[1], "before")
   test.equal(events[2][1], "handler")
   test.equal(events[2][2], 41)
   test.falsey(events[2][3])
   test.equal(events[3][1], "after")
   test.equal(events[3][2], "ok")
   test.equal(events[3][3], 42)
end)

test.case("async tickets surface failures and complete tasks", function()
   local scheduler = sched.Scheduler("async ticket failure scheduler")
   local task

   scheduler:set_handler("sched_test.async_ticket_fail", function(local_scheduler, current_task)
      local ticket = local_scheduler:start_async(current_task)
      ticket:fail("async ticket failed")
   end)

   scheduler:activate()
   task = sched.spawn(function()
      sched.await("sched_test.async_ticket_fail")
   end)

   local ok, err = pcall(function()
      scheduler:drain()
   end)
   scheduler:deactivate()

   test.falsey(ok)
   test.match(err, "async ticket failed")
   test.truthy(task:is_done())
   test.equal(scheduler:pending_async(), 0)
   test.equal(scheduler:has_active_tasks(), false)
end)

test.case("async tickets reject double completion", function()
   local scheduler = sched.Scheduler("async ticket double completion scheduler")
   local task

   scheduler:set_handler("sched_test.async_ticket_double_complete", function(local_scheduler, current_task)
      local ticket = local_scheduler:start_async(current_task)
      ticket:wake("ok")
      ticket:wake("again")
   end)

   scheduler:activate()
   task = sched.spawn(function()
      sched.await("sched_test.async_ticket_double_complete")
   end)

   local ok, err = pcall(function()
      scheduler:drain()
   end)
   scheduler:deactivate()

   test.falsey(ok)
   test.match(err, "async ticket already completed")
   test.truthy(task:is_done())
   test.equal(scheduler:pending_async(), 0)
   test.equal(scheduler:has_active_tasks(), false)
end)

test.case("sched.sleep reports missing runtime support", function()
   local scheduler = sched.Scheduler("sleep missing handler scheduler")
   local task

   scheduler:activate()
   task = sched.spawn(function()
      sched.sleep(0.1)
   end)

   local ok, err = pcall(function()
      scheduler:drain()
   end)
   scheduler:deactivate()

   test.falsey(ok)
   test.match(err, "no scheduler handler is registered for 'sched%.sleep'")
   test.truthy(task:is_done())
   test.equal(scheduler:has_active_tasks(), false)
end)

test.case("register_handler registers fresh kinds", function()
   local observed = nil

   sched.register_handler("sched_test.auto_registered", function(scheduler, task, payload)
      observed = payload
      scheduler:wake_task(task, "ok")
   end)

   local scheduler = sched.Scheduler("auto-registered handler scheduler")
   local result = nil

   scheduler:activate()
   sched.spawn(function()
      result = sched.await("sched_test.auto_registered", 42)
   end)
   scheduler:drain()
   scheduler:deactivate()

   test.equal(observed, 42)
   test.equal(result, "ok")
end)

test.case("sched.join resumes when a parked task is woken", function()
   local scheduler = sched.Scheduler("join wake scheduler")
   local events = {}

   scheduler:activate()

   local parked_task = sched.spawn(function()
      table.insert(events, "parked before")
      local a, b, c = sched.park()
      table.insert(events, { "parked after", a, b, c })
   end)

   local join_task = sched.spawn(function()
      table.insert(events, "join before")
      local ok = sched.join { parked_task }
      table.insert(events, { "join after", ok })
   end)

   scheduler:drain()
   test.equal(events[1], "parked before")
   test.equal(events[2], "join before")

   scheduler:wake_task(parked_task, "x", nil, "z")
   scheduler:drain()
   scheduler:deactivate()

   test.equal(#events, 4)
   test.equal(events[3][1], "parked after")
   test.equal(events[3][2], "x")
   test.equal(events[3][3], nil)
   test.equal(events[3][4], "z")
   test.equal(events[4][1], "join after")
   test.equal(events[4][2], true)
   test.truthy(join_task:is_done())
end)

test.case("sched.join rejects tasks from another scheduler", function()
   local scheduler_a = sched.Scheduler("join scheduler a")
   local scheduler_b = sched.Scheduler("join scheduler b")
   local task

   scheduler_a:activate()
   task = sched.spawn(function()
      sched.park()
   end)
   scheduler_a:drain()
   scheduler_a:deactivate()

   scheduler_b:activate()
   sched.spawn(function()
      sched.join { task }
   end)

   local ok, err = pcall(function()
      scheduler_b:drain()
   end)
   scheduler_b:deactivate()

   test.falsey(ok)
   test.match(
      err,
      "sched.join expects tasks%[1%] to belong to the active scheduler"
   )
end)

test.case("sched.join returns immediately for already completed tasks", function()
   local scheduler = sched.Scheduler("join immediate scheduler")
   local events = {}

   scheduler:activate()

   local task = sched.spawn(function()
      table.insert(events, "task ran")
   end)

   scheduler:drain()

   local join_task = sched.spawn(function()
      table.insert(events, "join before")
      local ok = sched.join { task }
      table.insert(events, { "join after", ok })
   end)

   scheduler:drain()
   scheduler:deactivate()

   test.equal(#events, 3)
   test.equal(events[1], "task ran")
   test.equal(events[2], "join before")
   test.equal(events[3][1], "join after")
   test.equal(events[3][2], true)
   test.truthy(task:is_done())
   test.truthy(join_task:is_done())
end)

test.case("scheduler surfaces missing handler errors and still completes the task", function()
   local scheduler = sched.Scheduler("missing handler scheduler")
   local task

   scheduler:activate()
   task = sched.spawn(function()
      sched.await("missing.handler")
   end)

   local ok, err = pcall(function()
      scheduler:drain()
   end)
   scheduler:deactivate()

   test.falsey(ok)
   test.match(
      err,
      "no scheduler handler is registered for 'missing%.handler'"
   )
   test.truthy(task:is_done())
   test.equal(scheduler:has_active_tasks(), false)
end)

test.case("scheduler surfaces handler errors and completes the task", function()
   local scheduler = sched.Scheduler("handler error scheduler")
   local task

   scheduler:set_handler("custom.fail", function()
      rig.raise("handler failed")
   end)

   scheduler:activate()
   task = sched.spawn(function()
      sched.await("custom.fail")
   end)

   local ok, err = pcall(function()
      scheduler:drain()
   end)
   scheduler:deactivate()

   test.falsey(ok)
   test.match(err, "handler failed")
   test.truthy(task:is_done())
   test.equal(scheduler:has_active_tasks(), false)
end)

test.case("scheduler rejects non-request yields and completes the task", function()
   local scheduler = sched.Scheduler("non-request scheduler")
   local task

   scheduler:activate()
   task = sched.spawn(function()
      coroutine.yield("not a request")
   end)

   local ok, err = pcall(function()
      scheduler:drain()
   end)
   scheduler:deactivate()

   test.falsey(ok)
   test.match(err, "scheduler task yielded a non%-request value")
   test.truthy(task:is_done())
   test.equal(scheduler:has_active_tasks(), false)
end)

test.case("scheduler reports coroutine errors and completes the task", function()
   local scheduler = sched.Scheduler("coroutine error scheduler")
   local task

   scheduler:activate()
   task = sched.spawn(function()
      rig.raise("task exploded")
   end)

   local ok, err = pcall(function()
      scheduler:drain()
   end)
   scheduler:deactivate()

   test.falsey(ok)
   test.match(err, "task exploded")
   test.truthy(task:is_done())
   test.equal(scheduler:has_active_tasks(), false)
end)
