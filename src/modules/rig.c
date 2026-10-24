#if !defined(_WIN32)
#define _GNU_SOURCE
#endif

#include <lua.h>
#include <lauxlib.h>

#include <errno.h>
#include <string.h>

#if defined(_WIN32)
#include <direct.h>
#include <stdlib.h>
#else
#include <limits.h>
#include <stdlib.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#endif

static int rig_realpath(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);

#if defined(_WIN32)
  char resolved[_MAX_PATH];
  if (_fullpath(resolved, path, sizeof(resolved)) == NULL) {
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return 2;
  }

  lua_pushstring(L, resolved);
  return 1;
#else
  char resolved[PATH_MAX];
  if (realpath(path, resolved) == NULL) {
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return 2;
  }

  lua_pushstring(L, resolved);
  return 1;
#endif
}

void rig_register_rig(lua_State *L) {
  lua_pushcfunction(L, rig_realpath);
  lua_setfield(L, -2, "realpath");
}