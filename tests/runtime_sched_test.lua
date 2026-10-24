local test = require("test")
local sched = require("sched")
local runtime = require("runtime")
local rig = require("rig")

local function compile_scheduler_runtime(execute)
   local core = runtime.scheduler_plugin()
   local clock = runtime.ManualClock()
   local timer = runtime.Timer()
   local compiled = rig.runtime()
      :use(core)
      :add(runtime.clock_component(core, {
         name = "clock",
         clock = clock,
      }))
      :add(runtime.timer_component(core, {
         name = "timer",
         timer = timer,
      }))
      :add(runtime.scheduler_component(core, {
         name = "scheduler",
      }))
      :execute(execute)
      :compile()
   return compiled, clock, timer
end

test.case("scheduler runs function execution as a coroutine", function()
   local steps = 0
   local compiled = compile_scheduler_runtime(function(ctx)
      steps = steps + 1
      ctx.scheduler:yield()
      steps = steps + 1
   end)

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.equal(steps, 2)
end)

test.case("scheduler sleep resumes at the timer deadline", function()
   local before = nil
   local after = nil
   local compiled = compile_scheduler_runtime(function(ctx)
      before = ctx.scheduler:monotonic()
      ctx.scheduler:sleep(2.5)
      after = ctx.scheduler:monotonic()
   end)

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.equal(before, 0)
   test.equal(after, 2.5)
end)

test.case("scheduler join waits for spawned tasks", function()
   local order = {}
   local compiled = compile_scheduler_runtime(function(ctx)
      local scheduler = ctx.scheduler
      local first = scheduler:spawn(function()
         scheduler:sleep(1)
         order[#order + 1] = "first"
      end)
      local second = scheduler:spawn(function()
         scheduler:sleep(2)
         order[#order + 1] = "second"
      end)

      scheduler:join({ first, second })
      order[#order + 1] = "joined"
   end)

   compiled:start()

   test.equal(order[1], "first")
   test.equal(order[2], "second")
   test.equal(order[3], "joined")
end)

test.case("background tasks are cancelled with a chance to clean up", function()
   local cleaned = false
   local compiled = compile_scheduler_runtime(function(ctx)
      local scheduler = ctx.scheduler
      scheduler:spawn_background(function()
         local reason = scheduler:park()
         if reason == runtime.CANCELLED then
            cleaned = true
         end
      end)
      scheduler:yield()
   end)

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.truthy(cleaned)
end)

test.case("background tasks do not keep the runtime alive", function()
   local ran = false
   local compiled = compile_scheduler_runtime(function(ctx)
      ctx.scheduler:spawn_background(function()
         local reason = ctx.scheduler:park()
         if reason ~= runtime.CANCELLED then
            ran = true
         end
      end)
   end)

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.falsey(ran)
end)

test.case("scheduler detects a foreground deadlock", function()
   local compiled = compile_scheduler_runtime(function(ctx)
      ctx.scheduler:park()
   end)

   local ok, err = pcall(function()
      compiled:start()
   end)

   test.falsey(ok)
   test.match(tostring(err), "deadlocked")
   test.equal(compiled.state, "failed")
end)

test.case("scheduler task failure fails the runtime", function()
   local compiled = compile_scheduler_runtime(function(ctx)
      ctx.scheduler:spawn(function()
         rig.raise("task boom")
      end)
      ctx.scheduler:yield()
   end)

   local ok, err = pcall(function()
      compiled:start()
   end)

   test.falsey(ok)
   test.match(tostring(err), "task boom")
   test.equal(compiled.state, "failed")
end)

test.case("scheduler requires a compatible timer", function()
   local core = runtime.scheduler_plugin()
   local clock = runtime.ManualClock()
   local timer = runtime.Timer()
   local incompatible = runtime.descriptor(core, {
      name = "timer",
      provides = {
         { capability = "sched.timer", properties = { protocol = "other" } },
      },
      create = function()
         return timer
      end,
   })

   local ok, err = pcall(function()
      rig.runtime()
         :use(core)
         :add(runtime.clock_component(core, {
            name = "clock",
            clock = clock,
         }))
         :add(incompatible)
         :add(runtime.scheduler_component(core, {
            name = "scheduler",
         }))
         :execute(function() end)
         :compile()
   end)

   test.falsey(ok)
   test.match(tostring(err), "no candidate matches its constraints")
end)

test.case("scheduler requires a clock and timer", function()
   local core = runtime.scheduler_plugin()

   local ok, err = pcall(function()
      rig.runtime()
         :use(core)
         :add(runtime.scheduler_component(core, {
            name = "scheduler",
         }))
         :execute(function() end)
         :compile()
   end)

   test.falsey(ok)
   test.match(
      tostring(err),
      "requires capability 'sched.clock' but no component provides it"
   )
end)

test.case("manual clock advances explicitly", function()
   local clock = runtime.ManualClock(5)
   local core = runtime.scheduler_plugin()

   local compiled = rig.runtime()
      :use(core)
      :add(runtime.clock_component(core, {
         clock = clock,
      }))
      :add(runtime.timer_component(core, {
         timer = runtime.Timer(),
      }))
      :add(runtime.scheduler_component(core, {
         name = "scheduler",
      }))
      :execute(function(ctx)
         ctx.scheduler:sleep(1)
      end)
      :compile()

   compiled:start()

   test.equal(clock:monotonic(), 6)
end)

test.case("a runtime scheduler blocks on a scheduler operation", function()
   local clock = runtime.ManualClock(0)
   local scheduler = runtime.Scheduler {
      clock = clock,
      timer = runtime.Timer(),
      label = "block test",
   }

   local result = scheduler:block(function()
      sched.sleep(0.25)
      return "done"
   end)

   test.equal(result, "done")
   test.truthy(clock:monotonic() >= 0.25)
end)

test.case("a runtime scheduler block surfaces task errors", function()
   local scheduler = runtime.Scheduler {
      clock = runtime.ManualClock(0),
      timer = runtime.Timer(),
      label = "block failure",
   }

   local ok, err = pcall(function()
      scheduler:block(function()
         rig.raise("block boom")
      end)
   end)

   test.falsey(ok)
   test.match(tostring(err), "block boom")
end)

test.case("sched.block rejects calls from a scheduler coroutine", function()
   local ok, err = pcall(function()
      sched.block(function() end)
   end)

   test.falsey(ok)
   test.match(tostring(err), "may not be called from a scheduler%-managed coroutine")
end)
