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
