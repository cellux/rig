#include <stdio.h>
#include <string.h>

#define SDL_MAIN_USE_CALLBACKS
#include <SDL3/SDL_main.h>
#include <SDL3/SDL.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "runtime.h"

typedef struct rig_app_state {
  lua_State *L;
  int has_render_handler;
} rig_app_state;

static void print_usage(const char *argv0) {
  fprintf(stderr, "Usage: %s <scriptfile>\n", argv0);
}

static SDL_AppResult report_lua_error(lua_State *L, const char *context) {
  const char *msg = lua_tostring(L, -1);
  fprintf(stderr, "%s: %s\n", context, msg ? msg : "unknown error");
  lua_pop(L, 1);
  return SDL_APP_FAILURE;
}

static int dispatch_keyboard_event(lua_State *L,
                                   const SDL_KeyboardEvent *key_event) {
  lua_pushlightuserdata(L, (void *)key_event);
  return rig_invoke_module_function(L, "sdl3", "_dispatch_keyboard_event");
}

static int dispatch_render(lua_State *L) {
  return rig_invoke_module_function(L, "sdl3", "_dispatch_render");
}

static int present_render(lua_State *L) {
  return rig_invoke_module_function(L, "sdl3", "_present");
}

static void ensure_hooks_table(lua_State *L) {
  lua_getglobal(L, "hooks");
  if (lua_istable(L, -1)) {
    lua_pop(L, 1);
    return;
  }
  lua_pop(L, 1);

  lua_newtable(L);
  lua_pushvalue(L, -1);
  lua_setglobal(L, "hooks");
  lua_pop(L, 1);
}

static void shutdown_sdl(lua_State *L) {
  const char *msg;

  if (rig_invoke_module_function(L, "sdl3", "_shutdown_sdl") != 0) {
    msg = lua_tostring(L, -1);
    fprintf(stderr, "Error shutting down SDL: %s\n",
            msg ? msg : "unknown error");
    lua_pop(L, 1);
  }
}

static int run_user_script(lua_State *L, const char *script_path) {
  const char *ext = strrchr(script_path, '.');

  if (ext == NULL) {
    lua_pushfstring(
        L, "script '%s' has no extension (expected .lua or .fnl)",
        script_path);
    return -1;
  }

  if (strcmp(ext, ".lua") == 0) {
    if (luaL_dofile(L, script_path) != LUA_OK) {
      return -1;
    }
    return 0;
  }

  if (strcmp(ext, ".fnl") == 0) {
    size_t source_len = 0;
    char *source = (char *)SDL_LoadFile(script_path, &source_len);
    if (source == NULL) {
      lua_pushfstring(L, "failed to read script '%s': %s", script_path,
                      SDL_GetError());
      return -1;
    }

    lua_getglobal(L, "fennel");
    if (!lua_istable(L, -1)) {
      SDL_free(source);
      lua_pop(L, 1);
      lua_pushliteral(L, "global 'fennel' module is not available");
      return -1;
    }

    lua_getfield(L, -1, "eval");
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) {
      SDL_free(source);
      lua_pop(L, 1);
      lua_pushliteral(L, "fennel.eval is not available");
      return -1;
    }

    lua_pushlstring(L, source, source_len);
    lua_newtable(L);
    lua_pushstring(L, script_path);
    lua_setfield(L, -2, "filename");

    if (lua_pcall(L, 2, 0, 0) != LUA_OK) {
      SDL_free(source);
      return -1;
    }

    SDL_free(source);
    return 0;
  }

  lua_pushfstring(
      L, "unsupported script extension for '%s' (expected .lua or .fnl)",
      script_path);
  return -1;
}

static int open_lua_lib(lua_State *L, lua_CFunction open_fn,
                        const char *lib_name, const char *label) {
  const char *msg;
  int nargs = 0;

  lua_pushcfunction(L, open_fn);
  if (lib_name != NULL) {
    lua_pushstring(L, lib_name);
    nargs = 1;
  }

  if (lua_pcall(L, nargs, 0, 0) != LUA_OK) {
    msg = lua_tostring(L, -1);
    fprintf(stderr, "Failed to initialize %s runtime: %s\n", label,
            msg ? msg : "unknown error");
    lua_pop(L, 1);
    return -1;
  }

  return 0;
}

