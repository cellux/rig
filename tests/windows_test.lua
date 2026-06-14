local ffi = require("ffi")
local test = require("test")
local windows = require("windows")

test.case("windows exposes shared constants", function()
   test.equal(windows.CP_UTF8, 65001)
   test.equal(windows.FORMAT_MESSAGE_IGNORE_INSERTS, 0x00000200)
   test.equal(windows.FORMAT_MESSAGE_FROM_SYSTEM, 0x00001000)
end)

test.case("windows defines shared FFI types", function()
   local guid = ffi.new("GUID")
   local unknown_ptr = ffi.new("IUnknown *[1]")

   test.equal(ffi.sizeof(guid), 16)
   test.truthy(unknown_ptr ~= nil)
end)
