local M = ... or {}
local time = require("time")
local uv = require("uv")
local sched = require("sched")

M._registered_cases = M._registered_cases or {}

local function is_test_script_path(script_path)
   return type(script_path) == "string"
      and (
         script_path:match("_test%.lua$") ~= nil
         or script_path:match("_test%.fnl$") ~= nil
      )
end

local function reset_registered_cases()
   M._registered_cases = {}
end

local function format_multiline(text, prefix)
   local lines = {}
   for line in tostring(text):gmatch("([^\n]*)\n?") do
      if line == "" and #lines > 0 then
         break
      end
      table.insert(lines, prefix .. line)
   end
   return table.concat(lines, "\n")
end

local function register_case(kind, name, fn)
   if type(name) ~= "string" or name == "" then
      error(("test.%s expects name to be a non-empty string"):format(kind), 0)
   end
   if type(fn) ~= "function" then
      error(("test.%s expects fn to be a function"):format(kind), 0)
   end

   table.insert(M._registered_cases, {
      name = name,
      fn = fn,
      serial = kind == "serial",
   })
end

local function fail_with_message(message)
   error(message, 0)
end

local function format_duration(duration_s)
   return string.format("%.3f ms", duration_s * 1000.0)
end

local function normalize_roots(roots)
   if roots == nil then
      return { "." }
   end
   if type(roots) ~= "table" then
      error("test.run expects roots to be a table if provided", 0)
   end
   if #roots == 0 then
      return { "." }
   end

   local normalized = {}
   for i = 1, #roots do
      local root = roots[i]
      if type(root) ~= "string" or root == "" then
         error(("test.run expects roots[%d] to be a non-empty string"):format(i), 0)
      end
      table.insert(normalized, root)
   end
   return normalized
end

local function normalize_jobs(value)
   if value == nil then
      return 1
   end
   local jobs = tonumber(value)
   if jobs == nil or jobs < 1 then
      error("test.run expects jobs to be a positive number if provided", 0)
   end
   jobs = math.floor(jobs)
   if jobs < 1 then
      jobs = 1
   end
   return jobs
end

local function discover_files(roots)
   local files = {}

   local function is_test_file(name)
      return name:match("_test%.lua$") ~= nil
         or name:match("_test%.fnl$") ~= nil
   end

   local function walk(path)
      local entries, err = uv.scandir(path)
      if entries == nil then
         error(err, 0)
      end

      for i = 1, #entries do
         local entry = entries[i]
         local child = path .. "/" .. entry.name
         if entry.type == uv.DIRENT_DIR then
            walk(child)
         elseif entry.type == uv.DIRENT_FILE and is_test_file(entry.name) then
            table.insert(files, child)
         end
      end
   end

   for i = 1, #roots do
      walk(roots[i])
   end

   table.sort(files)
   return files
end

local function parse_tap_summary(output)
   if type(output) ~= "string" or output == "" then
      return nil, nil
   end

   local passed = 0
   local total = nil

   for line in output:gmatch("([^\n]+)") do
      local planned = line:match("^1%.%.(%d+)$")
      if planned ~= nil then
         total = tonumber(planned)
      elseif line:match("^ok%s+%d+%s+%-") ~= nil then
         passed = passed + 1
      end
   end

   if total == nil then
      return nil, nil
   end

   return passed, total
end

function M.case(name, fn)
   register_case("case", name, fn)
end

function M.serial(name, fn)
   register_case("serial", name, fn)
end

function M.fail(message)
   if type(message) ~= "string" or message == "" then
      error("test.fail expects a non-empty string message", 0)
   end
   fail_with_message(message)
end

function M.truthy(value, message)
   if value then
      return value
   end

   if message == nil then
      message = "expected a truthy value"
   elseif type(message) ~= "string" or message == "" then
      error("test.truthy expects message to be a non-empty string if provided", 0)
   end

   fail_with_message(message)
end

function M.falsey(value, message)
   if not value then
      return value
   end

   if message == nil then
      message = "expected a falsey value"
   elseif type(message) ~= "string" or message == "" then
      error("test.falsey expects message to be a non-empty string if provided", 0)
   end

   fail_with_message(message)
