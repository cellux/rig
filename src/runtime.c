#include "runtime.h"

#include <stdio.h>
#include <string.h>

#include <lauxlib.h>

void rig_push_module(lua_State *L, const char *module_name) {
  lua_getglobal(L, module_name);
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    lua_newtable(L);
    lua_pushvalue(L, -1);
    lua_setglobal(L, module_name);
  }
}

int rig_push_module_function(lua_State *L, const char *module_name,
                             const char *function_name) {
  lua_getglobal(L, module_name);
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    lua_pushfstring(L, "global '%s' module is not available", module_name);
    return -1;
  }

  lua_getfield(L, -1, function_name);
  lua_remove(L, -2);
  if (!lua_isfunction(L, -1)) {
    lua_pop(L, 1);
    lua_pushfstring(L, "%s.%s is not available", module_name, function_name);
    return -1;
  }

  return 0;
}

int rig_invoke_module_function(lua_State *L, const char *module_name,
                               const char *function_name) {
  int nargs = lua_gettop(L);

  if (rig_push_module_function(L, module_name, function_name) != 0) {
    if (nargs > 0) {
      lua_pop(L, nargs);
    }
    return -1;
  }

  if (nargs > 0) {
    lua_insert(L, -1 - nargs);
  }

  if (lua_pcall(L, nargs, 0, 0) != LUA_OK) {
    return -1;
  }

  return 0;
}

static int rig_execute_module_chunk(lua_State *L, const rig_module_desc *module,
                                    const unsigned char *bytecode,
                                    const size_t *bytecode_len,
                                    const char *chunk_extension,
                                    const char *source_label,
                                    int top_with_context) {
  char chunk_name[128];
  size_t len = *bytecode_len;

  (void)snprintf(chunk_name, sizeof(chunk_name), "@rig/%s.%s", module->name,
                 chunk_extension);

  if (luaL_loadbuffer(L, (const char *)bytecode, len, chunk_name) != LUA_OK) {
    return -1;
  }

  lua_pushvalue(L, -2);
  if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
    return -1;
  }

  if (!lua_istable(L, -1)) {
    return luaL_error(L, "module '%s' %s chunk must return a table",
                      module->name, source_label);
  }

  lua_pushvalue(L, -1);
  lua_setglobal(L, module->name);
  lua_replace(L, -2);

  if (lua_gettop(L) != top_with_context) {
    return luaL_error(L,
                      "internal error: %s module '%s' changed stack depth "
                      "(expected %d, got %d)",
                      source_label, module->name, top_with_context,
                      lua_gettop(L));
  }

  return 0;
}

static int rig_find_module(const char *module_name,
                           const rig_module_desc **out_module) {
  size_t i;

  for (i = 0; i < rig_module_count; ++i) {
    if (strcmp(rig_modules[i].name, module_name) == 0) {
      *out_module = &rig_modules[i];
      return 0;
    }
  }

  return -1;
}

static int rig_load_module(lua_State *L, const rig_module_desc *module) {
  int top_before = lua_gettop(L);

  rig_push_module(L, module->name);

  int top_with_context = lua_gettop(L);
  if (top_with_context != top_before + 1) {
    return luaL_error(
        L, "internal error: failed to prepare module context for '%s'",
        module->name);
  }

  if (module->register_fn != NULL) {
    module->register_fn(L);
    if (lua_gettop(L) != top_with_context) {
      return luaL_error(L,
                        "internal error: C module '%s' changed stack depth "
                        "(expected %d, got %d)",
                        module->name, top_with_context, lua_gettop(L));
    }
  }

  if (module->lua_bytecode != NULL && module->lua_bytecode_len != NULL) {
    if (rig_execute_module_chunk(L, module, module->lua_bytecode,
                                 module->lua_bytecode_len, "lua", "Lua",
                                 top_with_context) != 0) {
      return -1;
    }
  }

  if (module->fennel_bytecode != NULL && module->fennel_bytecode_len != NULL) {
    if (rig_execute_module_chunk(L, module, module->fennel_bytecode,
                                 module->fennel_bytecode_len, "fnl", "Fennel",
                                 top_with_context) != 0) {
      return -1;
    }
  }

  lua_getglobal(L, "package");
  if (!lua_istable(L, -1)) {
    return luaL_error(L,
                      "internal error: global 'package' library is not available");
  }
  lua_getfield(L, -1, "loaded");
  lua_remove(L, -2);
  if (!lua_istable(L, -1)) {
    return luaL_error(L,
                      "internal error: package.loaded is not available");
  }
  lua_pushvalue(L, -2);
  lua_setfield(L, -2, module->name);
  lua_pop(L, 1);

  if (lua_gettop(L) != top_before + 1) {
    return luaL_error(L,
                      "internal error: module loader stack leak for '%s' "
                      "(expected %d, got %d)",
                      module->name, top_before + 1, lua_gettop(L));
  }

  if (!lua_istable(L, -1)) {
    return luaL_error(L, "internal error: loaded module '%s' is not a table",
                      module->name);
  }

  if (top_before != 0) {
    lua_insert(L, top_before + 1);
  }

  if (lua_gettop(L) != top_before + 1) {
    return luaL_error(L, "internal error: module loader stack leak for '%s'",
                      module->name);
  }

  return 0;
}

static int rig_preload_module(lua_State *L) {
  const rig_module_desc *module =
      (const rig_module_desc *)lua_touserdata(L, lua_upvalueindex(1));

  if (module == NULL) {
    return luaL_error(L, "internal error: missing module preload descriptor");
  }

  if (rig_load_module(L, module) != 0) {
    return lua_error(L);
  }

  return 1;
}

int rig_register_preloaded_modules(lua_State *L) {
  int top_before = lua_gettop(L);
  size_t i;

  lua_getglobal(L, "package");
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    lua_pushliteral(L, "global 'package' library is not available");
    return -1;
  }

  lua_getfield(L, -1, "preload");
  lua_remove(L, -2);
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    lua_pushliteral(L, "package.preload is not available");
    return -1;
  }

  for (i = 0; i < rig_module_count; ++i) {
    lua_pushlightuserdata(L, (void *)&rig_modules[i]);
    lua_pushcclosure(L, rig_preload_module, 1);
    lua_setfield(L, -2, rig_modules[i].name);
  }

  lua_pop(L, 1);
  if (lua_gettop(L) != top_before) {
    lua_pushliteral(L,
                    "internal error: preload registration changed stack depth");
    return -1;
  }

  return 0;
}

int rig_require_module(lua_State *L, const char *module_name) {
  const rig_module_desc *module = NULL;

  if (rig_find_module(module_name, &module) != 0) {
    lua_pushfstring(L, "unknown rig module '%s'", module_name);
    return -1;
  }

  lua_getglobal(L, "require");
  if (!lua_isfunction(L, -1)) {
    lua_pop(L, 1);
    lua_pushliteral(L, "global 'require' function is not available");
    return -1;
  }

  lua_pushstring(L, module->name);
  if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
    return -1;
  }

  lua_pop(L, 1);
  return 0;
}
