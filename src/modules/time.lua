local M = ... or {}

rig.create_service("time", {
   "now",
   "monotonic",
})

function M.now()
   return rig.require_service("time").now()
end

function M.monotonic()
   return rig.require_service("time").monotonic()
end

return M
