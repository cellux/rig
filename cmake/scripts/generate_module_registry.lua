local module_list_path = arg[1]
local module_dir = arg[2]
local output_path = arg[3]

local function fail(fmt, ...)
  io.stderr:write(string.format(fmt .. "\n", ...))
  os.exit(1)
end

if module_list_path == nil or module_dir == nil or output_path == nil then
  fail("usage: luajit generate_module_registry.lua <modules.txt> <module-dir> <output.c>")
end

local function read_lines(path)
  local f, err = io.open(path, "rb")
  if f == nil then
    fail("failed to open '%s': %s", path, tostring(err))
  end

  local lines = {}
  for line in f:lines() do
    table.insert(lines, line)
  end
  f:close()
  return lines
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function exists(path)
  local f = io.open(path, "rb")
  if f ~= nil then
    f:close()
    return true
  end
  return false
end

local function join_path(base, leaf)
  if base:sub(-1) == "/" then
    return base .. leaf
  end
  return base .. "/" .. leaf
end

local names = {}
for _, raw in ipairs(read_lines(module_list_path)) do
  local name = trim(raw)
  if name ~= "" and not name:match("^#") then
    table.insert(names, name)
  end
end

if #names == 0 then
  fail("no modules were found in %s", module_list_path)
end

local prototypes = {}
local externs = {}
local entries = {}

for _, name in ipairs(names) do
  local c_path = join_path(module_dir, name .. ".c")
  local lua_path = join_path(module_dir, name .. ".lua")
  local fnl_path = join_path(module_dir, name .. ".fnl")

  local has_c = exists(c_path)
  local has_lua = exists(lua_path)
  local has_fnl = exists(fnl_path)

  if not has_c and not has_lua and not has_fnl then
    fail(
      "module '%s' is listed but none of %s, %s, or %s exists",
      name,
      c_path,
      lua_path,
      fnl_path
    )
  end

  local register_fn = "NULL"
  if has_c then
    table.insert(prototypes, string.format("void rig_register_%s(lua_State *L);", name))
    register_fn = string.format("rig_register_%s", name)
  end

  local lua_bytecode = "NULL"
  local lua_bytecode_len = "NULL"
  if has_lua then
    table.insert(externs, string.format(
      "extern const unsigned char rig_lua_module_%s_bytecode[];",
      name
    ))
    table.insert(externs, string.format(
      "extern const size_t rig_lua_module_%s_bytecode_len;",
      name
    ))
    lua_bytecode = string.format("rig_lua_module_%s_bytecode", name)
    lua_bytecode_len = string.format("&rig_lua_module_%s_bytecode_len", name)
  end

  local fnl_bytecode = "NULL"
  local fnl_bytecode_len = "NULL"
  if has_fnl then
    table.insert(externs, string.format(
      "extern const unsigned char rig_fennel_module_%s_bytecode[];",
      name
    ))
    table.insert(externs, string.format(
      "extern const size_t rig_fennel_module_%s_bytecode_len;",
      name
    ))
    fnl_bytecode = string.format("rig_fennel_module_%s_bytecode", name)
    fnl_bytecode_len = string.format("&rig_fennel_module_%s_bytecode_len", name)
  end

  table.insert(entries, string.format(
    '    { "%s", %s, %s, %s, %s, %s },',
    name,
    register_fn,
    lua_bytecode,
    lua_bytecode_len,
    fnl_bytecode,
    fnl_bytecode_len
  ))
end

local out = {}
table.insert(out, "/* Generated file. Do not edit. */")
table.insert(out, "#include <stddef.h>")
table.insert(out, "#include <lua.h>")
table.insert(out, "")
table.insert(out, "#include \"runtime.h\"")
table.insert(out, "")

for _, line in ipairs(prototypes) do
  table.insert(out, line)
end
if #prototypes > 0 then
  table.insert(out, "")
end

for _, line in ipairs(externs) do
  table.insert(out, line)
end
if #externs > 0 then
  table.insert(out, "")
end

table.insert(out, "const rig_module_desc rig_modules[] = {")
for _, line in ipairs(entries) do
  table.insert(out, line)
end
table.insert(out, "};")
table.insert(out, "const size_t rig_module_count = (sizeof(rig_modules) / sizeof(rig_modules[0]));")
table.insert(out, "")

local output_file, out_err = io.open(output_path, "wb")
if output_file == nil then
  fail("failed to open '%s': %s", output_path, tostring(out_err))
end
output_file:write(table.concat(out, "\n"))
output_file:close()
