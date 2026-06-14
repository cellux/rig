local platform = require("platform")
local test = require("test")

test.case("platform exposes the current jit.os string", function()
   test.equal(platform.os, jit.os)
end)

test.case("platform helpers match the current host", function()
   test.equal(platform.is_windows(), jit.os == "Windows")
   test.equal(platform.is_linux(), jit.os == "Linux")
   test.equal(platform.is_osx(), jit.os == "OSX")
   test.equal(platform.is_bsd(), jit.os == "BSD")
   test.equal(platform.is_posix(), jit.os == "POSIX")
   test.equal(platform.is_other(), jit.os == "Other")
end)

test.case("platform.is_unix groups unix-like hosts", function()
   local expected = jit.os == "Linux"
      or jit.os == "OSX"
      or jit.os == "BSD"
      or jit.os == "POSIX"
   test.equal(platform.is_unix(), expected)
end)
