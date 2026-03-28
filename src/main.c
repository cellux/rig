#include <stdio.h>

#define SDL_MAIN_USE_CALLBACKS
#include <SDL3/SDL_main.h>
#include <SDL3/SDL.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "runtime.h"

typedef struct rig_app_state {
    lua_State *L;
    SDL_Window *window;
    SDL_Renderer *renderer;
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

static int push_sdl3_function(lua_State *L, const char *name) {
    lua_getglobal(L, "sdl3");
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        lua_pushliteral(L, "global 'sdl3' module is not available");
        return -1;
    }

    lua_getfield(L, -1, name);
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) {
        lua_pop(L, 1);
        lua_pushfstring(L, "sdl3.%s is not available", name);
        return -1;
    }

    return 0;
}

static int dispatch_key_event(lua_State *L, const SDL_KeyboardEvent *key_event) {
    if (push_sdl3_function(L, "_dispatch_key") != 0) {
        return -1;
    }

    lua_pushlightuserdata(L, (void *)key_event);
    if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
        return -1;
    }

    return 0;
}

static int dispatch_render(lua_State *L) {
    if (push_sdl3_function(L, "_dispatch_render") != 0) {
        return -1;
    }

    if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
        return -1;
    }

    return 0;
}

static int should_run_render_loop(lua_State *L, int *out_should_run) {
    if (push_sdl3_function(L, "_should_run") != 0) {
        return -1;
    }

    if (lua_pcall(L, 0, 1, 0) != LUA_OK) {
        return -1;
    }

    *out_should_run = lua_toboolean(L, -1);
    lua_pop(L, 1);
    return 0;
}

static int init_lua_runtime(rig_app_state *app) {
    app->L = luaL_newstate();
    if (app->L == NULL) {
        fprintf(stderr, "Failed to initialize LuaJIT state\n");
        return -1;
    }

    luaopen_base(app->L);
    lua_pop(app->L, 1);
    luaopen_string(app->L);
    lua_pop(app->L, 1);
    luaopen_table(app->L);
    lua_pop(app->L, 1);
    luaopen_math(app->L);
    lua_pop(app->L, 1);

    luaopen_ffi(app->L);
    lua_setglobal(app->L, "ffi");

    if (rig_init_modules(app->L) != 0) {
        const char *msg = lua_tostring(app->L, -1);
        fprintf(stderr, "Failed to initialize rig modules: %s\n", msg ? msg : "unknown error");
        lua_pop(app->L, 1);
        lua_pushnil(app->L);
        lua_setglobal(app->L, "ffi");
        return -1;
    }

    lua_pushnil(app->L);
    lua_setglobal(app->L, "ffi");

    return 0;
}

static int init_sdl_video(rig_app_state *app) {
    Uint32 required = SDL_INIT_VIDEO | SDL_INIT_EVENTS;

    if ((SDL_WasInit(required) & required) != required) {
        if (!SDL_Init(required)) {
            fprintf(stderr, "failed to initialize SDL: %s\n", SDL_GetError());
            return -1;
        }
    }

    app->window = SDL_CreateWindow("rig", 640, 360, 0);
    if (app->window == NULL) {
        fprintf(stderr, "failed to create window: %s\n", SDL_GetError());
        return -1;
    }

    app->renderer = SDL_CreateRenderer(app->window, NULL);
    if (app->renderer == NULL) {
        fprintf(stderr, "failed to create renderer: %s\n", SDL_GetError());
        SDL_DestroyWindow(app->window);
        app->window = NULL;
        return -1;
    }

    (void)SDL_SetRenderVSync(app->renderer, 1);

    lua_getglobal(app->L, "sdl3");
    if (!lua_istable(app->L, -1)) {
        lua_pop(app->L, 1);
        fprintf(stderr, "global 'sdl3' module is not available\n");
        return -1;
    }
    lua_pushlightuserdata(app->L, app->renderer);
    lua_setfield(app->L, -2, "renderer");
    lua_pop(app->L, 1);

    return 0;
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

    if (luaL_dofile(app->L, argv[1]) != LUA_OK) {
        return report_lua_error(app->L, "Error running script");
    }

    if (should_run_render_loop(app->L, &app->has_render_handler) != 0) {
        return report_lua_error(app->L, "Error checking render loop readiness");
    }
    if (!app->has_render_handler) {
        return SDL_APP_SUCCESS;
    }

    if (init_sdl_video(app) != 0) {
        return SDL_APP_FAILURE;
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
        if (dispatch_key_event(app->L, &event->key) != 0) {
            return report_lua_error(app->L, "Error in on_key");
        }
    }

    return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppIterate(void *appstate) {
    rig_app_state *app = (rig_app_state *)appstate;

    if (app == NULL || app->L == NULL) {
        return SDL_APP_FAILURE;
    }
    if (!app->has_render_handler || app->renderer == NULL) {
        return SDL_APP_SUCCESS;
    }

    if (dispatch_render(app->L) != 0) {
        return report_lua_error(app->L, "Error in on_render");
    }

    if (!SDL_RenderPresent(app->renderer)) {
        fprintf(stderr, "failed to present renderer: %s\n", SDL_GetError());
        return SDL_APP_FAILURE;
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
        lua_getglobal(app->L, "sdl3");
        if (lua_istable(app->L, -1)) {
            lua_pushnil(app->L);
            lua_setfield(app->L, -2, "renderer");
        }
        lua_pop(app->L, 1);
    }
    if (app->renderer != NULL) {
        SDL_DestroyRenderer(app->renderer);
    }
    if (app->window != NULL) {
        SDL_DestroyWindow(app->window);
    }
    if (app->L != NULL) {
        lua_close(app->L);
    }

    SDL_free(app);
}
