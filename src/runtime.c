#include "runtime.h"

#include <stdio.h>

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

int rig_push_global_handler(lua_State *L, const char *handler_name) {
  lua_getglobal(L, handler_name);
  if (lua_isfunction(L, -1)) {
    return 1;
  }
  lua_pop(L, 1);
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

    lua_pushvalue(L, -2);

    if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
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
