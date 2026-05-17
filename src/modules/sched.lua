local M = ... or {}

M._handlers = M._handlers or {}
M._active_scheduler = M._active_scheduler or nil
M._current_task = M._current_task or nil

local yieldable_tag = {}

local scheduler_mt = {}
scheduler_mt.__index = scheduler_mt

local function enqueue_item(queue, item)
   table.insert(queue, item)
end

M._handlers["sched.yield"] = function(scheduler, task)
   enqueue_item(scheduler._ready, {
      task = task,
      argc = 0,
      values = {},
   })
end

M._handlers["sched.park"] = function()
end

local function pop_item(queue)
   if #queue == 0 then
      return nil
   end
   return table.remove(queue, 1)
end

local function set_pending_error(self, err)
   if self._pending_error == nil then
      self._pending_error = err
   end
end

local function is_yieldable(value)
   return type(value) == "table" and value._sched_tag == yieldable_tag
end

function scheduler_mt:_complete_task(task)
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

function scheduler_mt:_resume_task(task, ...)
   M._active_scheduler = self
   M._current_task = task
   local ok, yielded_or_err = coroutine.resume(task.co, ...)
   M._current_task = nil
   M._active_scheduler = self

   if not ok then
      self._active_tasks = self._active_tasks - 1
      self:_complete_task(task)
      set_pending_error(self, yielded_or_err)
      return
   end

   if coroutine.status(task.co) == "dead" then
      self._active_tasks = self._active_tasks - 1
      self:_complete_task(task)
      return
   end

   if not is_yieldable(yielded_or_err) then
      self._active_tasks = self._active_tasks - 1
      self:_complete_task(task)
      set_pending_error(
         self,
         "scheduler task yielded a non-yieldable value"
      )
      return
   end

   local handler = self._handlers[yielded_or_err.kind]
   if type(handler) ~= "function" then
      self._active_tasks = self._active_tasks - 1
      set_pending_error(
         self,
         ("no scheduler handler is registered for '%s'"):format(
            tostring(yielded_or_err.kind)
         )
      )
      return
   end

   local handler_ok, handler_err = pcall(
      handler,
      self,
      task,
      yielded_or_err.payload
   )
   if not handler_ok then
      self._active_tasks = self._active_tasks - 1
      self:_complete_task(task)
      set_pending_error(self, handler_err)
   end
end

function scheduler_mt:spawn(fn, ...)
   if type(fn) ~= "function" then
      error("sched.spawn expects a function", 0)
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

function scheduler_mt:wake(task, ...)
   enqueue_item(self._completions, {
      task = task,
      argc = select("#", ...),
      values = { ... },
   })
end

function scheduler_mt:begin_async()
   self._pending_async = self._pending_async + 1
end

function scheduler_mt:end_async()
   if self._pending_async <= 0 then
      error("scheduler pending async count underflow", 0)
   end
   self._pending_async = self._pending_async - 1
end

function scheduler_mt:has_live_tasks()
   return self._active_tasks > 0
end

function scheduler_mt:has_ready_work()
   return #self._ready > 0 or #self._completions > 0
end

function scheduler_mt:pending_async()
   return self._pending_async
end

function scheduler_mt:drain()
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
      error(err, 0)
   end
end

function scheduler_mt:activate()
   M._active_scheduler = self
end

function scheduler_mt:deactivate()
   if M._active_scheduler == self then
      M._active_scheduler = nil
   end
   M._current_task = nil
end

function M.register_handler(kind, handler)
   if type(kind) ~= "string" or kind == "" then
      error("sched.register_handler expects kind to be a non-empty string", 0)
   end
   if type(handler) ~= "function" then
      error("sched.register_handler expects handler to be a function", 0)
   end
   if M._handlers[kind] ~= nil then
      error(
         ("sched.register_handler already has a handler for '%s'"):format(kind),
         0
      )
   end

   M._handlers[kind] = handler
end

function M.create(label)
   if label ~= nil and (type(label) ~= "string" or label == "") then
      error("sched.create expects label to be a non-empty string if provided", 0)
   end

   return setmetatable({
      _label = label or "scheduler",
      _handlers = M._handlers,
      _ready = {},
      _completions = {},
      _active_tasks = 0,
      _pending_async = 0,
      _pending_error = nil,
   }, scheduler_mt)
end

function M.build_request(kind, payload)
   if type(kind) ~= "string" or kind == "" then
      error("sched.build_request expects kind to be a non-empty string", 0)
   end

   return {
      _sched_tag = yieldable_tag,
      kind = kind,
      payload = payload,
   }
end

function M.await(kind, payload)
   if M._current_task == nil then
      error("sched.await may only be called from a scheduler-managed coroutine", 0)
   end
   return coroutine.yield(M.build_request(kind, payload))
end

function M.yield()
   return M.await("sched.yield")
end

function M.park()
   return M.await("sched.park")
end

function M.spawn(fn, ...)
   local scheduler = M._active_scheduler
   if scheduler == nil then
      error("sched.spawn requires an active scheduler", 0)
   end
   return scheduler:spawn(fn, ...)
end

function M.join(tasks)
   if M._current_task == nil then
      error("sched.join may only be called from a scheduler-managed coroutine", 0)
   end
   if type(tasks) ~= "table" then
      error("sched.join expects a table of tasks", 0)
   end

   local pending = {}
   for i = 1, #tasks do
      local task = tasks[i]
      if type(task) ~= "table" or type(task.co) ~= "thread" then
         error(("sched.join expects tasks[%d] to be a scheduler task"):format(i), 0)
      end
      if not task._done then
         table.insert(pending, task)
      end
   end

   if #pending == 0 then
      return true
   end

   local waiter = {
      task = M._current_task,
      remaining = #pending,
      resumed = false,
   }
   for i = 1, #pending do
      table.insert(pending[i]._waiters, waiter)
   end

   return M.park()
end

return M
