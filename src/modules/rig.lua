local M = ... or {}
local lua_tostring = _G.tostring

local function is_identifier(key)
   return type(key) == "string" and key:match("^[_%a][_%w]*$") ~= nil
end

local function serialize_lua(value, seen)
   local value_type = type(value)

   if value_type ~= "table" then
      if value_type == "string" then
         return string.format("%q", value)
      end
      return tostring(value)
   end

   if seen[value] then
      return "{ --[[cycle]] }"
   end
   seen[value] = true

   local parts = {}
   for k, v in pairs(value) do
      local val_repr = serialize_lua(v, seen)
      local key_repr
      if is_identifier(k) then
         key_repr = k
      else
         key_repr = "[" .. serialize_lua(k, seen) .. "]"
      end
      parts[#parts + 1] = key_repr .. " = " .. val_repr
   end

   seen[value] = nil
   return "{" .. table.concat(parts, ", ") .. "}"
end

function M.tostring(value)
   if type(value) == "table" then
      return serialize_lua(value, {})
   end
   return lua_tostring(value)
end

local function write_values(with_newline, ...)
   local parts = {}
   local stringify = M.tostring

   if type(stringify) ~= "function" then
      stringify = lua_tostring
   end

   for i = 1, select("#", ...) do
      local text = stringify(select(i, ...))
      if type(text) ~= "string" then
         error("'tostring' must return a string to 'rig.print'", 0)
      end
      parts[i] = text
   end

   local output = table.concat(parts, " ")
   if with_newline then
      output = output .. "\n"
   end

   local ok, err = io.stdout:write(output)
   if not ok then
      error(tostring(err or "failed to write to stdout"), 0)
   end

   io.stdout:flush()
end

function M.print(...)
   write_values(false, ...)
end

function M.println(...)
   write_values(true, ...)
end

local function load_lua_script(script_path, source)
   local chunk, err = loadstring(source, script_path)
   if chunk ~= nil then
      return chunk
   end
   return nil, "Lua: " .. tostring(err or "unknown error")
end

local function load_fennel_script(script_path, source)
   local fennel_mod = _G.fennel
   if type(fennel_mod) ~= "table" then
      return nil, "Fennel: global 'fennel' module is not available"
   end

   local compile_string = fennel_mod.compileString
   if type(compile_string) ~= "function" then
      return nil, "Fennel: fennel.compileString is not available"
   end

   local ok, compiled_source_or_err = pcall(compile_string, source, {
      filename = script_path,
   })
   if not ok then
      return nil, "Fennel: " .. tostring(compiled_source_or_err)
   end

   if compiled_source_or_err == nil then
      return nil, "Fennel: compiler did not return Lua source"
   end

   local chunk, load_err = loadstring(compiled_source_or_err, script_path)
   if chunk ~= nil then
      return chunk
   end

   return nil, "Fennel: " .. tostring(load_err or "unknown error")
end

M.script_loaders = {
   load_lua_script,
   load_fennel_script,
}

function M.load_script(script_path, source)
   if type(script_path) ~= "string" then
      error("rig.load_script expects script_path to be a string")
   end
   if type(source) ~= "string" then
      error("rig.load_script expects source to be a string")
   end

   local loader_errors = {}

   for i, loader in ipairs(M.script_loaders) do
      if type(loader) ~= "function" then
         loader_errors[i] = "script loader entry is not a function"
      else
         local chunk, err = loader(script_path, source)
         if type(chunk) == "function" then
            return chunk()
         end
         loader_errors[i] = tostring(err or "script loader rejected the script")
      end
   end

   error(
      ("failed to load script '%s' with any registered loader\n%s"):format(
         script_path,
         table.concat(loader_errors, "\n")
      ),
      0
   )
end

function M.run_script_file(script_path)
   if type(script_path) ~= "string" then
      error("rig.run_script_file expects script_path to be a string")
   end

   local file, open_err = io.open(script_path, "rb")
   if file == nil then
      error(
         ("failed to open '%s': %s"):format(
            script_path,
            tostring(open_err or "unknown error")
         ),
         0
      )
   end

   local source, read_err = file:read("*all")
   file:close()

   if source == nil then
      error(
         ("failed to read '%s': %s"):format(
            script_path,
            tostring(read_err or "unknown error")
         ),
         0
      )
   end

   return M.load_script(script_path, source)
end

return M
