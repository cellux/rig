local M = ... or {}
local ffi = ffi

ffi.cdef[[
typedef long time_t;
typedef long long int64_t;
typedef struct timespec {
   time_t tv_sec;
   long tv_nsec;
} timespec;
int clock_gettime(int clk_id, struct timespec *tp);
]]

M.CLOCK_REALTIME = 0
M.CLOCK_MONOTONIC = 1

local function read_timespec(clock_id, label)
   local tp = ffi.new("struct timespec[1]")
   if ffi.C.clock_gettime(clock_id, tp) ~= 0 then
      error("clock_gettime(" .. label .. ") failed", 0)
   end

   return tonumber(tp[0].tv_sec), tonumber(tp[0].tv_nsec)
end

local function read_clock(clock_id, label)
   local seconds, nanoseconds = read_timespec(clock_id, label)
   return seconds + nanoseconds / 1000000000.0
end

local function read_clock_ns(clock_id, label)
   local seconds, nanoseconds = read_timespec(clock_id, label)
   return seconds * 1000000000 + nanoseconds
end

function M.now_ns()
   return read_clock_ns(M.CLOCK_REALTIME, "CLOCK_REALTIME")
end

function M.monotonic_ns()
   return read_clock_ns(M.CLOCK_MONOTONIC, "CLOCK_MONOTONIC")
end

function M.now()
   return read_clock(M.CLOCK_REALTIME, "CLOCK_REALTIME")
end

function M.monotonic()
   return read_clock(M.CLOCK_MONOTONIC, "CLOCK_MONOTONIC")
end

return M
