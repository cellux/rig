local test = require("test")
local uv = require("uv")

test.case("rig globals are available", function()
   test.equal(type(rig), "table")
   test.equal(type(rig.executable_path), "string")
   test.truthy(rig.executable_path ~= "")
   test.match(rig.executable_path, "rig$")
end)

test.case("resource scope releases in the expected order", function()
   local scope = rig.resource_scope({}, "test scope")
   local released = {}

   scope:adopt("alpha", function(context, resource)
      assert(context ~= nil)
      table.insert(released, resource)
   end)

   scope:replace("slot", "first", function(_, resource)
      table.insert(released, resource)
   end)
   scope:replace("slot", "second", function(_, resource)
      table.insert(released, resource)
   end)
   scope:release()

   test.equal(#released, 3)
   test.equal(released[1], "first")
   test.equal(released[2], "second")
   test.equal(released[3], "alpha")
end)

test.case("uv scandir can see the tests directory", function()
   local entries, err = uv.scandir("tests")
   assert(entries ~= nil, err)

   local seen = {}
   for i = 1, #entries do
      seen[entries[i].name] = entries[i].type
   end

   test.equal(seen["rig_basics_test.lua"], uv.DIRENT_FILE)
end)

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
      files = { "tests/fennel_basics_test.fnl" },
      jobs = 1,
   }

   test.equal(summary.total, 1)
   test.equal(summary.passed, 1)
   test.truthy(summary.duration_ns >= 0)
   test.truthy(summary.duration_ms >= 0)
   test.truthy(summary.files[1].duration_ns >= 0)
   test.truthy(summary.files[1].duration_ms >= 0)
   test.match(
      summary.files[1].stdout,
      "PASS scheduler can run a spawned task %([^)]+%)"
   )
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
