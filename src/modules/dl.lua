local M = ... or {}
local ffi = require("ffi")
local rig = require("rig")

ffi.cdef[[
void *rig_dl_open(const char *path);
void *rig_dl_open_flags(const char *path, int flags);
void *rig_dl_sym(void *handle, const char *name);
int rig_dl_close(void *handle);
const char *rig_dl_error(void);
]]

local function last_error()
   local ptr = ffi.C.rig_dl_error()
   if ptr == nil or ptr == ffi.NULL then
      return "unknown dynamic loader error"
   end
   return ffi.string(ptr)
end

function M.open(path, flags)
   if path ~= nil and (type(path) ~= "string" or path == "") then
      rig.raise("dl.open expects path to be a non-empty string or nil")
   end
   if flags ~= nil and type(flags) ~= "number" then
      rig.raise("dl.open expects flags to be a number if provided")
   end

   local handle
   if flags == nil then
      handle = ffi.C.rig_dl_open(path)
   else
      handle = ffi.C.rig_dl_open_flags(path, flags)
   end

   if handle == nil or handle == ffi.NULL then
      return nil, last_error()
   end

   return handle
end

function M.sym(handle, name, ctype)
   if handle == nil or handle == ffi.NULL then
      rig.raise("dl.sym expects a handle")
   end
   if type(name) ~= "string" or name == "" then
      rig.raise("dl.sym expects name to be a non-empty string")
   end
   if ctype ~= nil and (type(ctype) ~= "string" or ctype == "") then
      rig.raise("dl.sym expects ctype to be a non-empty string if provided")
   end

   local symbol = ffi.C.rig_dl_sym(handle, name)
   if symbol == nil or symbol == ffi.NULL then
      return nil, last_error()
   end

   if ctype == nil then
      return symbol
   end

   local ok, cast_or_err = pcall(ffi.cast, ctype, symbol)
   if not ok then
      return nil, ("resolved symbol '%s', but failed to cast it to %s"):format(
         name,
         ctype
      )
   end

   return cast_or_err
end

function M.close(handle)
   if handle == nil or handle == ffi.NULL then
      rig.raise("dl.close expects a handle")
   end

   if ffi.C.rig_dl_close(handle) ~= 0 then
      return nil, last_error()
   end

   return true
end

return M
