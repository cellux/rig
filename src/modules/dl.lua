local M = ... or {}
local ffi = require("ffi")
local bit = require("bit")
local platform = require("platform")
local rig = require("rig")
local windows = require("windows")

ffi.cdef[[
void *rig_dl_open(const char *path);
void *rig_dl_open_flags(const char *path, int flags);
void *rig_dl_sym(void *handle, const char *name);
int rig_dl_close(void *handle);
const char *rig_dl_error(void);
]]

local function unix_last_error()
   local ptr = ffi.C.rig_dl_error()
   if ptr == nil or ptr == ffi.NULL then
      return "unknown dynamic loader error"
   end
   return ffi.string(ptr)
end

local function windows_last_error(prefix)
   local code = windows.GetLastError()
   local flags = bit.bor(
      windows.FORMAT_MESSAGE_FROM_SYSTEM,
      windows.FORMAT_MESSAGE_IGNORE_INSERTS
   )
   local buffer = ffi.new("char[512]")
   local rc =
      windows.FormatMessageA(flags, nil, code, 0, buffer, ffi.sizeof(buffer), nil)
   local message

   if tonumber(rc) == 0 then
      message = ("Windows error %lu"):format(tonumber(code))
   else
      message = ffi.string(buffer, tonumber(rc)):gsub("[\r\n ]+$", "")
   end

   if prefix == nil then
      return message
   end

   return ("%s: %s"):format(prefix, message)
end

local function utf8_to_utf16(text)
   local length =
      windows.MultiByteToWideChar(windows.CP_UTF8, 0, text, -1, nil, 0)
   if tonumber(length) <= 0 then
      return nil, windows_last_error("failed to convert UTF-8 path to UTF-16")
   end

   local buffer = ffi.new("WCHAR[?]", tonumber(length))
   if tonumber(
      windows.MultiByteToWideChar(
         windows.CP_UTF8,
         0,
         text,
         -1,
         buffer,
         tonumber(length)
      )
   ) <= 0 then
      return nil, windows_last_error("failed to convert UTF-8 path to UTF-16")
   end

   return buffer
end

function M.open(path, flags)
   if path ~= nil and (type(path) ~= "string" or path == "") then
      rig.raise("dl.open expects path to be a non-empty string or nil")
   end
   if flags ~= nil and type(flags) ~= "number" then
      rig.raise("dl.open expects flags to be a number if provided")
   end

   if platform.is_windows() then
      if path == nil then
         local handle = windows.GetModuleHandleW(nil)
         if handle == nil or handle == ffi.NULL then
            return nil, windows_last_error("failed to get current process module")
         end
         return handle
      end

      local wide_path, wide_err = utf8_to_utf16(path)
      if wide_path == nil then
         return nil, wide_err
      end

      local handle = windows.LoadLibraryW(wide_path)
      if handle == nil or handle == ffi.NULL then
         return nil, windows_last_error("failed to load shared object")
      end

      return handle
   end

   local handle
   if flags == nil then
      handle = ffi.C.rig_dl_open(path)
   else
      handle = ffi.C.rig_dl_open_flags(path, flags)
   end

   if handle == nil or handle == ffi.NULL then
      return nil, unix_last_error()
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

   if platform.is_windows() then
      local symbol = windows.GetProcAddress(ffi.cast("HMODULE", handle), name)
      local raw_symbol = ffi.cast("void *", symbol)
      if raw_symbol == nil or raw_symbol == ffi.NULL then
         return nil, windows_last_error("failed to load symbol")
      end

      if ctype == nil then
         return raw_symbol
      end

      local ok, cast_or_err = pcall(ffi.cast, ctype, raw_symbol)
      if not ok then
         return nil, ("resolved symbol '%s', but failed to cast it to %s"):format(
            name,
            ctype
         )
      end

      return cast_or_err
   end

   local symbol = ffi.C.rig_dl_sym(handle, name)
   if symbol == nil or symbol == ffi.NULL then
      return nil, unix_last_error()
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

   if platform.is_windows() then
      if windows.FreeLibrary(ffi.cast("HMODULE", handle)) == 0 then
         return nil, windows_last_error("failed to unload shared object")
      end
      return true
   end

   if ffi.C.rig_dl_close(handle) ~= 0 then
      return nil, unix_last_error()
   end

   return true
end

return M
