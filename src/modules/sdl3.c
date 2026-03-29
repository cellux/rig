#include <SDL3/SDL.h>

#include <lua.h>
#include <lauxlib.h>

#include "runtime.h"

#define RIG_REGKEY_SDL3_RENDERER "sdl3.renderer"

static int sdl3_create_window(lua_State *L) {
  const char *title = luaL_optstring(L, 1, "rig");
  int width = (int)luaL_optinteger(L, 2, 640);
  int height = (int)luaL_optinteger(L, 3, 360);
  SDL_WindowFlags flags = (SDL_WindowFlags)(Uint64)luaL_optinteger(L, 4, 0);
  SDL_Window *window = SDL_CreateWindow(title, width, height, flags);

  if (window == NULL) {
    lua_pushnil(L);
    lua_pushstring(L, SDL_GetError());
    return 2;
  }

  lua_pushlightuserdata(L, window);
  lua_pushnil(L);
  return 2;
}

static int sdl3_create_renderer(lua_State *L) {
  SDL_Window *window;
  const char *name = NULL;
  SDL_Renderer *renderer;

  if (!lua_islightuserdata(L, 1)) {
    return luaL_error(L, "sdl3.create_renderer expects window lightuserdata");
  }
  window = (SDL_Window *)lua_touserdata(L, 1);

  if (!lua_isnoneornil(L, 2)) {
    name = luaL_checkstring(L, 2);
  }

  renderer = SDL_CreateRenderer(window, name);
  if (renderer == NULL) {
    lua_pushnil(L);
    lua_pushstring(L, SDL_GetError());
    return 2;
  }

  lua_pushlightuserdata(L, renderer);
  lua_pushnil(L);
  return 2;
}

static int sdl3_set_render_vsync(lua_State *L) {
  SDL_Renderer *renderer;
  int enabled;

  if (!lua_islightuserdata(L, 1)) {
    return luaL_error(L, "sdl3.set_render_vsync expects renderer lightuserdata");
  }
  renderer = (SDL_Renderer *)lua_touserdata(L, 1);
  enabled = lua_toboolean(L, 2) ? 1 : 0;

  if (!SDL_SetRenderVSync(renderer, enabled)) {
    lua_pushboolean(L, 0);
    lua_pushstring(L, SDL_GetError());
    return 2;
  }

  lua_pushboolean(L, 1);
  lua_pushnil(L);
  return 2;
}

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
  lua_pushcfunction(L, sdl3_create_window);
  lua_setfield(L, -2, "create_window");

  lua_pushcfunction(L, sdl3_create_renderer);
  lua_setfield(L, -2, "create_renderer");

  lua_pushcfunction(L, sdl3_set_render_vsync);
  lua_setfield(L, -2, "set_render_vsync");

  lua_pushcfunction(L, sdl3_get_renderer);
  lua_setfield(L, -2, "get_renderer");
}
