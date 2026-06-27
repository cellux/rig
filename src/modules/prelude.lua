local M = ... or {}

function M.raise(message, ...)
   if select("#", ...) > 0 then
      message = string.format(message, ...)
   end
   error(message, 0)
end

function M.set(values)
   if type(values) ~= "table" then
      M.raise("set expects values to be a table")
   end

   local set = {}
   for i = 1, #values do
      set[values[i]] = true
   end
   return set
end

local class_parent_key = {}

local Class = {}
M.Class = Class

local function is_class(value)
   return value == Class
      or (type(value) == "table" and rawget(value, class_parent_key) ~= nil)
end

M.is_class = is_class

local function class_of(value)
   if is_class(value) then
      return value
   end

   local value_mt = getmetatable(value)
   if is_class(value_mt) then
      return value_mt
   end

   return nil
end

function Class:super()
   local class_value = class_of(self)
   if class_value == nil then
      return nil
   end

   local parent = rawget(class_value, class_parent_key)
   if parent == Class then
      return nil
   end

   return parent
end

local function is_descendant(class_value, ancestor)
   if not is_class(class_value) or not is_class(ancestor) then
      return false
   end

   local current = class_value

   while current ~= nil do
      if current == ancestor then
         return true
      end

      current = rawget(current, class_parent_key)
   end

   return false
end

function Class:is_instance(value)
   if not is_class(self) then
      return false
   end
   if self == Class then
      return is_class(value)
   end

   return is_descendant(getmetatable(value), self)
end

function Class:is_descendant(ancestor)
   return is_descendant(self, ancestor)
end

function Class:is_ancestor(descendant)
   return is_descendant(descendant, self)
end

local function construct_class(parent)
   if parent ~= nil and not is_class(parent) then
      M.raise("Class expects parent to be a class if provided")
   end
   if parent == Class then
      M.raise("Class expects parent to be nil or a class other than Class")
   end

   local c = {}
   c.__index = c
   c[class_parent_key] = parent or Class
   return setmetatable(c, Class)
end

function Class:__call(...)
   if self == Class then
      return construct_class(...)
   end

   local instance = setmetatable({}, self)
   if type(instance.init) == "function" then
      instance:init(...)
   end
   return instance
end

function Class:__index(key)
   local parent = rawget(self, class_parent_key)
   if parent == nil then
      return nil
   end

   return parent[key]
end

setmetatable(Class, Class)

return M
