local source_path = arg[1]
local output_path = arg[2]
local symbol = arg[3]
local chunk_name = arg[4]
local fennel_module_source = arg[5]
local luajit_bin = arg[6]
local ffi = require("ffi")

ffi.cdef([[
  typedef int pid_t;
  pid_t fork(void);
  int execvp(const char *file, char *const argv[]);
  pid_t waitpid(pid_t pid, int *status, int options);
  int unlink(const char *pathname);
  void _exit(int status);
]])

local function fail(fmt, ...)
  io.stderr:write(string.format(fmt .. "\n", ...))
  os.exit(1)
end

if source_path == nil or output_path == nil or symbol == nil or chunk_name == nil or fennel_module_source == nil or luajit_bin == nil then
  fail(
    "usage: luajit build_embedded_module.lua <source.{lua,fnl}> <output.c> <symbol> <chunk-name> <fennel.lua> <luajit-bin>"
  )
end

local function read_all(path)
  local f, err = io.open(path, "rb")
  if f == nil then
    fail("failed to open '%s': %s", path, err)
  end

  local content = f:read("*all")
  f:close()
  if content == nil then
    fail("failed to read '%s'", path)
  end
  return content
end

local function run_process(argv)
  local c_argv_keepalive = {}
  local c_argv = ffi.new("char *[?]", #argv + 1)
  for i = 1, #argv do
    c_argv_keepalive[i] = ffi.new("char[?]", #argv[i] + 1, argv[i])
    c_argv[i - 1] = c_argv_keepalive[i]
  end
  c_argv[#argv] = nil

  local pid = ffi.C.fork()
  if pid < 0 then
    fail("fork failed while running '%s'", argv[1])
  end

  if pid == 0 then
    ffi.C.execvp(c_argv_keepalive[1], c_argv)
    ffi.C._exit(127)
  end

  local status = ffi.new("int[1]")
  while true do
    local waited = ffi.C.waitpid(pid, status, 0)
    if waited == pid then
      break
    end
    if waited < 0 then
      fail("waitpid failed while running '%s'", argv[1])
    end
  end

  local raw = tonumber(status[0])
  local exited_normally = (raw % 128) == 0
  local exit_code = math.floor(raw / 256) % 256
  if not exited_normally or exit_code ~= 0 then
    fail("command failed: %s (status=%d)", table.concat(argv, " "), raw)
  end
end

local function cleanup_file(path)
  ffi.C.unlink(path)
end

local function write_all(path, content)
  local f, err = io.open(path, "wb")
  if f == nil then
    fail("failed to open '%s': %s", path, err)
  end
  f:write(content)
  f:close()
end

local function load_fennel_module(path)
  local chunk, load_err = loadfile(path)
  if chunk == nil then
    fail("failed to load fennel module '%s': %s", path, load_err)
  end

  local fennel = chunk()
  if type(fennel) ~= "table" or type(fennel.compileString) ~= "function" then
    fail("'%s' did not return a usable fennel module", path)
  end

  package.loaded["fennel"] = fennel
  return fennel
end

local function to_lua_source(source, ext)
  if ext == "lua" then
    return source
  end
  if ext ~= "fnl" then
    fail("unsupported source extension '%s' for '%s'", ext, source_path)
  end

  local fennel = load_fennel_module(fennel_module_source)
  local ok, lua_source = pcall(fennel.compileString, source, {filename = source_path})
  if not ok then
    fail("failed to compile fennel '%s': %s", source_path, lua_source)
  end
  if type(lua_source) ~= "string" then
    fail("compiler returned non-string output for '%s'", source_path)
  end
  return lua_source
end

local function build_bytecode(lua_source)
  local temp_lua_path = output_path .. ".tmp.lua"
  local bytecode_path = output_path .. ".tmp.ljbc"

  write_all(temp_lua_path, lua_source)
  run_process({luajit_bin, "-b", temp_lua_path, bytecode_path})

  local bytecode = read_all(bytecode_path)
  cleanup_file(bytecode_path)
  cleanup_file(temp_lua_path)
  return bytecode
end

local function emit_c_source(bytecode)
  local lines = {
    "/* Generated file. Do not edit. */",
    "#include <stddef.h>",
    "",
    string.format("const unsigned char %s[] = {", symbol),
  }

  local columns = 0
  local current = {}
  for i = 1, #bytecode do
    table.insert(current, string.format("0x%02x, ", bytecode:byte(i)))
    columns = columns + 1
    if columns == 12 then
      table.insert(lines, table.concat(current))
      current = {}
      columns = 0
    end
  end

  if #current > 0 then
    table.insert(lines, table.concat(current))
  end

  table.insert(lines, "};")
  table.insert(lines, string.format("const size_t %s_len = %d;", symbol, #bytecode))
  table.insert(lines, "")
  return table.concat(lines, "\n")
end

local ext = source_path:match("%.([^.]+)$")
if ext == nil then
  fail("source file has no extension: '%s'", source_path)
end

local source = read_all(source_path)
local lua_source = to_lua_source(source, ext)
local bytecode = build_bytecode(lua_source)
local c_source = emit_c_source(bytecode)
write_all(output_path, c_source)
