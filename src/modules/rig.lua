local M = ... or {}
local prelude = require("prelude")
local repr = require("repr")

M.repr = repr.repr
M.set = prelude.set
M.is_class = prelude.is_class
M.Class = prelude.Class
M.raise = prelude.raise

local raise = M.raise

--[ runtime builder ]--

function M.runtime()
   return require("runtime").Builder()
end

function M.shallow_copy(value)
   if type(value) ~= "table" then
      return value
   end

   local copy = {}
   for key, entry in pairs(value) do
      copy[key] = entry
   end
   return copy
end

--[ rig.tostring ]--

local function stringify(value)
   if type(value) == "table" then
      local mt = getmetatable(value)
      if type(mt) == "table" and type(rawget(mt, "__tostring")) == "function" then
         return tostring(value)
      end
      return M.repr(value)
   end
   return tostring(value)
end

M.tostring = stringify

--[ printers ]--

local function print_values(stream, with_newline, ...)
   local parts = {}
   for i = 1, select("#", ...) do
      local text = stringify(select(i, ...))
      if type(text) ~= "string" then
         raise("'tostring' must return a string to 'rig.print'")
      end
      parts[i] = text
   end

   local output = table.concat(parts, " ")
   if with_newline then
      output = output .. "\n"
   end

   local ok, err = stream:write(output)
   if not ok then
      raise(err or "failed to write output")
   end

   if type(stream.flush) == "function" then
      ok, err = stream:flush()
      if not ok then
         raise(err or "failed to flush output")
      end
   end
end

function M.print(...)
   print_values(io.stdout, false, ...)
end

function M.printf(format_string, ...)
   M.print(string.format(format_string, ...))
end

function M.println(...)
   print_values(io.stdout, true, ...)
end

function M.eprint(...)
   print_values(io.stderr, false, ...)
end

function M.eprintf(format_string, ...)
   M.eprint(string.format(format_string, ...))
end

function M.eprintln(...)
   print_values(io.stderr, true, ...)
end

function M.fprint(stream, ...)
   print_values(stream, false, ...)
end

function M.fprintf(stream, format_string, ...)
   M.fprint(stream, string.format(format_string, ...))
end

function M.fprintln(stream, ...)
   print_values(stream, true, ...)
end

--[ FFI loaders ]--

function M.create_ffi_library_loader(options)
   if type(options) ~= "table" then
      raise("rig.create_ffi_library_loader expects an options table")
   end

   local label = options.label
   if type(label) ~= "string" or label == "" then
      raise("rig.create_ffi_library_loader expects label to be a non-empty string")
   end

   local candidates = options.candidates
   if type(candidates) ~= "table" then
      raise("rig.create_ffi_library_loader expects candidates to be an array")
   end

   local resolved_candidates = {}
   for i, name in ipairs(candidates) do
      if type(name) ~= "string" or name == "" then
         raise(
            "rig.create_ffi_library_loader expects candidates[%d] to be a non-empty string",
            i
         )
      end
      resolved_candidates[i] = name
   end
   if #resolved_candidates == 0 then
      raise("rig.create_ffi_library_loader expects at least one candidate")
   end

   local ffi = require("ffi")
   local library = nil
   local load_error = nil

   return function()
      if library ~= nil then
         return library
      end
      if load_error ~= nil then
         error(load_error)
      end

      local failures = {}
      for i, name in ipairs(resolved_candidates) do
         local ok, lib = pcall(ffi.load, name)
         if ok then
            library = lib
            return lib
         end
         failures[i] = tostring(lib)
      end

      load_error = ("failed to load %s library: %s"):format(
         label,
         table.concat(failures, "; ")
      )
      error(load_error)
   end
end

--[ ResourceScope ]--

M.ResourceScope = M.Class()

local function add_scope_entry(scope, resource, release_fn)
   local entry = {
      resource = resource,
      release_fn = release_fn,
   }
   table.insert(scope._entries, entry)
   return entry
end

function M.ResourceScope:init(context, label)
   if context == nil then
      raise("rig.ResourceScope requires a context value")
   end
   if label ~= nil and (type(label) ~= "string" or label == "") then
      raise("rig.ResourceScope expects label to be a non-empty string if provided")
   end

   self.context = context
   self._entries = {}
   self._named_entries = {}
   self._released = false
   self._scope_label = label or "resource scope"
end

function M.ResourceScope:adopt(resource, release_fn)
   if self._released then
      raise("cannot adopt a resource into a released " .. self._scope_label)
   end
   if resource == nil then
      raise("rig.ResourceScope:adopt requires a resource")
   end
   if type(release_fn) ~= "function" then
      raise("rig.ResourceScope:adopt requires a release function")
   end

   add_scope_entry(self, resource, release_fn)
   return resource
end

function M.ResourceScope:replace(key, resource, release_fn)
   if self._released then
      raise("cannot replace a resource in a released " .. self._scope_label)
   end
   if type(key) ~= "string" or key == "" then
      raise("rig.ResourceScope:replace requires a non-empty string key")
   end
   if resource == nil then
      raise("rig.ResourceScope:replace requires a resource")
   end
   if type(release_fn) ~= "function" then
      raise("rig.ResourceScope:replace requires a release function")
   end

   local existing = self._named_entries[key]
   if existing ~= nil then
      if existing.resource ~= nil then
         existing.release_fn(self.context, existing.resource)
      end
      existing.resource = nil
      existing.release_fn = nil
      self._named_entries[key] = nil
   end

   local entry = add_scope_entry(self, resource, release_fn)
   self._named_entries[key] = entry
   return resource
end

function M.ResourceScope:release()
   local errors = {}
   if self._released then
      return errors
   end

   for index = #self._entries, 1, -1 do
      local entry = self._entries[index]
      if entry.resource ~= nil then
         local ok, err = pcall(entry.release_fn, self.context, entry.resource)
         if not ok then
            errors[#errors + 1] = tostring(err)
         end
      end
      self._entries[index] = nil
   end

   self._named_entries = {}
   self._released = true
   return errors
end

--[ script loaders ]--

local function load_lua_script(source, script_path)
   local chunk, err = loadstring(source, script_path)
   if chunk ~= nil then
      return chunk
   end
   return nil, "Lua: " .. tostring(err or "unknown error")
end

local function load_fennel_script(source, script_path)
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

function M.load_script(source, script_path)
   if type(source) ~= "string" then
      error("rig.load_script expects source to be a string")
   end
   if type(script_path) ~= "string" then
      raise("rig.load_script expects script_path to be a string")
   end

   local loader_errors = {}

   for i, loader in ipairs(M.script_loaders) do
      if type(loader) ~= "function" then
         loader_errors[i] = "script loader entry is not a function"
      else
         local chunk, err = loader(source, script_path)
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
      ))
end

function M.run_script_file(script_path)
   if type(script_path) ~= "string" then
      raise("rig.run_script_file expects script_path to be a string")
   end

   local file, open_err = io.open(script_path, "rb")
   if file == nil then
      raise(
         "failed to open '%s': %s",
         script_path,
         open_err or "unknown error"
      )
   end

   local source, read_err = file:read("*all")
   file:close()

   if source == nil then
      raise(
         "failed to read '%s': %s",
         script_path,
         read_err or "unknown error"
      )
   end

   local result = M.load_script(source, script_path)

   if script_path:match("_test%.lua$")
      or script_path:match("_test%.fnl$") then
      require("test").run_registered_cases {
         script_path = script_path,
      }
   end

   return result
end

return M
