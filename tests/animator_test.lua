local animator = require("animator")
local scenegraph = require("scenegraph")
local test = require("test")

local Object = scenegraph.Object

test.case("animator.App manages root, animator, and teardown lifecycle", function()
   local observed = {}
   local root = nil
   local scene_animator = nil
   local TestRoot = rig.Class(Object)
   local TestApp = rig.Class(animator.App)

   function TestRoot:init()
      self:super().init(self)
      self.released = false
   end

   function TestRoot:release()
      self.released = true
      table.insert(observed, "root_release")
   end

   function TestRoot:update(dt)
      table.insert(observed, string.format("update:%.6f", dt))
   end

   function TestApp:init()
      self:super().init(self, {
         module_config = {
            animator = {
               fixed_dt = 0.25,
               max_dt = 0.25,
               max_steps_per_frame = 1,
               start = false,
            },
         },
      })
      self.root = TestRoot()
      root = self.root
   end

   function TestApp:create_scene_animator(created_root)
      scene_animator = animator.Animator(created_root, self.animator_options)
      return scene_animator
   end

   function TestApp:after_setup()
      self:super().after_setup(self)
      table.insert(observed, "after_setup")
      test.equal(self.root, root)
      test.equal(self.animator, scene_animator)
   end

   function TestApp:release(released_root, released_animator)
      table.insert(observed, "release")
      test.equal(released_root, root)
      test.equal(released_animator, scene_animator)
   end

   local app = TestApp()

   app:after_setup()
   test.equal(app.root, root)
   test.equal(app.animator, scene_animator)
   test.equal(root.animator, scene_animator)
   test.equal(observed[1], "after_setup")

   app.animator.animation_last_monotonic = app.animator.animation_last_monotonic - 0.25
   app:before_drain()
   test.equal(observed[2], "update:0.250000")

   app:before_shutdown()
   test.equal(app.root, nil)
   test.equal(app.animator, nil)
   test.truthy(root.released)
   test.equal(observed[3], "root_release")
   test.equal(observed[4], "release")
end)

test.case("animator.App can create the root during after_setup", function()
   local root = nil
   local scene_animator = nil
   local TestRoot = rig.Class(Object)
   local TestApp = rig.Class(animator.App)

   function TestRoot:init()
      self:super().init(self)
   end

   function TestApp:init()
      self:super().init(self, {
         module_config = {
            animator = {
               start = false,
            },
         },
      })
   end

   function TestApp:create_root()
      root = TestRoot()
      return root
   end

   function TestApp:create_scene_animator(created_root)
      scene_animator = animator.Animator(created_root, self.animator_options)
      return scene_animator
   end

   local app = TestApp()
   app:after_setup()

   test.equal(app.root, root)
   test.equal(app.animator, scene_animator)
   test.equal(root.animator, scene_animator)
end)

test.case("animator.App runs activate() on the root tree before starting", function()
   local observed = {}
   local scene_animator = nil
   local Child = rig.Class(Object)
   local Root = rig.Class(Object)
   local TestApp = rig.Class(animator.App)

   function Child:activate()
      table.insert(observed, "child_activate")
      test.equal(self.animator, scene_animator)
   end

   function Root:init()
      self:super().init(self)
      self.child = self:add_child(Child())
   end

   function Root:activate()
      table.insert(observed, "root_activate")
      test.equal(self.animator, scene_animator)
   end

   function TestApp:init()
      self:super().init(self, {
         module_config = {
            animator = {
               start = false,
            },
         },
      })
      self.root = Root()
   end

   function TestApp:create_scene_animator(root)
      scene_animator = animator.Animator(root, self.animator_options)
      return scene_animator
   end

   local app = TestApp()
   app:after_setup()

   test.equal(#observed, 2)
   test.equal(observed[1], "root_activate")
   test.equal(observed[2], "child_activate")
end)

test.case("animator.App releases the root tree if activate() fails", function()
   local observed = {}
   local Root = rig.Class(Object)
   local Child = rig.Class(Object)
   local TestApp = rig.Class(animator.App)

   function Child:activate()
      self.token = self:own("child token", function(_, resource)
         table.insert(observed, "resource:" .. resource)
      end)
      error("boom")
   end

   function Child:release()
      table.insert(observed, "child_release")
   end

   function Root:init()
      self:super().init(self)
      self.child = self:add_child(Child())
   end

   function Root:release()
      table.insert(observed, "root_release")
   end

   function TestApp:init()
      self:super().init(self, {
         module_config = {
            animator = {
               start = false,
            },
         },
      })
      self.root = Root()
   end

   local app = TestApp()
   local ok, err = pcall(function()
      app:after_setup()
   end)

   test.equal(ok, false)
   test.match(tostring(err), "boom")
   test.equal(app.root, nil)
   test.equal(app.animator, nil)
   test.equal(#observed, 3)
   test.equal(observed[1], "child_release")
   test.equal(observed[2], "resource:child token")
   test.equal(observed[3], "root_release")
end)
