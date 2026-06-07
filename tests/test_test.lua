local test = require("test")

local fixture_setup_count = 0
local fixture_teardown_count = 0
local with_counter_fixture = test.fixture(
   function()
      fixture_setup_count = fixture_setup_count + 1
      return { value = 41 }
   end,
   function(resource)
      fixture_teardown_count = fixture_teardown_count + 1
      test.equal(resource.value, 42)
   end
)

test.case("fixture wraps setup and teardown", with_counter_fixture(function(resource)
   test.equal(resource.value, 41)
   resource.value = 42
end))

test.case("test.run discovers the repo test files", function()
   local summary = test.run {
      files = { "tests/fennel_test.fnl" },
      jobs = 1,
   }

   test.equal(summary.total, 1)
   test.equal(summary.passed, 1)
   test.truthy(summary.duration >= 0)
   test.truthy(summary.files[1].duration >= 0)
   test.equal(summary.files[1].passed_cases, 2)
   test.equal(summary.files[1].total_cases, 2)
   test.contains_line(summary.files[1].stdout, "TAP version 13")
   test.contains_line(summary.files[1].stdout, "1..2")
   test.match(
      summary.files[1].stdout,
      "ok 2 %- scheduler can run a spawned task %([^)]+%)"
   )
end)

test.case("test.run validates roots jobs and files through schema", function()
   local bad_roots_ok, bad_roots_err = pcall(function()
      test.run {
         roots = { "" },
         files = {},
      }
   end)
   test.falsey(bad_roots_ok)
   test.match(tostring(bad_roots_err), "test.run roots%[1%] expects a non%-empty string")

   local bad_jobs_ok, bad_jobs_err = pcall(function()
      test.run {
         files = {},
         jobs = 0,
      }
   end)
   test.falsey(bad_jobs_ok)
   test.match(tostring(bad_jobs_err), "test.run jobs expects a number >= 1")

   local bad_files_ok, bad_files_err = pcall(function()
      test.run {
         files = { "" },
      }
   end)
   test.falsey(bad_files_ok)
   test.match(tostring(bad_files_err), "test.run files%[1%] expects a non%-empty string")
end)

test.case("contains_line matches complete lines", function()
   local text = "alpha\nbeta\ngamma\n"
   test.contains_line(text, "beta")
end)

local serial_counter = 0

test.serial("serial case runs first in serial sequence", function()
   serial_counter = serial_counter + 1
   test.equal(serial_counter, 1)
end)

test.serial("serial case preserves declaration order", function()
   serial_counter = serial_counter + 1
   test.equal(serial_counter, 2)
end)

test.serial("fixture setup and teardown ran once", function()
   test.equal(fixture_setup_count, 1)
   test.equal(fixture_teardown_count, 1)
end)
