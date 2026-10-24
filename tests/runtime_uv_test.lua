local test = require("test")
local runtime = require("runtime")
local rig = require("rig")
local uv = require("uv")

local function build_uv_runtime(execute)
   local core = runtime.scheduler_plugin()
   local uv_plugin = uv.plugin()

   return rig.runtime()
      :use(core)
      :use(uv_plugin)
      :add(uv.clock_component(uv_plugin, { name = "clock" }))
      :add(runtime.timer_component(core, { name = "timer" }))
      :add(runtime.scheduler_component(core, { name = "scheduler" }))
      :add(uv.loop_component(uv_plugin, { name = "uv" }))
      :execute(execute)
      :compile()
end

test.case("uv component spawns a subprocess and captures stdout", function()
   local result = nil
   local compiled = build_uv_runtime(function(ctx)
      result = ctx.uv:spawn {
         file = "sh",
         args = { "sh", "-c", "printf hello" },
      }
   end)

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.truthy(result ~= nil)
   test.equal(result.stdout, "hello")
   test.truthy(result.success)
end)

test.case("uv component reports non-zero exit status", function()
   local result = nil
   local compiled = build_uv_runtime(function(ctx)
      result = ctx.uv:spawn {
         file = "sh",
         args = { "sh", "-c", "exit 3" },
      }
   end)

   compiled:start()

   test.truthy(result ~= nil)
   test.equal(result.exit_status, 3)
   test.falsey(result.success)
end)

test.case("uv component scans a directory", function()
   local entries = nil
   local compiled = build_uv_runtime(function(ctx)
      entries = ctx.uv:scandir("tests")
   end)

   compiled:start()

   test.truthy(entries ~= nil)
   local seen = {}
   for i = 1, #entries do
      seen[entries[i].name] = entries[i].type
   end
   test.equal(seen["uv_test.lua"], uv.DIRENT_FILE)
end)

test.case("uv component returns an error for missing directories", function()
   local entries = nil
   local err = nil
   local compiled = build_uv_runtime(function(ctx)
      entries, err = ctx.uv:scandir("no-such-directory-rig-xyz")
   end)

   compiled:start()

   test.equal(entries, nil)
   test.truthy(err ~= nil)
end)

test.case("uv clock component provides monotonic time", function()
   local clock_time = nil
   local loop_time = nil
   local compiled = build_uv_runtime(function(ctx)
      clock_time = ctx.clock:monotonic()
      loop_time = ctx.uv:monotonic()
   end)

   compiled:start()

   test.equal(type(clock_time), "number")
   test.equal(type(loop_time), "number")
   test.truthy(loop_time >= clock_time)
end)

test.case("uv component reads, writes, and stats files through the scheduler", function()
   local path = os.tmpname()
   local payload = "runtime fs\n"
   local read_back = nil
   local stat_size = nil
   local stat_is_file = nil

   local compiled = build_uv_runtime(function(ctx)
      local written = ctx.uv:fs_write(path, payload)
      test.equal(written, #payload)
      read_back = ctx.uv:fs_read(path)
      local stat = ctx.uv:fs_stat(path)
      stat_size = stat.size
      stat_is_file = stat.is_file
   end)

   compiled:start()

   test.equal(read_back, payload)
   test.equal(stat_size, #payload)
   test.truthy(stat_is_file)

   os.remove(path)
end)

test.case("uv loop is released after shutdown", function()
   local loop = nil
   local compiled = build_uv_runtime(function(ctx)
      loop = ctx.uv
   end)

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.truthy(loop ~= nil)
   test.truthy(loop.released)
end)

test.case("uv spawn validates the spec before awaiting", function()
   local ok, err = pcall(function()
      local loop = uv.UvLoop()
      loop:spawn {}
   end)

   test.falsey(ok)
   test.match(tostring(err), "uv%.spawn spec%.file expects a non%-empty string")
end)

test.case("a runtime scheduler blocks on uv file I/O", function()
   local loop = uv.UvLoop()
   local scheduler = runtime.Scheduler {
      clock = runtime.ManualClock(0),
      timer = runtime.Timer(),
      label = "uv block",
   }

   loop:install_handlers(scheduler)
   scheduler:set_pump(function()
      if loop.pending > 0 then
         loop:run()
      end
   end)

   local contents = scheduler:block(function()
      return uv.fs_read("tests/fixtures/assets/hello.txt")
   end)

   loop:release()

   test.equal(contents, "hello assets\n")
end)

test.case("asset.read blocks through sched on a uv scheduler", function()
   local asset = require("asset")
   local loop = uv.UvLoop()
   local scheduler = runtime.Scheduler {
      clock = runtime.ManualClock(0),
      timer = runtime.Timer(),
      label = "asset block",
   }

   loop:install_handlers(scheduler)
   scheduler:set_pump(function()
      if loop.pending > 0 then
         loop:run()
      end
   end)

   local contents = scheduler:block(function()
      return asset.read("fixtures/assets/hello.txt")
   end)

   loop:release()

   test.equal(contents, "hello assets\n")
end)
