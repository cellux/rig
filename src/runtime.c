#include "runtime.h"

#include <stdio.h>

#include <lauxlib.h>

static int abs_index(lua_State *L, int index) {
  if (index > 0 || index <= LUA_REGISTRYINDEX) {
    return index;
  }
  return lua_gettop(L) + index + 1;
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

int rig_has_global_function(lua_State *L, const char *name) {
  int is_fn;

  lua_getglobal(L, name);
  is_fn = lua_isfunction(L, -1);
  lua_pop(L, 1);
  return is_fn;
}

int rig_push_global_function(lua_State *L, const char *function_name) {
  lua_getglobal(L, function_name);
  if (lua_isfunction(L, -1)) {
    return 1;
  }
  lua_pop(L, 1);
  return 0;
}

static int rig_set_chunk_env_to_module(lua_State *L, int chunk_index,
                                       int module_index,
                                       const char *module_name) {
  int abs_chunk_index = abs_index(L, chunk_index);
  int abs_module_index = abs_index(L, module_index);
  int has_index;

  lua_pushvalue(L, abs_module_index);
  if (!lua_getmetatable(L, -1)) {
    lua_newtable(L);
  }

  lua_getfield(L, -1, "__index");
  has_index = !lua_isnil(L, -1);
  lua_pop(L, 1);
  if (!has_index) {
    lua_pushliteral(L, "__index");
    lua_getglobal(L, "_G");
    lua_rawset(L, -3);
  }

  lua_setmetatable(L, -2);
  if (!lua_setfenv(L, abs_chunk_index)) {
    lua_pop(L, 1);
    return luaL_error(L,
                      "internal error: failed to set environment for module '%s'",
                      module_name);
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

  if (module->bytecode != NULL && module->bytecode_len != NULL) {
    char chunk_name[128];
    size_t bytecode_len = *module->bytecode_len;

    (void)snprintf(chunk_name, sizeof(chunk_name), "@rig/%s.lua", module->name);

    if (luaL_loadbuffer(L, (const char *)module->bytecode, bytecode_len,
                        chunk_name) != LUA_OK) {
      return -1;
    }

    if (rig_set_chunk_env_to_module(L, -1, -2, module->name) != 0) {
      return -1;
    }

    if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
      return -1;
    }

    if (lua_gettop(L) != top_with_context) {
      return luaL_error(L,
                        "internal error: Lua module '%s' changed stack depth "
                        "(expected %d, got %d)",
                        module->name, top_with_context, lua_gettop(L));
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
