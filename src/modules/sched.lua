local M = ... or {}
local rig = require("rig")

local _request_handlers = {}
local _active_scheduler = nil
local _current_task = nil

local Request = rig.class()
local AsyncTicket = rig.class()

local function is_request(value)
   return Request:is_instance(value)
end

local function is_task(value)
   return type(value) == "table" and type(value.co) == "thread"
end

local function begin_async(scheduler)
   scheduler._pending_async = scheduler._pending_async + 1
end

local function end_async(scheduler)
   if scheduler._pending_async <= 0 then
      rig.raise("scheduler pending async count underflow")
   end
   scheduler._pending_async = scheduler._pending_async - 1
end

local function finish_async_ticket(ticket)
   if ticket._done then
      rig.raise("async ticket already completed")
   end

   ticket._done = true
   end_async(ticket._scheduler)
   return ticket._scheduler, ticket._task
end

local function enqueue_item(queue, item)
   table.insert(queue, item)
end

local function pop_item(queue)
   if #queue == 0 then
      return nil
   end
   return table.remove(queue, 1)
end

function Request:init(kind, payload)
   if type(kind) ~= "string" or kind == "" then
      rig.raise("sched request expects kind to be a non-empty string")
   end

   self.kind = kind
   self.payload = payload
end

function AsyncTicket:init(scheduler, task)
   self._scheduler = scheduler
   self._task = task
   self._done = false
   begin_async(scheduler)
end

function AsyncTicket:is_done()
   return self._done
end

function AsyncTicket:wake(...)
   local scheduler, task = finish_async_ticket(self)
   scheduler:wake(task, ...)
end

function AsyncTicket:fail(err)
   local scheduler, task = finish_async_ticket(self)
   scheduler._active_tasks = scheduler._active_tasks - 1
   scheduler:_complete_task(task)
   scheduler:_set_pending_error(err)
end

M.Scheduler = rig.class()

function M.Scheduler:init(label)
   if label ~= nil and (type(label) ~= "string" or label == "") then
      rig.raise("sched.Scheduler expects label to be a non-empty string if provided")
   end

   self._label = label or "scheduler"
   self._handlers = setmetatable({}, { __index = _request_handlers })
   self._ready = {}
   self._next_ready = {}
   self._completions = {}
   self._sleeping = {}
   self._active_tasks = 0
   self._pending_async = 0
   self._pending_error = nil
end

function M.Scheduler:_set_pending_error(err)
   if self._pending_error == nil then
      self._pending_error = err
   end
end

function M.Scheduler:_complete_task(task)
   if task._done then
      return
   end

   task._done = true
   local waiters = task._waiters
   if waiters == nil then
      return
   end

   for i = 1, #waiters do
      local waiter = waiters[i]
      waiter.remaining = waiter.remaining - 1
      if waiter.remaining == 0 and not waiter.resumed then
         waiter.resumed = true
         self:wake(waiter.task, true)
      end
   end
   task._waiters = nil
end

function M.Scheduler:_resume_task(task, ...)
   _current_task = task
   local ok, yielded_or_err = coroutine.resume(task.co, ...)
   _current_task = nil

   if not ok then
      self._active_tasks = self._active_tasks - 1
      self:_complete_task(task)
      self:_set_pending_error(yielded_or_err)
      return
   end

   if coroutine.status(task.co) == "dead" then
      self._active_tasks = self._active_tasks - 1
      self:_complete_task(task)
      return
   end

   if not is_request(yielded_or_err) then
      self._active_tasks = self._active_tasks - 1
      self:_complete_task(task)
      self:_set_pending_error(
         "scheduler task yielded a non-request value"
      )
      return
   end

   local request = yielded_or_err
   if request.kind == "sched.yield" then
      enqueue_item(self._next_ready, {
         task = task,
         argc = 0,
         values = {},
      })
      return
   end
   if request.kind == "sched.park" then
      return
   end

   local handler = self._handlers[request.kind]
   if type(handler) ~= "function" then
      self._active_tasks = self._active_tasks - 1
      self:_complete_task(task)
      self:_set_pending_error(
         ("no scheduler handler is registered for '%s'"):format(
            request.kind
         )
      )
      return
   end

   local handler_ok, handler_err = pcall(
      handler,
      self,
      task,
      request.payload
   )
   if not handler_ok then
      self._active_tasks = self._active_tasks - 1
      self:_complete_task(task)
      self:_set_pending_error(handler_err)
   end
end

function M.Scheduler:spawn(fn, ...)
   if type(fn) ~= "function" then
      rig.raise("sched.spawn expects a function")
   end

   local task = {
      co = coroutine.create(fn),
      _done = false,
      _waiters = {},
   }
   self._active_tasks = self._active_tasks + 1
   enqueue_item(self._ready, {
      task = task,
      argc = select("#", ...),
      values = { ... },
   })
   return task
end

