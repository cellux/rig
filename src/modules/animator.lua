local M = ... or {}
local rig = require("rig")
local sched = require("sched")
local time = require("time")

M.DEFAULT_FIXED_DT = 1.0 / 120.0
M.DEFAULT_MAX_DT = 0.05
M.DEFAULT_MAX_STEPS_PER_FRAME = 6

local Animator = rig.class()

M.Animator = Animator

function Animator:init(root, options)
   options = options or {}

   self.root = nil
   self.animate_enabled = true
   self.animation_time = 0.0
   self.animation_last_monotonic = 0.0
   self.animation_accumulator = 0.0
   self.animation_step_generation = 0
   self.animation_step_count = 0
   self.fixed_dt = options.fixed_dt or M.DEFAULT_FIXED_DT
   self.max_dt = options.max_dt or M.DEFAULT_MAX_DT
   self.max_steps_per_frame = options.max_steps_per_frame or M.DEFAULT_MAX_STEPS_PER_FRAME
   self.drive_tasks = {}

   if root ~= nil then
      self:register_root(root)
   end
end

function Animator:register_root(root)
   if root == nil then
      rig.raise("Animator:register_root requires a root object")
   end

   self.root = root
   root:set_animator(self)
end

function Animator:start()
   self.animation_time = 0.0
   self.animation_last_monotonic = time.monotonic()
   self.animation_accumulator = 0.0
   self.animation_step_generation = 0
   self.animation_step_count = 0
   self.drive_tasks = {}

   if self.root ~= nil then
      self.root:spawn_drive_tasks(self.drive_tasks)
   end
end

function Animator:set_enabled(enabled)
   self.animate_enabled = enabled

   if enabled then
      self.animation_last_monotonic = time.monotonic()
      local scheduler = sched.active_scheduler()
      if scheduler ~= nil then
         for i = 1, #self.drive_tasks do
            scheduler:wake(self.drive_tasks[i])
         end
      end
   end
end

function Animator:update_scene(dt)
   if self.root ~= nil then
      self.root:update_tree(dt)
   end
end

function Animator:next_steps(last_generation)
   while true do
      if not self.animate_enabled then
         sched.park()
      elseif self.animation_step_generation ~= last_generation then
         return self.animation_step_generation, self.animation_step_count
      else
         sched.park()
      end
   end
end

function Animator:sleep(duration)
   local deadline = self.animation_time + duration
   local generation = self.animation_step_generation

   while self.animation_time < deadline do
      generation = self:next_steps(generation)
   end
end

function Animator:tick()
   if not self.animate_enabled then
      self.animation_last_monotonic = time.monotonic()
      return
   end

   local now = time.monotonic()
   local dt = now - self.animation_last_monotonic
   self.animation_last_monotonic = now
   if dt < 0.0 then
      dt = 0.0
   elseif dt > self.max_dt then
      dt = self.max_dt
   end

   self.animation_accumulator = self.animation_accumulator + dt
   local steps = 0
   while self.animation_accumulator >= self.fixed_dt and steps < self.max_steps_per_frame do
      self.animation_accumulator = self.animation_accumulator - self.fixed_dt
      steps = steps + 1
   end

   if self.max_steps_per_frame > 0 then
      if steps == self.max_steps_per_frame and self.animation_accumulator > self.fixed_dt then
         self.animation_accumulator = self.fixed_dt
      end
   end

   if steps == 0 then
      return
   end

   for _ = 1, steps do
      self:update_scene(self.fixed_dt)
      self.animation_time = self.animation_time + self.fixed_dt
   end
   self.animation_step_count = steps
   self.animation_step_generation = self.animation_step_generation + 1

   local scheduler = sched.active_scheduler()
   if scheduler ~= nil then
      for i = 1, #self.drive_tasks do
         scheduler:wake(self.drive_tasks[i])
      end
   end
end

return M
