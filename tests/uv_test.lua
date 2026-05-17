local test = require("test")
local uv = require("uv")

test.case("uv scandir can see the tests directory", function()
   local entries, err = uv.scandir("tests")
   assert(entries ~= nil, err)

   local seen = {}
   for i = 1, #entries do
      seen[entries[i].name] = entries[i].type
   end

   test.equal(seen["uv_test.lua"], uv.DIRENT_FILE)
end)

test.case("uv clock helpers return numbers", function()
   local now = uv.now()
   local monotonic = uv.monotonic()

   test.equal(type(now), "number")
   test.equal(type(monotonic), "number")
   test.truthy(now > 0)
   test.truthy(monotonic > 0)
end)
