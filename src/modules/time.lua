local M = ... or {}
local uv = require("uv")

function M.now()
   return uv.now()
end

function M.monotonic()
   return uv.monotonic()
end

return M
