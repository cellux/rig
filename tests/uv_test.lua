local test = require("test")
local sched = require("sched")
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

test.case("sched.sleep waits under uv mode", function()
   local start = uv.monotonic()
   sched.sleep(0.01)
   local elapsed = uv.monotonic() - start

   test.truthy(elapsed >= 0.005)
end)

test.case("uv.spawn validates spec through schema before awaiting", function()
   local missing_file_ok, missing_file_err = pcall(function()
      uv.spawn({})
   end)
   test.falsey(missing_file_ok)
   test.match(tostring(missing_file_err), "uv%.spawn spec%.file expects a non%-empty string")

   local bad_args_ok, bad_args_err = pcall(function()
      uv.spawn {
         file = rig.argv[0],
         args = { rig.argv[0], 123 },
      }
   end)
   test.falsey(bad_args_ok)
   test.match(tostring(bad_args_err), "uv%.spawn spec%.args%[2%] expects a string")
end)
