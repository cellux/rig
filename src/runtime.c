#include "runtime.h"

#include <stdio.h>

#include <lauxlib.h>

static char rig_registry_namespace_key;

static void rig_push_registry_table(lua_State *L) {
  lua_pushlightuserdata(L, (void *)&rig_registry_namespace_key);
  lua_rawget(L, LUA_REGISTRYINDEX);
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    lua_newtable(L);
    lua_pushlightuserdata(L, (void *)&rig_registry_namespace_key);
    lua_pushvalue(L, -2);
    lua_rawset(L, LUA_REGISTRYINDEX);
  }
}

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

void rig_remove_global(lua_State *L, const char *name) {
  lua_pushnil(L);
  lua_setglobal(L, name);
}

void rig_registry_set_lightuserdata(lua_State *L, const char *key,
                                    void *value) {
  rig_push_registry_table(L);
  lua_pushstring(L, key);
  if (value == NULL) {
    lua_pushnil(L);
  } else {
    lua_pushlightuserdata(L, value);
  }
  lua_rawset(L, -3);
  lua_pop(L, 1);
}

void *rig_registry_get_lightuserdata(lua_State *L, const char *key) {
  void *value = NULL;

  rig_push_registry_table(L);
  lua_pushstring(L, key);
  lua_rawget(L, -2);
  if (lua_islightuserdata(L, -1)) {
    value = lua_touserdata(L, -1);
  }
  lua_pop(L, 2);

  return value;
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

  lua_pop(L, 1);
  if (lua_gettop(L) != top_before) {
    return luaL_error(L, "internal error: module loader stack leak for '%s'",
                      module->name);
  }

  return 0;
}

int rig_init_modules(lua_State *L) {
  for (size_t i = 0; i < rig_module_count; ++i) {
    if (rig_load_module(L, &rig_modules[i]) != 0) {
      return -1;
    }
  }

  return 0;
}
