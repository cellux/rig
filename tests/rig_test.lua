local test = require("test")

test.case("rig globals are available", function()
   test.equal(type(rig), "table")
   test.equal(type(rig.executable_path), "string")
   test.truthy(rig.executable_path ~= "")
   test.match(rig.executable_path, "rig$")
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

test.case("service registry validates implementations and resolves by active providers", function()
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
      rig.register_service_impl("rig_test_service", "rig_test_provider_incomplete", {
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

   rig.register_service_impl("rig_test_service", "rig_test_provider_alpha", {
      ping = function()
         return "ping ok"
      end,
      pong = function()
         return "pong ok"
      end,
   })

   rig.register_service_impl("rig_test_service", "rig_test_provider_beta", {
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

   rig.run {
      preset = "rig_test_service_preset",
   }

   test.equal(rig_test_service_result.ping, "ping ok")
   test.equal(rig_test_service_result.pong, "pong ok")

   rig.run {
      preset = "rig_test_service_preset",
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
