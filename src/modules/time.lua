local M = ... or {}
local uv = require("uv")

M.CLOCK_MONOTONIC = uv.CLOCK_MONOTONIC
M.CLOCK_REALTIME = uv.CLOCK_REALTIME

function M.now_ns()
   return uv.now_ns()
end

function M.monotonic_ns()
   return uv.monotonic_ns()
end

function M.now()
   return uv.now()
end

function M.monotonic()
   return uv.monotonic()
end

return M
