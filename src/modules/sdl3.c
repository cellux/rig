#include <SDL3/SDL.h>

#include <lauxlib.h>
#include <lua.h>

static Uint8 color_component_from_lua(lua_State *L, int index,
                                      double default_value) {
  double value = luaL_optnumber(L, index, default_value);
  if (value < 0.0) {
    value = 0.0;
  }
  if (value > 1.0) {
    value = 1.0;
  }
  return (Uint8)(value * 255.0);
}

static int sdl3_clear(lua_State *L) {
  SDL_Renderer *renderer = NULL;
  Uint8 r;
  Uint8 g;
  Uint8 b;
  Uint8 a;

  lua_getglobal(L, "sdl3");
  if (lua_istable(L, -1)) {
    lua_getfield(L, -1, "renderer");
    if (lua_islightuserdata(L, -1)) {
      renderer = (SDL_Renderer *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);
  }
  lua_pop(L, 1);

  if (renderer == NULL) {
    return luaL_error(L, "sdl3.clear can only be called during on_render callback");
  }

  r = color_component_from_lua(L, 1, 0.0);
  g = color_component_from_lua(L, 2, 0.0);
  b = color_component_from_lua(L, 3, 0.0);
  a = color_component_from_lua(L, 4, 1.0);

  if (!SDL_SetRenderDrawColor(renderer, r, g, b, a)) {
    return luaL_error(L, "failed to set draw color: %s", SDL_GetError());
  }
  if (!SDL_RenderClear(renderer)) {
    return luaL_error(L, "failed to clear render target: %s", SDL_GetError());
  }

  return 0;
}

void rig_register_sdl3(lua_State *L) {
  lua_pushcfunction(L, sdl3_clear);
  lua_setfield(L, -2, "clear");
}
