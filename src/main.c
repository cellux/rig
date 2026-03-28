#include <stdio.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

static void print_usage(const char *argv0) {
    fprintf(stderr, "Usage: %s <scriptfile>\n", argv0);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        print_usage(argv[0]);
        return 1;
    }

    lua_State *L = luaL_newstate();
    if (L == NULL) {
        fprintf(stderr, "Failed to initialize LuaJIT state\n");
        return 1;
    }

    if (luaL_dofile(L, argv[1]) != LUA_OK) {
        const char *msg = lua_tostring(L, -1);
        fprintf(stderr, "Error running '%s': %s\n", argv[1], msg ? msg : "unknown error");
        lua_pop(L, 1);
        lua_close(L);
        return 1;
    }

    lua_close(L);
    return 0;
}
