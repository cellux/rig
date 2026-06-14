local M = ... or {}
local rig = require("rig")
local sched = require("sched")

local Object = rig.class()

M.Object = Object

function Object:init()
   self.children = {}
   self.enabled = true
   self.running = true
   self.parent = nil
   self.animator = nil
end

function Object:add_child(child)
   if child == nil then
      rig.raise("Object:add_child requires a child object")
   end

   child.parent = self
   table.insert(self.children, child)
   if self.animator ~= nil then
      child:set_animator(self.animator)
   end
   return child
end

function Object:set_animator(animator)
   self.animator = animator
   for i = 1, #self.children do
      self.children[i]:set_animator(animator)
   end
end

function Object:update_tree(dt)
   if type(self.update) == "function" then
      self:update(dt)
   end
   for i = 1, #self.children do
      self.children[i]:update_tree(dt)
   end
end

function Object:draw_tree(context)
   if self.enabled == false then
      return
   end

   if type(self.draw) == "function" then
      self:draw(context)
   end
   for i = 1, #self.children do
      self.children[i]:draw_tree(context)
   end
end

function Object:spawn_drive_tasks(tasks)
   if self.running ~= false and type(self.drive) == "function" then
      tasks[#tasks + 1] = sched.spawn(function()
         self:drive()
      end)
   end
   for i = 1, #self.children do
      self.children[i]:spawn_drive_tasks(tasks)
   end
end

function Object:release_tree()
   for i = #self.children, 1, -1 do
      self.children[i]:release_tree()
   end
   if type(self.release) == "function" then
      self:release()
   end
   self.children = {}
end

return M