end

function M.equal(actual, expected, message)
   if actual == expected then
      return actual
   end

   if message ~= nil and (type(message) ~= "string" or message == "") then
      error("test.equal expects message to be a non-empty string if provided", 0)
   end

   local parts = {}
   if message ~= nil then
      table.insert(parts, message)
   else
      table.insert(parts, "expected values to be equal")
   end
   table.insert(parts, "expected: " .. rig.tostring(expected))
   table.insert(parts, "actual:   " .. rig.tostring(actual))
   fail_with_message(table.concat(parts, "\n"))
end

function M.match(value, pattern, message)
   if type(value) ~= "string" then
      error("test.match expects value to be a string", 0)
   end
   if type(pattern) ~= "string" or pattern == "" then
      error("test.match expects pattern to be a non-empty string", 0)
   end
   if message ~= nil and (type(message) ~= "string" or message == "") then
      error("test.match expects message to be a non-empty string if provided", 0)
   end

   if value:match(pattern) ~= nil then
      return value
   end

   local parts = {}
   if message ~= nil then
      table.insert(parts, message)
   else
      table.insert(parts, "expected string to match pattern")
   end
   table.insert(parts, "pattern: " .. pattern)
   table.insert(parts, "value:   " .. rig.tostring(value))
   fail_with_message(table.concat(parts, "\n"))
end

function M.contains_line(value, expected_line, message)
   if type(value) ~= "string" then
      error("test.contains_line expects value to be a string", 0)
   end
   if type(expected_line) ~= "string" or expected_line == "" then
      error("test.contains_line expects expected_line to be a non-empty string", 0)
   end
   if message ~= nil and (type(message) ~= "string" or message == "") then
      error("test.contains_line expects message to be a non-empty string if provided", 0)
   end

   for line in value:gmatch("[^\n]+") do
      if line == expected_line then
         return value
      end
   end

   local parts = {}
   if message ~= nil then
      table.insert(parts, message)
   else
      table.insert(parts, "expected string to contain line")
   end
   table.insert(parts, "expected line: " .. expected_line)
   table.insert(parts, "value:         " .. rig.tostring(value))
   fail_with_message(table.concat(parts, "\n"))
end

function M.fixture(setup, teardown)
   if type(setup) ~= "function" then
      error("test.fixture expects setup to be a function", 0)
   end
   if teardown ~= nil and type(teardown) ~= "function" then
      error("test.fixture expects teardown to be a function if provided", 0)
   end

   return function(body)
      if type(body) ~= "function" then
         error("test.fixture wrapper expects body to be a function", 0)
      end

      return function()
         local resource = setup()
         local ok, body_err = xpcall(function()
            return body(resource)
         end, function(value)
            return tostring(value)
         end)

         local teardown_ok, teardown_err = true, nil
         if teardown ~= nil then
            teardown_ok, teardown_err = xpcall(function()
               teardown(resource)
            end, function(value)
               return tostring(value)
            end)
         end

         if not ok then
            if not teardown_ok then
               error(
                  tostring(body_err)
                     .. "\nfixture teardown also failed:\n"
                     .. tostring(teardown_err),
                  0
               )
            end
            error(body_err, 0)
         end

         if not teardown_ok then
            error("fixture teardown failed:\n" .. tostring(teardown_err), 0)
         end
      end
   end
end

function M.discover(options)
   local opts = options or {}
   if type(opts) ~= "table" then
      error("test.discover expects a table if provided", 0)
   end
   return discover_files(normalize_roots(opts.roots))
end

