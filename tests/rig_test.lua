local test = require("test")
local uv = require("uv")
local repr = require("repr")

test.case("rig globals are available", function()
   test.equal(type(rig), "table")
   test.equal(type(rig.argv), "table")
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

test.case("service registry validates providers and resolves by active providers", function()
   rig.create_service("rig_test_service", {
      "ping",
      "pong",
   })

   local duplicate_ok, duplicate_err = pcall(function()
      rig.create_service("rig_test_service", {
         "ping",
         "pong",
      })
   end)
   test.falsey(duplicate_ok)
   test.match(tostring(duplicate_err), "already has a service")

   local incomplete_ok, incomplete_err = pcall(function()
      rig.register_service_provider("rig_test_service", "rig_test_provider_incomplete", {
         ping = function()
            return "ping"
         end,
      })
   end)
   test.falsey(incomplete_ok)
   test.match(tostring(incomplete_err), "implement method 'pong'")

   rig.register_runtime_driver("rig_test_service_driver", {
      loop = function()
         local service = rig.require_service("rig_test_service")
         _G.rig_test_service_result = {
            ping = service.ping(),
            pong = service.pong(),
         }
      end,
   })

   rig.register_service_provider("rig_test_service", "rig_test_provider_alpha", {
      ping = function()
         return "ping ok"
      end,
      pong = function()
         return "pong ok"
      end,
   })

   rig.register_service_provider("rig_test_service", "rig_test_provider_beta", {
      ping = function()
         return "ping beta"
      end,
      pong = function()
         return "pong beta"
      end,
   })

   rig.register_runtime_preset("rig_test_service_preset", {
      driver = "rig_test_service_driver",
      providers = {
         rig_test_service = "rig_test_provider_alpha",
      },
   })

   local duplicate_preset_ok, duplicate_preset_err = pcall(function()
      rig.register_runtime_preset("rig_test_service_preset", {
         driver = "rig_test_service_driver",
      })
   end)
   test.falsey(duplicate_preset_ok)
   test.match(tostring(duplicate_preset_err), "already has a runtime preset")

   local extra_preset_field_ok, extra_preset_field_err = pcall(function()
      rig.register_runtime_preset("rig_test_service_preset_extra_field", {
         driver = "rig_test_service_driver",
         extra = true,
      })
   end)
   test.falsey(extra_preset_field_ok)
   test.match(
      tostring(extra_preset_field_err),
      "rig%.register_runtime_preset preset%.extra is not allowed"
   )

   local missing_driver_ok, missing_driver_err = pcall(function()
      rig.register_runtime_preset("rig_test_service_preset_missing_driver", {})
   end)
   test.falsey(missing_driver_ok)
   test.match(
      tostring(missing_driver_err),
      "rig%.register_runtime_preset preset%.driver expects a non%-empty string"
   )

   rig.run {
      mode = "rig_test_service_preset",
   }

   test.equal(rig_test_service_result.ping, "ping ok")
   test.equal(rig_test_service_result.pong, "pong ok")

   rig.run {
      mode = "rig_test_service_preset",
      providers = {
         rig_test_service = "rig_test_provider_beta",
      },
   }

   test.equal(rig_test_service_result.ping, "ping beta")
   test.equal(rig_test_service_result.pong, "pong beta")
end)

test.case("rig.run validates provider mappings before the driver starts", function()
   local started = false

   rig.register_runtime_driver("rig_test_validation_driver", {
      loop = function()
         started = true
      end,
   })

   local missing_provider_ok, missing_provider_err = pcall(function()
      rig.run {
         driver = "rig_test_validation_driver",
         providers = {
            rig_test_service = "rig_test_provider_missing",
         },
      }
   end)
   test.falsey(missing_provider_ok)
   test.falsey(started)
   test.match(tostring(missing_provider_err), "rig_test_provider_missing")
   test.match(tostring(missing_provider_err), "rig_test_service")

   local unknown_service_ok, unknown_service_err = pcall(function()
      rig.run {
         driver = "rig_test_validation_driver",
         providers = {
            rig_test_service_missing = "rig_test_provider_alpha",
         },
      }
   end)
   test.falsey(unknown_service_ok)
   test.falsey(started)
   test.match(tostring(unknown_service_err), "rig_test_service_missing")
   test.match(tostring(unknown_service_err), "unknown service")
end)

test.case("rig.run validates option shapes before resolving the runtime", function()
   local bad_mode_ok, bad_mode_err = pcall(function()
      rig.run {
         mode = "",
      }
   end)
   test.falsey(bad_mode_ok)
   test.match(tostring(bad_mode_err), "rig.run options%.mode expects a non%-empty string")

   local bad_driver_ok, bad_driver_err = pcall(function()
      rig.run {
         driver = false,
      }
   end)
   test.falsey(bad_driver_ok)
   test.match(tostring(bad_driver_err), "rig.run options%.driver expects a non%-empty string")

   local bad_provider_map_ok, bad_provider_map_err = pcall(function()
      rig.run {
         driver = "rig_test_validation_driver",
         providers = {
            [1] = "rig_test_provider_alpha",
         },
      }
   end)
   test.falsey(bad_provider_map_ok)
   test.match(tostring(bad_provider_map_err), "rig.run options%.providers key expects a non%-empty string")
end)

test.case("rig.run validates and executes declared hook phases", function()
   local observed = {}

   rig.register_runtime_driver("rig_test_hook_driver", {
      phases = {
         "before_tick",
         "after_tick",
      },
      loop = function(options, run_hooks)
         run_hooks("before_tick", options)
         run_hooks("after_tick", options)
      end,
   })

   rig.run {
      driver = "rig_test_hook_driver",
      hooks = {
         before_setup = function()
            table.insert(observed, "before_setup")
         end,
         before_tick = function()
            table.insert(observed, "before_tick")
         end,
         after_tick = function()
            table.insert(observed, "after_tick")
         end,
         after_shutdown = function()
            table.insert(observed, "after_shutdown")
         end,
      },
   }

   test.equal(#observed, 4)
   test.equal(observed[1], "before_setup")
   test.equal(observed[2], "before_tick")
   test.equal(observed[3], "after_tick")
   test.equal(observed[4], "after_shutdown")

   local unknown_phase_ok, unknown_phase_err = pcall(function()
      rig.run {
         driver = "rig_test_hook_driver",
         hooks = {
            before_frame = function() end,
         },
      }
   end)
   test.falsey(unknown_phase_ok)
   test.match(tostring(unknown_phase_err), "does not know hook phase")
   test.match(tostring(unknown_phase_err), "before_frame")
end)