function M.Scheduler:set_handler(kind, handler)
   if type(kind) ~= "string" or kind == "" then
      rig.raise("scheduler:set_handler expects kind to be a non-empty string")
   end
   if type(handler) ~= "function" then
      rig.raise("scheduler:set_handler expects handler to be a function")
   end
   self._handlers[kind] = handler
end

function M.Scheduler:start_async(task)
   if not is_task(task) then
      rig.raise("scheduler:start_async expects a scheduler task")
   end
   return AsyncTicket(self, task)
end

function M.Scheduler:wake(task, ...)
   enqueue_item(self._completions, {
      task = task,
      argc = select("#", ...),
      values = { ... },
   })
end

function M.Scheduler:sleep_until(task, deadline)
   if not is_task(task) then
      rig.raise("scheduler:sleep_until expects a scheduler task")
   end
   if type(deadline) ~= "number" then
      rig.raise("scheduler:sleep_until expects deadline to be a number")
   end

   enqueue_item(self._sleeping, {
      task = task,
      deadline = deadline,
   })
end

function M.Scheduler:wake_due_sleepers(now)
   if type(now) ~= "number" then
      rig.raise("scheduler:wake_due_sleepers expects now to be a number")
   end

   local sleeping = self._sleeping
   local remaining = {}

   for i = 1, #sleeping do
      local entry = sleeping[i]
      if entry.deadline <= now then
         self:wake(entry.task)
      else
         table.insert(remaining, entry)
      end
   end

   self._sleeping = remaining
end

function M.Scheduler:has_active_tasks()
   return self._active_tasks > 0
end

function M.Scheduler:has_ready_work()
   return #self._ready > 0 or #self._completions > 0 or #self._next_ready > 0
end

function M.Scheduler:pending_async()
   return self._pending_async
end

function M.Scheduler:_flush_next_ready()
   local next_ready = self._next_ready
   if #next_ready == 0 then
      return
   end

   for i = 1, #next_ready do
      enqueue_item(self._ready, next_ready[i])
      next_ready[i] = nil
   end
end

function M.Scheduler:drain()
   self:_flush_next_ready()

   while self._pending_error == nil do
      local completion = pop_item(self._completions)
      if completion ~= nil then
         self:_resume_task(
            completion.task,
            unpack(completion.values, 1, completion.argc)
         )
      else
         local ready = pop_item(self._ready)
         if ready == nil then
            break
         end
         self:_resume_task(
            ready.task,
            unpack(ready.values, 1, ready.argc)
         )
      end
   end

   if self._pending_error ~= nil then
      local err = self._pending_error
      self._pending_error = nil
      rig.raise(err)
   end
end

function M.Scheduler:activate()
   _active_scheduler = self
end

function M.Scheduler:deactivate()
   if _active_scheduler == self then
      _active_scheduler = nil
   end
   _current_task = nil
end

function M.register_handler(kind, handler)
   if type(kind) ~= "string" or kind == "" then
      rig.raise("sched.register_handler expects kind to be a non-empty string")
   end
   if type(handler) ~= "function" then
      rig.raise("sched.register_handler expects handler to be a function")
   end
   if _request_handlers[kind] ~= nil then
      rig.raise("sched.register_handler already has a handler for '%s'", kind)
   end

   _request_handlers[kind] = handler
end

function M.active_scheduler()
   return _active_scheduler
end

function M.await(kind, payload)
   if _current_task == nil then
      rig.raise("sched.await may only be called from a scheduler-managed coroutine")
   end
   return coroutine.yield(Request(kind, payload))
end

function M.yield()
   return M.await("sched.yield")
end

function M.park()
   return M.await("sched.park")
end

function M.sleep(seconds)
   if type(seconds) ~= "number" then
      rig.raise("sched.sleep expects seconds to be a number")
   end
   if seconds < 0 then
      rig.raise("sched.sleep expects seconds to be non-negative")
   end

   return M.await("sched.sleep", seconds)
end

function M.spawn(fn, ...)
   local scheduler = _active_scheduler
   if scheduler == nil then
      rig.raise("sched.spawn requires an active scheduler")
   end
   return scheduler:spawn(fn, ...)
end

function M.join(tasks)
   if _current_task == nil then
      rig.raise("sched.join may only be called from a scheduler-managed coroutine")
   end
   if type(tasks) ~= "table" then
      rig.raise("sched.join expects a table of tasks")
   end

   local pending = {}
   for i = 1, #tasks do
      local task = tasks[i]
      if not is_task(task) then
         rig.raise("sched.join expects tasks[%d] to be a scheduler task", i)
      end
      if not task._done then
         table.insert(pending, task)
      end
   end

   if #pending == 0 then
      return true
   end

   local waiter = {
      task = _current_task,
      remaining = #pending,
      resumed = false,
   }
   for i = 1, #pending do
      table.insert(pending[i]._waiters, waiter)
   end

   return M.park()
end

return M