function M.run(options)
   local opts = options or {}
   if type(opts) ~= "table" then
      error("test.run expects a table if provided", 0)
   end

   local executable = rig.argv[0]
   if type(executable) ~= "string" or executable == "" then
      error("test.run requires rig.argv[0]", 0)
   end

   local roots = normalize_roots(opts.roots)
   local jobs = normalize_jobs(opts.jobs)
   local files = opts.files
   if files == nil then
      files = discover_files(roots)
   elseif type(files) ~= "table" then
      error("test.run expects files to be a table if provided", 0)
   end

   local results = {}
   local started_at = time.monotonic()
   local next_index = 1
   local worker_count = math.min(jobs, #files)
   if worker_count == 0 then
      return {
         files = {},
         passed = 0,
         failed = 0,
         total = 0,
         success = true,
         duration = 0,
      }
   end

   local function worker()
      while true do
         local index = next_index
         next_index = next_index + 1
         local file = files[index]
         if file == nil then
            return
         end

         local file_started_at = time.monotonic()
         local result = uv.spawn {
            file = executable,
            args = { executable, file },
         }
         local duration = time.monotonic() - file_started_at
         local passed_cases, total_cases = parse_tap_summary(result.stdout)

         table.insert(results, {
            file = file,
            success = result.success,
            exit_status = result.exit_status,
            term_signal = result.term_signal,
            stdout = result.stdout,
            stderr = result.stderr,
            duration = duration,
            passed_cases = passed_cases,
            total_cases = total_cases,
         })
      end
   end

   local tasks = {}
   for _ = 1, worker_count do
      table.insert(tasks, sched.spawn(worker))
   end

   sched.join(tasks)

   table.sort(results, function(a, b)
      return a.file < b.file
   end)

   local summary = {
      files = results,
      passed = 0,
      failed = 0,
      total = #results,
    }

   for i = 1, #results do
      if results[i].success then
         summary.passed = summary.passed + 1
      else
         summary.failed = summary.failed + 1
      end
   end
   summary.duration = time.monotonic() - started_at
   summary.success = summary.failed == 0
   return summary
end

function M.run_registered_cases(options)
   local opts = options or {}
   if type(opts) ~= "table" then
      error("test.run_registered_cases expects a table if provided", 0)
   end

   local script_path = opts.script_path
   if not is_test_script_path(script_path) then
      return nil
   end

   local cases = M._registered_cases
   reset_registered_cases()

   if #cases == 0 then
      return {
         cases = {},
         passed = 0,
         failed = 0,
         total = 0,
         success = true,
      }
   end

   local results = {}

   local function run_case(case, index)
      local started_at = time.monotonic()
      local ok, err = xpcall(case.fn, function(value)
         return tostring(value)
      end)
      local duration = time.monotonic() - started_at
      results[index] = {
         name = case.name,
         success = ok,
         err = err,
         serial = case.serial,
         duration = duration,
      }
   end

   local function run_concurrent_batch(batch)
      if #batch == 0 then
         return
      end

      local tasks = {}
      for i = 1, #batch do
         local entry = batch[i]
         table.insert(tasks, sched.spawn(function()
            run_case(entry.case, entry.index)
         end))
      end
      sched.join(tasks)
   end

   rig.run {
      preset = "uv",
      module_config = {
         uv = {
            main = function()
            local concurrent_batch = {}
            for i = 1, #cases do
               local case = cases[i]
               if case.serial then
                  run_concurrent_batch(concurrent_batch)
                  concurrent_batch = {}
                  run_case(case, i)
               else
                  table.insert(concurrent_batch, {
                     case = case,
                     index = i,
                  })
               end
            end
            run_concurrent_batch(concurrent_batch)
            end,
         },
      },
   }

   local summary = {
      cases = results,
      passed = 0,
      failed = 0,
      total = #results,
   }

   rig.println("TAP version 13")
   rig.println("1.." .. tostring(#results))

   for i = 1, #results do
      local result = results[i]
      if result.success then
         summary.passed = summary.passed + 1
         rig.println(
            ("ok %d - %s (%s)"):format(
               i,
               result.name,
               format_duration(result.duration)
            )
         )
      else
         summary.failed = summary.failed + 1
         rig.println(
            ("not ok %d - %s (%s)"):format(
               i,
               result.name,
               format_duration(result.duration)
            )
         )
         rig.println(
            format_multiline(result.err or "unknown test error", "# ")
         )
      end
   end

   summary.success = summary.failed == 0
   if not summary.success then
      error(
         ("test file '%s' failed: %d of %d cases failed"):format(
            script_path,
            summary.failed,
            summary.total
         ),
         0
      )
   end

   return summary
end

return M
