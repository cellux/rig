local test = require("test")
local sched = require("sched")

test.case("sched.yield resumes on the next scheduler drain", function()
   local events = {}

   local task_a = sched.spawn(function()
      table.insert(events, "a1")
      sched.yield()
      table.insert(events, "a2")
   end)

   local task_b = sched.spawn(function()
      table.insert(events, "b1")
   end)

   sched.join { task_a, task_b }

   test.equal(#events, 3)
   test.equal(events[1], "a1")
   test.equal(events[2], "b1")
   test.equal(events[3], "a2")
end)
