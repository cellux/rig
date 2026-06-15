local M = ... or {}

function M.raise(message, ...)
   if select("#", ...) > 0 then
      message = string.format(message, ...)
   end
   error(message, 0)
end

function M.class(parent)
   if parent ~= nil and type(parent) ~= "table" then
      M.raise("prelude.class expects parent to be a table if provided")
   end

   local c = {}
   c.__index = c

   function c:super()
      return parent
   end

   function c:is_instance(value)
      local current = getmetatable(value)

      while type(current) == "table" do
         if current == self then
            return true
         end

         local current_mt = getmetatable(current)
         if type(current_mt) ~= "table" then
            return false
         end

         current = rawget(current_mt, "__index")
      end

      return false
   end

   setmetatable(c, {
      __index = parent,
      __call = function(class_table, ...)
         local instance = setmetatable({}, class_table)
         if type(instance.init) == "function" then
            instance:init(...)
         end
         return instance
      end,
   })

   return c
end

return M
