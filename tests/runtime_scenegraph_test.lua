local test = require("test")
local runtime = require("runtime")
local rig = require("rig")
local animator = require("animator")
local scenegraph = require("scenegraph")

local function plugin(id, spec)
   spec = spec or {}
   spec.id = id
   return runtime.plugin(spec)
end

test.case("scene object resources release through the runtime root", function()
   local core = plugin("core")
   local released = {}

   local Root = rig.Class(scenegraph.Object)
   local Child = rig.Class(scenegraph.Object)

   function Root:init()
      self:super().init(self)
      self.child = self:add_child(Child())
      self.token = self:own("root-token", function(_, resource)
         released[#released + 1] = resource
      end)
   end

   function Child:init()
      self:super().init(self)
      self.token = self:own("child-token", function(_, resource)
         released[#released + 1] = resource
      end)
   end

   local App = rig.Class(animator.App)
   function App:init(context)
      self:super().init(self, context)
      self.root = Root()
   end

   local compiled = rig.runtime()
      :use(core)
      :add(runtime.descriptor(core, {
         name = "stop",
         progress = {
            should_stop = function()
               return true
            end,
         },
      }))
      :execute(App)
      :compile()

   compiled:start()

   test.equal(compiled.state, "stopped")
   -- Children are adopted after their parent, so they release first.
   test.equal(#released, 2)
   test.equal(released[1], "child-token")
   test.equal(released[2], "root-token")
end)

test.case("object resources added after activation still reach the runtime root", function()
   local core = plugin("core")
   local released = {}
   local root = nil

   local Node = rig.Class(scenegraph.Object)
   function Node:init()
      self:super().init(self)
      self.token = self:own("node-token", function(_, resource)
         released[#released + 1] = resource
      end)
   end

   local App = rig.Class(animator.App)
   function App:init(context)
      self:super().init(self, context)
      root = scenegraph.Object()
      self.root = root
   end

   local compiled = rig.runtime()
      :use(core)
      :add(runtime.descriptor(core, {
         name = "spawn",
         progress = {
            frame = function()
               root:add_child(Node())
            end,
         },
      }))
      :add(runtime.descriptor(core, {
         name = "stop",
         progress = {
            should_stop = function(context)
               return context.step >= 2
            end,
         },
      }))
      :execute(App)
      :compile()

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.equal(released[1], "node-token")
end)

test.case("runtime resource scope replace releases the previous resource", function()
   local scope = runtime.ResourceScope("replace scope")
   local released = {}

   scope:replace("owner", "key", { id = 1 }, function(resource)
      released[#released + 1] = resource.id
   end)
   scope:replace("owner", "key", { id = 2 }, function(resource)
      released[#released + 1] = resource.id
   end)

   local errors = scope:release()

   test.equal(#errors, 0)
   test.equal(#released, 2)
   test.equal(released[1], 1)
   test.equal(released[2], 2)
end)
