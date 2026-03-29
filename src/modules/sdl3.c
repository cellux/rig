#include <lua.h>

#include "runtime.h"

#define RIG_REGKEY_SDL3_RENDERER "sdl3.renderer"

static int sdl3_get_renderer(lua_State *L) {
  void *renderer_userdata =
      rig_registry_get_lightuserdata(L, RIG_REGKEY_SDL3_RENDERER);
  if (renderer_userdata == NULL) {
    lua_pushnil(L);
  } else {
    lua_pushlightuserdata(L, renderer_userdata);
  }
  return 1;
}

void rig_register_sdl3(lua_State *L) {
  lua_pushcfunction(L, sdl3_get_renderer);
  lua_setfield(L, -2, "get_renderer");
}
