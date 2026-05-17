local test = require("test")

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

test.case("service registry validates implementations and resolves by active mode", function()
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
      rig.register_service_impl("rig_test_service", "rig_test_service_mode", {
         ping = function()
            return "ping"
         end,
      })
   end)
   test.falsey(incomplete_ok)
   test.match(tostring(incomplete_err), "implement method 'pong'")

   rig.register_runtime_mode("rig_test_service_mode", {
      loop = function()
         local service = rig.require_service("rig_test_service")
         _G.rig_test_service_result = {
            ping = service.ping(),
            pong = service.pong(),
         }
      end,
   })

   rig.register_service_impl("rig_test_service", "rig_test_service_mode", {
      ping = function()
         return "ping ok"
      end,
      pong = function()
         return "pong ok"
      end,
   })

   rig.run {
      mode = "rig_test_service_mode",
   }

   test.equal(rig_test_service_result.ping, "ping ok")
   test.equal(rig_test_service_result.pong, "pong ok")
end)
