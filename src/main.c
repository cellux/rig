#include <stdio.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "runtime.h"

static void print_usage(const char *argv0) {
    fprintf(stderr, "Usage: %s <scriptfile>\n", argv0);
}

static int maybe_run_sdl3_loop(lua_State *L) {
    lua_getglobal(L, "on_render");
    if (!lua_isfunction(L, -1)) {
        lua_pop(L, 1);
        return 0;
    }
    lua_pop(L, 1);

    lua_getglobal(L, "sdl3");
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        return luaL_error(L, "global 'sdl3' is not available");
    }

    lua_getfield(L, -1, "loop");
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) {
        lua_pop(L, 1);
        return luaL_error(L, "sdl3.loop is not available");
    }

    if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
        return -1;
    }

    return 0;
}

int main(int argc, char **argv) {
    lua_State *L;

    if (argc != 2) {
        print_usage(argv[0]);
        return 1;
    }

    L = luaL_newstate();
    if (L == NULL) {
        fprintf(stderr, "Failed to initialize LuaJIT state\n");
        return 1;
    }

    luaopen_base(L);
    lua_pop(L, 1);
    luaopen_string(L);
    lua_pop(L, 1);
    luaopen_table(L);
    lua_pop(L, 1);
    luaopen_math(L);
    lua_pop(L, 1);

    if (rig_init_modules(L) != 0) {
        const char *msg = lua_tostring(L, -1);
        fprintf(stderr, "Failed to initialize rig modules: %s\n", msg ? msg : "unknown error");
        lua_pop(L, 1);
        lua_close(L);
        return 1;
    }

    if (luaL_dofile(L, argv[1]) != LUA_OK) {
        const char *msg = lua_tostring(L, -1);
        fprintf(stderr, "Error running '%s': %s\n", argv[1], msg ? msg : "unknown error");
        lua_pop(L, 1);
        lua_close(L);
        return 1;
    }

    if (maybe_run_sdl3_loop(L) != 0) {
        const char *msg = lua_tostring(L, -1);
        fprintf(stderr, "Error running sdl3.loop: %s\n", msg ? msg : "unknown error");
        lua_pop(L, 1);
        lua_close(L);
        return 1;
    }

    lua_close(L);
    return 0;
}
