local test = require("test")
local uv = require("uv")
local repr = require("repr")
local schema = require("schema")

test.case("rig globals are available", function()
   test.equal(type(rig), "table")
   test.equal(type(rig.argv), "table")
   test.equal(type(rig.set), "function")
   test.equal(type(rig.argv[0]), "string")
   test.truthy(rig.argv[0] ~= "")
   test.match(rig.argv[0], "rig$")
   test.match(rig.argv[1], "tests/rig_test%.lua$")
end)

test.case("luajit standard libraries are available and ffi stays require-only", function()
   test.equal(type(assert), "function")
   test.equal(type(bit), "table")
   test.equal(type(coroutine), "table")
   test.equal(type(debug), "table")
   test.equal(type(io), "table")
   test.equal(type(jit), "table")
   test.equal(type(math), "table")
   test.equal(type(os), "table")
   test.equal(type(package), "table")
   test.equal(type(string), "table")
   test.equal(type(table), "table")

   test.equal(ffi, nil)

   local ffi_module = require("ffi")
   test.equal(type(ffi_module), "table")
   test.equal(type(ffi_module.new), "function")
end)

test.case("arg matches luajit startup layout", function()
   test.equal(type(arg), "table")
   test.equal(arg[-1], rig.argv[0])
   test.match(arg[0], "tests/rig_test%.lua$")
   test.equal(arg[1], nil)
   test.equal(type(rig.argv), "table")
   test.equal(type(rig.argv[0]), "string")
   test.match(rig.argv[1], "tests/rig_test%.lua$")
   test.equal(rig.argv[2], nil)

   local script_path = os.tmpname()
   local script_file = assert(io.open(script_path, "w"))
   script_file:write([[
print("arg[-1]=" .. tostring(arg[-1]))
print("arg[0]=" .. tostring(arg[0]))
print("arg[1]=" .. tostring(arg[1]))
print("arg[2]=" .. tostring(arg[2]))
print("rig.argv[0]=" .. tostring(rig.argv[0]))
print("rig.argv[1]=" .. tostring(rig.argv[1]))
print("rig.argv[2]=" .. tostring(rig.argv[2]))
print("rig.argv[3]=" .. tostring(rig.argv[3]))
]])
   script_file:close()

   local result = uv.spawn {
      file = rig.argv[0],
      args = {
         rig.argv[0],
         script_path,
         "alpha",
         "beta",
      },
   }

   os.remove(script_path)

   test.truthy(result.success, result.stderr)
   test.contains_line(result.stdout, "arg[-1]=" .. rig.argv[0])
   test.contains_line(result.stdout, "arg[0]=" .. script_path)
   test.contains_line(result.stdout, "arg[1]=alpha")
   test.contains_line(result.stdout, "arg[2]=beta")
   test.contains_line(result.stdout, "rig.argv[0]=" .. rig.argv[0])
   test.contains_line(result.stdout, "rig.argv[1]=" .. script_path)
   test.contains_line(result.stdout, "rig.argv[2]=alpha")
   test.contains_line(result.stdout, "rig.argv[3]=beta")
end)

test.case("rig.printf formats through string.format and prints without newline", function()
   local script_path = os.tmpname()
   local script_file = assert(io.open(script_path, "w"))
   script_file:write([[
rig.printf("%s=%d", "alpha", 42)
rig.println(" done")
]])
   script_file:close()

   local result = uv.spawn {
      file = rig.argv[0],
      args = {
         rig.argv[0],
         script_path,
      },
   }

   os.remove(script_path)

   test.truthy(result.success, result.stderr)
   test.contains_line(result.stdout, "alpha=42 done")
end)

test.case("rig.fprint variants target the requested stream", function()
   local script_path = os.tmpname()
   local script_file = assert(io.open(script_path, "w"))
   script_file:write([[
rig.fprint(io.stdout, "out:")
rig.fprintf(io.stdout, "%02d", 7)
rig.fprintln(io.stdout, " done")
rig.fprint(io.stderr, "err:")
rig.fprintf(io.stderr, "%02d", 9)
rig.fprintln(io.stderr, " done")
]])
   script_file:close()

   local result = uv.spawn {
      file = rig.argv[0],
      args = {
         rig.argv[0],
         script_path,
      },
   }

   os.remove(script_path)

   test.truthy(result.success, result.stderr)
   test.contains_line(result.stdout, "out:07 done")
   test.contains_line(result.stderr, "err:09 done")
end)

