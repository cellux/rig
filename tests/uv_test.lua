local test = require("test")
local sched = require("sched")
local uv = require("uv")

test.case("uv scandir can see the tests directory", function()
   local entries, err = uv.scandir("tests")
   assert(entries ~= nil, err)

   local seen = {}
   for i = 1, #entries do
      seen[entries[i].name] = entries[i].type
   end

   test.equal(seen["uv_test.lua"], uv.DIRENT_FILE)
end)

test.case("uv.fs_read reads a file through the scheduler", function()
   local contents, err = uv.fs_read("tests/fixtures/assets/hello.txt")
   assert(contents ~= nil, err)
   test.equal(contents, "hello assets\n")
end)

test.case("uv.fs_write writes a file that uv.fs_read reads back", function()
   local path = os.tmpname()
   local payload = "rig async fs\nsecond line\n"

   local written, write_err = uv.fs_write(path, payload)
   assert(written ~= nil, write_err)
   test.equal(written, #payload)

   local contents, read_err = uv.fs_read(path)
   assert(contents ~= nil, read_err)
   test.equal(contents, payload)

   os.remove(path)
end)

test.case("uv.fs_read reassembles files larger than one read chunk", function()
   local path = os.tmpname()
   local payload = string.rep("0123456789abcdef", 8192) -- 128 KiB

   local written, write_err = uv.fs_write(path, payload)
   assert(written ~= nil, write_err)
   test.equal(written, #payload)

   local contents, read_err = uv.fs_read(path)
   assert(contents ~= nil, read_err)
   test.equal(contents, payload)

   os.remove(path)
end)

test.case("uv.fs_stat reports file metadata", function()
   local stat, err = uv.fs_stat("tests/fixtures/assets/hello.txt")
   assert(stat ~= nil, err)

   test.truthy(stat.is_file)
   test.falsey(stat.is_dir)
   test.falsey(stat.is_symlink)
   test.equal(stat.size, 13)
   test.truthy(stat.mtime > 0)
end)

test.case("uv.fs_stat reports directory metadata", function()
   local stat, err = uv.fs_stat("tests/fixtures/assets")
   assert(stat ~= nil, err)
   test.truthy(stat.is_dir)
   test.falsey(stat.is_file)
end)

test.case("uv.fs_read and uv.fs_stat error on a missing path", function()
   local contents, read_err = uv.fs_read("no-such-file-rig-xyz")
   test.equal(contents, nil)
   test.truthy(type(read_err) == "string")
   test.match(read_err, "uv%.fs_read failed")

   local stat, stat_err = uv.fs_stat("no-such-file-rig-xyz")
   test.equal(stat, nil)
   test.truthy(type(stat_err) == "string")
   test.match(stat_err, "uv%.fs_stat failed")
end)

test.case("uv fs operations are substitutable through the scheduler", function()
   local scheduler = sched.Scheduler("uv fs substitution")
   local seen = {}

   scheduler:set_handler("uv.fs_read", function(local_scheduler, task, path)
      seen.read_path = path
      local ticket = local_scheduler:start_async(task)
      ticket:wake("virtual contents")
   end)
   scheduler:set_handler("uv.fs_write", function(local_scheduler, task, spec)
      seen.write_path = spec.path
      seen.write_data = spec.data
      local ticket = local_scheduler:start_async(task)
      ticket:wake(#spec.data)
   end)
   scheduler:set_handler("uv.fs_stat", function(local_scheduler, task, path)
      seen.stat_path = path
      local ticket = local_scheduler:start_async(task)
      ticket:wake({ size = 7, is_file = true })
   end)

   local read_result = nil
   local write_result = nil
   local stat_result = nil
   scheduler:activate()
   sched.spawn(function()
      read_result = uv.fs_read("virtual.txt")
      write_result = uv.fs_write("virtual.txt", "payload")
      stat_result = uv.fs_stat("virtual.txt")
   end)
   scheduler:drain()
   scheduler:deactivate()

   test.equal(seen.read_path, "virtual.txt")
   test.equal(read_result, "virtual contents")
   test.equal(seen.write_path, "virtual.txt")
   test.equal(seen.write_data, "payload")
   test.equal(write_result, 7)
   test.equal(seen.stat_path, "virtual.txt")
   test.equal(stat_result.size, 7)
   test.truthy(stat_result.is_file)
end)

test.case("uv fs operations validate arguments before awaiting", function()
   local read_ok, read_err = pcall(function()
      uv.fs_read("")
   end)
   test.falsey(read_ok)
   test.match(tostring(read_err), "uv%.fs_read expects path to be a non%-empty string")

   local write_ok, write_err = pcall(function()
      uv.fs_write("path.txt", 123)
   end)
   test.falsey(write_ok)
   test.match(tostring(write_err), "uv%.fs_write expects data to be a string")
end)

test.case("uv clock helpers return numbers", function()
   local now = uv.now()
   local monotonic = uv.monotonic()

   test.equal(type(now), "number")
   test.equal(type(monotonic), "number")
   test.truthy(now > 0)
   test.truthy(monotonic > 0)
end)

test.case("sched.sleep waits under uv mode", function()
   local start = uv.monotonic()
   sched.sleep(0.01)
   local elapsed = uv.monotonic() - start

   test.truthy(elapsed >= 0.005)
end)

test.case("uv.spawn validates spec through schema before awaiting", function()
   local missing_file_ok, missing_file_err = pcall(function()
      uv.spawn({})
   end)
   test.falsey(missing_file_ok)
   test.match(tostring(missing_file_err), "uv%.spawn spec%.file expects a non%-empty string")

   local bad_args_ok, bad_args_err = pcall(function()
      uv.spawn {
         file = rig.argv[0],
         args = { rig.argv[0], 123 },
      }
   end)
   test.falsey(bad_args_ok)
   test.match(tostring(bad_args_err), "uv%.spawn spec%.args%[2%] expects a string")
end)
