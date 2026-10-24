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

-- Code-first sketch entrypoint. Assembles a default composition (bundle,
-- scene, entities, frame callbacks) on top of the builder/compiler/component
-- machinery so a demo can be a single Lua file. The implementation lives in
-- `sketch`, required lazily so core `rig` stays independent of the graphics
-- backends at load time.
function M.run(options, build)
   return require("sketch").run(options, build)
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

--[ module loading ]--

local function source_from_info(info)
   if info == nil or type(info.source) ~= "string" then
      return nil
   end

   local source = info.source
   if source:sub(1, 1) == "@" then
      return source:sub(2)
   end
   if source:sub(1, 1) == "=" or source:sub(1, 9) == "[string " then
      return nil
   end
   return source
end

-- Parses the file path out of a debug.getinfo(...) result. Returns nil for
-- chunks loaded from strings.
function M.source_of(info)
   return source_from_info(info)
end

-- Returns `path`'s directory including the trailing separator (or "").
function M.dirname(path)
   if type(path) ~= "string" then
      return ""
   end
   return path:match("^(.*[/\\])") or ""
end

-- Joins a directory with a possibly relative path; absolute paths pass through.
function M.join_path(directory, path)
   if type(path) ~= "string" or path == "" then
      raise("rig.join_path expects a non-empty path")
   end
   if directory == nil or directory == "" then
      return path
   end
   if path:sub(1, 1) == "/" or path:sub(1, 1) == "\\" or path:match("^%a:[/\\]") then
      return path
   end
   return directory .. path
end

local relative_extensions = { ".lua", ".fnl" }

local function relative_candidates(directory, name)
   local candidates = {}
   local lowered = name:lower()
   if lowered:sub(-4) == ".lua" or lowered:sub(-4) == ".fnl" then
      candidates[1] = directory .. name
      return candidates
   end

   for i = 1, #relative_extensions do
      candidates[#candidates + 1] = directory .. name .. relative_extensions[i]
   end
   for i = 1, #relative_extensions do
      candidates[#candidates + 1] =
         directory .. name .. "/init" .. relative_extensions[i]
   end
   return candidates
end

function M.file_exists(path)
   local file = io.open(path, "rb")
   if file == nil then
      return false
   end
   file:close()
   return true
end

function M.read_file(path)
   local file, open_err = io.open(path, "rb")
   if file == nil then
      return nil, open_err
   end

   local contents, read_err = file:read("*all")
   file:close()
   if contents == nil then
      return nil, read_err
   end
   return contents
end

local relative_modules = {}

-- Loads a module. Names beginning with '.' are resolved against the directory
-- of the calling script file and loaded through rig.load_script. Relative
-- modules are cached in a rig-private table keyed by canonical absolute path
-- (rig.realpath), so equivalent spellings and symlinks share one instance and
-- the modules never enter -- or conflict with -- the stock Lua require cache.
-- Lua and Fennel siblings are both supported, and nested relative requires
-- resolve against their own file.
function M.require(module_name)
   if type(module_name) ~= "string" or module_name == "" then
      raise("rig.require expects a non-empty module name")
   end

   if module_name:sub(1, 1) ~= "." then
      return require(module_name)
   end

   local source = M.source_of(debug.getinfo(2, "S"))
   if source == nil then
      raise(
         "rig.require cannot resolve '%s': the calling chunk has no file path",
         module_name
      )
   end

   local relative = module_name:sub(1, 2) == "./"
      and module_name:sub(3)
      or module_name
   if relative == "" then
      raise("rig.require expects a module path after './'")
   end

   local directory = M.dirname(source)
   local candidates = relative_candidates(directory, relative)

   local resolved = nil
   for i = 1, #candidates do
      if M.file_exists(candidates[i]) then
         resolved = candidates[i]
         break
      end
   end

   if resolved == nil then
      raise(
         "rig.require could not find module '%s' relative to '%s'",
         module_name,
         source
      )
   end

   local key = resolved
   if type(M.realpath) == "function" then
      local canonical = M.realpath(resolved)
      if canonical ~= nil then
         key = canonical
      end
   end

   local loaded = relative_modules[key]
   if loaded ~= nil then
      return loaded
   end

   local contents, read_err = M.read_file(resolved)
   if contents == nil then
      raise("failed to read '%s': %s", resolved, read_err or "unknown error")
   end

   local value = M.load_script(contents, key)
   if value == nil then
      value = true
   end
   relative_modules[key] = value

   return value
end

return M
