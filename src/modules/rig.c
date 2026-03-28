#include <stdio.h>

#include <lauxlib.h>
#include <lua.h>

#include "runtime.h"

static int rig_print(lua_State *L) {
  int argc = lua_gettop(L);
  int i;

  rig_push_module(L, "rig");
  lua_getfield(L, -1, "tostring");
  if (!lua_isfunction(L, -1)) {
    lua_pop(L, 1);
    lua_getglobal(L, "tostring");
  }
  lua_remove(L, -2);

  for (i = 1; i <= argc; ++i) {
    lua_pushvalue(L, -1);
    lua_pushvalue(L, i);

    if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
      return lua_error(L);
    }
    if (!lua_isstring(L, -1)) {
      lua_pop(L, 1);
      return luaL_error(L, "'tostring' must return a string to 'rig.print'");
    }

    fputs(lua_tostring(L, -1), stdout);
    lua_pop(L, 1);

    if (i != argc) {
      fputc(' ', stdout);
    }
  }

  lua_pop(L, 1);
  fflush(stdout);
  return 0;
}

static int rig_println(lua_State *L) {
  if (rig_print(L) != 0) {
    return lua_error(L);
  }

  fputc('\n', stdout);
  fflush(stdout);
  return 0;
}

void rig_register_rig(lua_State *L) {
  lua_pushcfunction(L, rig_print);
  lua_setfield(L, -2, "print");
  lua_pushcfunction(L, rig_println);
  lua_setfield(L, -2, "println");
}