static int init_lua_runtime(rig_app_state *app) {
  app->L = luaL_newstate();
  if (app->L == NULL) {
    fprintf(stderr, "Failed to initialize LuaJIT state\n");
    return -1;
  }

  if (open_lua_lib(app->L, luaopen_base, NULL, "base") != 0) {
    return -1;
  }
  if (open_lua_lib(app->L, luaopen_string, NULL, LUA_STRLIBNAME) != 0) {
    return -1;
  }
  if (open_lua_lib(app->L, luaopen_table, NULL, LUA_TABLIBNAME) != 0) {
    return -1;
  }
  if (open_lua_lib(app->L, luaopen_math, NULL, LUA_MATHLIBNAME) != 0) {
    return -1;
  }
  if (open_lua_lib(app->L, luaopen_bit, LUA_BITLIBNAME, LUA_BITLIBNAME) != 0) {
    return -1;
  }

  ensure_hooks_table(app->L);

  // risky modules like `package` or `ffi` are loaded only until
  // all builtin modules have been initialized

  if (open_lua_lib(app->L, luaopen_package, LUA_LOADLIBNAME,
                   LUA_LOADLIBNAME) != 0) {
    return -1;
  }

  luaopen_ffi(app->L);
  lua_setglobal(app->L, "ffi");

  if (rig_init_modules(app->L) != 0) {
    const char *msg = lua_tostring(app->L, -1);
    fprintf(stderr, "Failed to initialize rig modules: %s\n",
            msg ? msg : "unknown error");
    lua_pop(app->L, 1);
    return -1;
  }

  rig_remove_global(app->L, "ffi");
  rig_remove_global(app->L, "package");
  rig_remove_global(app->L, "require");
  return 0;
}

static int init_sdl(lua_State *L) {
  return rig_invoke_module_function(L, "sdl3", "_init_sdl");
}

SDL_AppResult SDL_AppInit(void **appstate, int argc, char **argv) {
  rig_app_state *app;

  if (argc != 2) {
    print_usage(argv[0]);
    return SDL_APP_FAILURE;
  }

  app = SDL_calloc(1, sizeof(*app));
  if (app == NULL) {
    fprintf(stderr, "Out of memory\n");
    return SDL_APP_FAILURE;
  }
  *appstate = app;

  if (init_lua_runtime(app) != 0) {
    return SDL_APP_FAILURE;
  }

  if (run_user_script(app->L, argv[1]) != 0) {
    return report_lua_error(app->L, "Error running script");
  }

  lua_getglobal(app->L, "hooks");
  if (lua_istable(app->L, -1)) {
    lua_getfield(app->L, -1, "render");
    app->has_render_handler = lua_isfunction(app->L, -1);
    lua_pop(app->L, 2);
  } else {
    app->has_render_handler = 0;
    lua_pop(app->L, 1);
  }

  if (!app->has_render_handler) {
    return SDL_APP_SUCCESS;
  }

  if (init_sdl(app->L) != 0) {
    return report_lua_error(app->L, "Error initializing SDL video");
  }

  return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppEvent(void *appstate, SDL_Event *event) {
  rig_app_state *app = (rig_app_state *)appstate;

  if (app == NULL || app->L == NULL) {
    return SDL_APP_FAILURE;
  }

  if (event->type == SDL_EVENT_QUIT) {
    return SDL_APP_SUCCESS;
  }

  if (event->type == SDL_EVENT_KEY_DOWN || event->type == SDL_EVENT_KEY_UP) {
    if (dispatch_keyboard_event(app->L, &event->key) != 0) {
      return report_lua_error(app->L, "Error in hooks.handle_key");
    }
  }

  return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppIterate(void *appstate) {
  rig_app_state *app = (rig_app_state *)appstate;

  if (app == NULL || app->L == NULL) {
    return SDL_APP_FAILURE;
  }
  if (!app->has_render_handler) {
    return SDL_APP_SUCCESS;
  }

  if (dispatch_render(app->L) != 0) {
    return report_lua_error(app->L, "Error in hooks.render");
  }

  if (present_render(app->L) != 0) {
    return report_lua_error(app->L, "Error presenting frame");
  }

  return SDL_APP_CONTINUE;
}

void SDL_AppQuit(void *appstate, SDL_AppResult result) {
  rig_app_state *app = (rig_app_state *)appstate;
  (void)result;

  if (app == NULL) {
    return;
  }

  if (app->L != NULL) {
    shutdown_sdl(app->L);
    lua_close(app->L);
  }

  SDL_free(app);
}
