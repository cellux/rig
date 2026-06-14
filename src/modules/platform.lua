local M = ... or {}

M.os = jit.os

function M.is_windows()
   return M.os == "Windows"
end

function M.is_linux()
   return M.os == "Linux"
end

function M.is_osx()
   return M.os == "OSX"
end

function M.is_bsd()
   return M.os == "BSD"
end

function M.is_posix()
   return M.os == "POSIX"
end

function M.is_other()
   return M.os == "Other"
end

function M.is_unix()
   return M.is_linux() or M.is_osx() or M.is_bsd() or M.is_posix()
end

return M
