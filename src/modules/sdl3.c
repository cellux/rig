#include <SDL3/SDL.h>

#include <lauxlib.h>
#include <lua.h>

#include "runtime.h"

static SDL_Renderer *g_active_renderer = NULL;

static Uint8 color_component_from_lua(lua_State *L, int index, double default_value) {
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
  Uint8 r;
  Uint8 g;
  Uint8 b;
  Uint8 a;

  if (g_active_renderer == NULL) {
    return luaL_error(L, "sdl3.clear can only be called during sdl3.loop render callback");
  }

  r = color_component_from_lua(L, 1, 0.0);
  g = color_component_from_lua(L, 2, 0.0);
  b = color_component_from_lua(L, 3, 0.0);
  a = color_component_from_lua(L, 4, 1.0);

  if (!SDL_SetRenderDrawColor(g_active_renderer, r, g, b, a)) {
    return luaL_error(L, "failed to set draw color: %s", SDL_GetError());
  }
  if (!SDL_RenderClear(g_active_renderer)) {
    return luaL_error(L, "failed to clear render target: %s", SDL_GetError());
  }

  return 0;
}

static void push_key_info(lua_State *L, const SDL_KeyboardEvent *key_event) {
  const char *action_text = "up";
  const char *key_text;
  SDL_Keymod mods;

  if (key_event->down) {
    action_text = "down";
  }

  key_text = SDL_GetKeyName(key_event->key);
  if (key_text == NULL || key_text[0] == '\0') {
    key_text = "Unknown";
  }
  mods = key_event->mod;

  lua_newtable(L);

  lua_pushliteral(L, "type");
  lua_pushliteral(L, "key");
  lua_rawset(L, -3);

  lua_pushliteral(L, "action");
  lua_pushstring(L, action_text);
  lua_rawset(L, -3);

  lua_pushliteral(L, "key");
  lua_pushstring(L, key_text);
  lua_rawset(L, -3);

  lua_pushliteral(L, "code");
  lua_pushinteger(L, key_event->key);
  lua_rawset(L, -3);

  lua_pushliteral(L, "scancode");
  lua_pushinteger(L, key_event->scancode);
  lua_rawset(L, -3);

  lua_pushliteral(L, "repeat");
  lua_pushboolean(L, key_event->repeat);
  lua_rawset(L, -3);

  lua_pushliteral(L, "timestamp_ms");
  lua_pushinteger(L, key_event->timestamp);
  lua_rawset(L, -3);

  lua_pushliteral(L, "mods");
  lua_newtable(L);
  lua_pushliteral(L, "shift");
  lua_pushboolean(L, (mods & SDL_KMOD_SHIFT) != 0);
  lua_rawset(L, -3);
  lua_pushliteral(L, "ctrl");
  lua_pushboolean(L, (mods & SDL_KMOD_CTRL) != 0);
  lua_rawset(L, -3);
  lua_pushliteral(L, "alt");
  lua_pushboolean(L, (mods & SDL_KMOD_ALT) != 0);
  lua_rawset(L, -3);
  lua_pushliteral(L, "super");
  lua_pushboolean(L, (mods & SDL_KMOD_GUI) != 0);
  lua_rawset(L, -3);
  lua_rawset(L, -3);
}

static int dispatch_key_event(lua_State *L, const SDL_KeyboardEvent *key_event) {
  if (!rig_push_global_handler(L, "on_key")) {
    return 0;
  }

  push_key_info(L, key_event);
  if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
    return -1;
  }

  return 0;
}

static int dispatch_render(lua_State *L) {
  if (!rig_push_global_handler(L, "on_render")) {
    return 0;
  }

  if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
    return -1;
  }

  return 0;
}

static int sdl3_loop(lua_State *L) {
  SDL_Window *window;
  SDL_Renderer *renderer;
  int running = 1;
  Uint32 required = SDL_INIT_VIDEO | SDL_INIT_EVENTS;

  if ((SDL_WasInit(required) & required) != required) {
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
      return luaL_error(L, "failed to initialize SDL: %s", SDL_GetError());
    }
  }

  window = SDL_CreateWindow("rig", 640, 360, 0);
  if (window == NULL) {
    return luaL_error(L, "failed to create window: %s", SDL_GetError());
  }

  renderer = SDL_CreateRenderer(window, NULL);
  if (renderer == NULL) {
    SDL_DestroyWindow(window);
    return luaL_error(L, "failed to create renderer: %s", SDL_GetError());
  }

  (void)SDL_SetRenderVSync(renderer, 1);

  g_active_renderer = renderer;
  while (running) {
    SDL_Event event;

    while (SDL_PollEvent(&event)) {
      if (event.type == SDL_EVENT_QUIT) {
        running = 0;
        break;
      }

      if (event.type == SDL_EVENT_KEY_DOWN || event.type == SDL_EVENT_KEY_UP) {
        if (dispatch_key_event(L, &event.key) != 0) {
          g_active_renderer = NULL;
          SDL_DestroyRenderer(renderer);
          SDL_DestroyWindow(window);
          return lua_error(L);
        }
      }
    }

    if (dispatch_render(L) != 0) {
      g_active_renderer = NULL;
      SDL_DestroyRenderer(renderer);
      SDL_DestroyWindow(window);
      return lua_error(L);
    }

    if (!SDL_RenderPresent(renderer)) {
      g_active_renderer = NULL;
      SDL_DestroyRenderer(renderer);
      SDL_DestroyWindow(window);
      return luaL_error(L, "failed to present renderer: %s", SDL_GetError());
    }
  }

  g_active_renderer = NULL;
  SDL_DestroyRenderer(renderer);
  SDL_DestroyWindow(window);
  return 0;
}

void rig_register_sdl3(lua_State *L) {
  lua_pushcfunction(L, sdl3_clear);
  lua_setfield(L, -2, "clear");
  lua_pushcfunction(L, sdl3_loop);
  lua_setfield(L, -2, "loop");
}
