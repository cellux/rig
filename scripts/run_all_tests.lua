local test = require("test")

local function format_duration(duration)
   return string.format("%.3f ms", duration * 1000.0)
end

local function format_file_status(prefix, summary, result)
   local passed = result.passed_cases
   local total = result.total_cases
   if type(passed) ~= "number" or type(total) ~= "number" then
      passed = summary.passed
      total = summary.total
   end

   return string.format(
      "%s [%d/%d] %s (%s)",
      prefix,
      passed,
      total,
      result.file,
      format_duration(result.duration)
   )
end

local function print_failure(summary, result)
   rig.println(format_file_status("FAIL", summary, result))
   if result.stdout ~= "" then
      rig.println("stdout:")
      io.write(result.stdout)
      if result.stdout:sub(-1) ~= "\n" then
         io.write("\n")
      end
   end
   if result.stderr ~= "" then
      rig.println("stderr:")
      io.write(result.stderr)
      if result.stderr:sub(-1) ~= "\n" then
         io.write("\n")
      end
   end
end

rig.run {
   mode = "uv",
   uv = {
      main = function()
         local summary = test.run {
            roots = { "tests" },
            jobs = 4,
         }

         for i = 1, #summary.files do
            local result = summary.files[i]
            if result.success then
               rig.println(format_file_status("PASS", summary, result))
            else
               print_failure(summary, result)
            end
         end

         rig.println(
            ("Summary: %d passed, %d failed, %d total (%s)"):
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
}
