local test = require("test")
local sched = require("sched")

test.case("sched.yield resumes on the next scheduler drain", function()
   local scheduler = sched.create("yield scheduler")
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
   test.falsey(task_a._done)
   test.truthy(task_b._done)

   scheduler:drain()
   scheduler:deactivate()

   test.equal(#events, 3)
   test.equal(events[3], "a2")
   test.truthy(task_a._done)
end)

test.case("sched.yield is not starved by completions on the next drain", function()
   local scheduler = sched.create("yield starvation scheduler")
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
   scheduler:wake(parked_task)
   scheduler:drain()
   scheduler:deactivate()

   test.equal(#events, 4)
   test.equal(events[1], "yield before")
   test.equal(events[2], "park before")
   test.equal(events[3], "park after")
   test.equal(events[4], "yield after")
   test.truthy(yielded_task._done)
   test.truthy(parked_task._done)
end)

test.case("sched.sleep can be implemented with deadline wakeups", function()
   local scheduler = sched.create("sleep test scheduler")
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

test.case("sched.join resumes when a parked task is woken", function()
   local scheduler = sched.create("join wake scheduler")
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

   scheduler:wake(parked_task, "x", nil, "z")
   scheduler:drain()
   scheduler:deactivate()

   test.equal(#events, 4)
   test.equal(events[3][1], "parked after")
   test.equal(events[3][2], "x")
   test.equal(events[3][3], nil)
   test.equal(events[3][4], "z")
   test.equal(events[4][1], "join after")
   test.equal(events[4][2], true)
   test.truthy(join_task._done)
end)

test.case("sched.join returns immediately for already completed tasks", function()
   local scheduler = sched.create("join immediate scheduler")
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
   test.truthy(task._done)
   test.truthy(join_task._done)
end)

test.case("scheduler surfaces missing handler errors and still completes the task", function()
   local scheduler = sched.create("missing handler scheduler")
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
   test.truthy(task._done)
   test.equal(scheduler:has_live_tasks(), false)
end)

test.case("scheduler surfaces handler errors and completes the task", function()
   local scheduler = sched.create("handler error scheduler")
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
   test.truthy(task._done)
   test.equal(scheduler:has_live_tasks(), false)
end)

test.case("scheduler rejects non-request yields and completes the task", function()
   local scheduler = sched.create("non-request scheduler")
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
   test.truthy(task._done)
   test.equal(scheduler:has_live_tasks(), false)
end)

test.case("scheduler reports coroutine errors and completes the task", function()
   local scheduler = sched.create("coroutine error scheduler")
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
   test.truthy(task._done)
   test.equal(scheduler:has_live_tasks(), false)
end)
