local M = ... or {}
local ffi = require("ffi")

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
      error("dl.open expects path to be a non-empty string or nil", 0)
   end
   if flags ~= nil and type(flags) ~= "number" then
      error("dl.open expects flags to be a number if provided", 0)
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
      error("dl.sym expects a handle", 0)
   end
   if type(name) ~= "string" or name == "" then
      error("dl.sym expects name to be a non-empty string", 0)
   end
   if ctype ~= nil and (type(ctype) ~= "string" or ctype == "") then
      error("dl.sym expects ctype to be a non-empty string if provided", 0)
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
      error("dl.close expects a handle", 0)
   end

   if ffi.C.rig_dl_close(handle) ~= 0 then
      return nil, last_error()
   end

   return true
end

return M
