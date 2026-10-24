local test = require("test")
local params = require("params")

test.case("params defines and clamps numeric values", function()
   local store = params.params {
      { name = "speed", value = 2.0, min = 0.0, max = 10.0, step = 0.5 },
   }

   test.equal(store:get("speed"), 2.0)
   test.equal(store:set("speed", 20.0), 10.0)
   test.equal(store:set("speed", -3.0), 0.0)

   test.equal(store:adjust("speed", 1), 0.5)
   test.equal(store:adjust("speed", -1), 0.0)
   test.equal(store:fraction("speed"), 0.0)

   store:set("speed", 5.0)
   test.equal(store:fraction("speed"), 0.5)
   test.equal(store:format("speed"), "5")
end)

test.case("params handles booleans and enums", function()
   local store = params.params {
      { name = "debug", kind = "boolean", value = false },
      { name = "mode", kind = "enum", values = { "solid", "wire", "points" } },
   }

   test.equal(store:get("debug"), false)
   test.equal(store:toggle("debug"), true)
   test.equal(store:fraction("debug"), 1.0)
   test.equal(store:format("debug"), "on")

   test.equal(store:get("mode"), 1)
   test.equal(store:adjust("mode", 1), 2)
   test.equal(store:adjust("mode", 1), 3)
   test.equal(store:adjust("mode", 1), 1)
   test.equal(store:adjust("mode", -1), 3)
   test.equal(store:format("mode"), "points")
   test.equal(store:fraction("mode"), 1.0)
end)

test.case("params exposes declaration order and iteration", function()
   local store = params.params {
      { name = "a" },
      { name = "b" },
      { name = "c" },
   }

   test.equal(store:count(), 3)
   test.equal(store:name_at(2), "b")

   local names = {}
   for name in store:each() do
      names[#names + 1] = name
   end
   test.equal(table.concat(names, ","), "a,b,c")
end)

test.case("params validates definitions", function()
   test.falsey(pcall(function()
      params.params { { name = "" } }
   end))
   test.falsey(pcall(function()
      params.params { { name = "x" }, { name = "x" } }
   end))
   test.falsey(pcall(function()
      params.params { { name = "x", kind = "enum", values = {} } }
   end))
   test.falsey(pcall(function()
      params.params { { name = "x", kind = "unknown" } }
   end))
   test.falsey(pcall(function()
      params.params { { name = "x", min = 5, max = 1 } }
   end))
end)