test.case("rig.eprint variants target stderr", function()
   local script_path = os.tmpname()
   local script_file = assert(io.open(script_path, "w"))
   script_file:write([[
rig.eprint("err:")
rig.eprintf("%02d", 11)
rig.eprintln(" done")
]])
   script_file:close()

   local result = uv.spawn {
      file = rig.argv[0],
      args = {
         rig.argv[0],
         script_path,
      },
   }

   os.remove(script_path)

   test.truthy(result.success, result.stderr)
   test.equal(result.stdout, "")
   test.contains_line(result.stderr, "err:11 done")
end)

test.case("repr module entrypoints agree", function()
   test.equal(repr({
      a = 1,
   }), '{a = 1}')
   test.equal(repr.repr({ a = 1 }), rig.repr({ a = 1 }))
end)

test.case("rig.tostring keeps non-table values unquoted", function()
   test.equal(rig.tostring("hello"), "hello")
   test.equal(rig.tostring({
      a = 1,
   }), "{a = 1}")
end)

test.case("rig.tostring respects __tostring on tables", function()
   local value = setmetatable({}, {
      __tostring = function()
         return "custom table"
      end,
   })

   test.equal(rig.tostring(value), "custom table")
end)

test.case("rig.shallow_copy returns non-tables unchanged and clones tables", function()
   test.equal(rig.shallow_copy(nil), nil)
   test.equal(rig.shallow_copy(42), 42)
   test.equal(rig.shallow_copy("hello"), "hello")

   local nested = {
      flag = true,
   }
   local original = {
      count = 3,
      nested = nested,
   }
   local copy = rig.shallow_copy(original)

   test.truthy(copy ~= original)
   test.equal(copy.count, 3)
   test.equal(copy.nested, nested)

   copy.count = 9
   test.equal(original.count, 3)
end)

test.case("rig.create_ffi_library_loader caches success and failure", function()
   local ffi_module = require("ffi")
   local old_load = ffi_module.load

   local ok, err = pcall(function()
      local success_calls = {}
      local fake_library = {
         marker = "ok",
      }

      ffi_module.load = function(name)
         table.insert(success_calls, name)
         if name == "rig-test-good" then
            return fake_library
         end
         error("missing " .. name)
      end

      local load_success = rig.create_ffi_library_loader({
         label = "rig-test-success",
         candidates = {
            "rig-test-missing",
            "rig-test-good",
            "rig-test-never-reached",
         },
      })

      test.equal(load_success(), fake_library)
      test.equal(load_success(), fake_library)
      test.equal(#success_calls, 2)
      test.equal(success_calls[1], "rig-test-missing")
      test.equal(success_calls[2], "rig-test-good")

      local failure_calls = {}
      ffi_module.load = function(name)
         table.insert(failure_calls, name)
         error("missing " .. name)
      end

      local load_failure = rig.create_ffi_library_loader({
         label = "rig-test-failure",
         candidates = {
            "rig-test-bad-a",
            "rig-test-bad-b",
         },
      })

      local failure_ok_1, failure_err_1 = pcall(load_failure)
      test.falsey(failure_ok_1)
      test.match(tostring(failure_err_1), "failed to load rig%-test%-failure library:")

      local failure_ok_2, failure_err_2 = pcall(load_failure)
      test.falsey(failure_ok_2)
      test.match(tostring(failure_err_2), "failed to load rig%-test%-failure library:")
      test.equal(#failure_calls, 2)
      test.equal(failure_calls[1], "rig-test-bad-a")
      test.equal(failure_calls[2], "rig-test-bad-b")
   end)

   ffi_module.load = old_load
   if not ok then
      error(err)
   end
end)

test.case("resource scope releases in the expected order", function()
   local scope = rig.ResourceScope({}, "test scope")
   local released = {}

   test.equal(getmetatable(scope), rig.ResourceScope)

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

test.case("rig.ResourceScope constructs scope instances", function()
   local direct = rig.ResourceScope({}, "direct scope")
   test.equal(getmetatable(direct), rig.ResourceScope)
   test.equal(direct._scope_label, "direct scope")
end)

