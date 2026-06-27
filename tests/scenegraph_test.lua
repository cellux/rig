local scenegraph = require("scenegraph")
local test = require("test")

local Object = scenegraph.Object

test.case("scenegraph.Object creates owned resource scopes lazily", function()
   local object = Object()

   test.equal(object._resource_scope, nil)

   local released = {}
   object:own("alpha", function(_, resource)
      table.insert(released, resource)
   end)

   test.truthy(object._resource_scope ~= nil)

   object:release_tree()

   test.equal(#released, 1)
   test.equal(released[1], "alpha")
   test.equal(object._resource_scope, nil)
end)

test.case("scenegraph.Object releases owned resources after release()", function()
   local observed = {}
   local TestObject = rig.Class(Object)

   function TestObject:release()
      table.insert(observed, "release")
      test.truthy(self.token ~= nil)
   end

   local object = TestObject()
   object.token = object:own("token", function(self_ref, resource)
      table.insert(observed, "resource")
      test.equal(self_ref, object)
      test.equal(resource, "token")
      object.token = nil
   end)

   object:release_tree()

   test.equal(#observed, 2)
   test.equal(observed[1], "release")
   test.equal(observed[2], "resource")
   test.equal(object.token, nil)
end)

test.case("scenegraph.Object can own nested scopes", function()
   local object = Object()
   local released = {}
   local nested = object:create_owned_scope("nested scope")

   nested:adopt("child", function(_, resource)
      table.insert(released, resource)
   end)

   object:release_tree()

   test.equal(#released, 1)
   test.equal(released[1], "child")
end)

test.case("scenegraph.Object runs activate() in parent-to-child order", function()
   local observed = {}
   local Parent = rig.Class(Object)
   local Child = rig.Class(Object)

   function Parent:activate()
      table.insert(observed, "parent")
   end

   function Child:activate()
      table.insert(observed, "child")
   end

   local root = Parent()
   root:add_child(Child())
   root:activate_tree()

   test.equal(#observed, 2)
   test.equal(observed[1], "parent")
   test.equal(observed[2], "child")
end)
