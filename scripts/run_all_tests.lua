local test = require("test")

local function format_duration(duration)
   return string.format("%.3f ms", duration * 1000.0)
end

local function format_file_status(ok, index, summary, result)
   local passed = result.passed_cases
   local total = result.total_cases
   if type(passed) ~= "number" or type(total) ~= "number" then
      passed = summary.passed
      total = summary.total
   end

   return string.format(
      "%s %d - [%d/%d] %s (%s)",
      ok and "ok" or "not ok",
      index,
      passed,
      total,
      result.file,
      format_duration(result.duration)
   )
end

local function print_diagnostics(label, text)
   rig.println("# " .. label .. ":")
   for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
      rig.println("# " .. line)
   end
end

local function print_failure(index, summary, result)
   rig.println(format_file_status(false, index, summary, result))
   if result.stdout ~= "" then
      print_diagnostics("stdout", result.stdout)
   end
   if result.stderr ~= "" then
      print_diagnostics("stderr", result.stderr)
   end
end

rig.run {
   preset = "uv",
   module_config = {
      uv = {
         main = function()
        local summary = test.run {
            roots = { "tests" },
            jobs = 4,
        }

         rig.println("TAP version 13")
         rig.println("1.." .. tostring(#summary.files))

         for i = 1, #summary.files do
            local result = summary.files[i]
            if result.success then
               rig.println(format_file_status(true, i, summary, result))
            else
               print_failure(i, summary, result)
            end
         end

         rig.println(
            ("# Summary: %d passed, %d failed, %d total (%s)"):
               format(
                  summary.passed,
                  summary.failed,
                  summary.total,
                  format_duration(summary.duration)
               )
         )

         if not summary.success then
            error("test run failed", 0)
         end
         end,
      },
   },
}
