#include <stdio.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "runtime.h"

static void print_usage(const char *argv0) {
  fprintf(stderr, "Usage: %s <scriptfile>\n", argv0);
}

static int report_lua_error(lua_State *L, const char *context) {
  const char *msg = lua_tostring(L, -1);
  fprintf(stderr, "%s: %s\n", context, msg ? msg : "unknown error");
  lua_pop(L, 1);
  return 1;
}

static int run_user_script(lua_State *L, const char *script_path) {
  if (rig_push_module_function(L, "rig", "run_script_file") != 0) {
    return -1;
  }
  lua_pushstring(L, script_path);
  if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
    return -1;
  }

  return 0;
}

static int set_rig_string_field(lua_State *L, const char *field_name,
                                const char *value) {
  lua_getglobal(L, "rig");
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    fprintf(stderr, "Failed to initialize rig runtime field '%s'\n", field_name);
    return -1;
  }

  lua_pushstring(L, value);
  lua_setfield(L, -2, field_name);
  lua_pop(L, 1);
  return 0;
}

static lua_State *init_lua_runtime(void) {
  lua_State *L = luaL_newstate();
  if (L == NULL) {
    fprintf(stderr, "Failed to initialize LuaJIT state\n");
    return NULL;
  }

  luaL_openlibs(L);

  if (rig_register_preloaded_modules(L) != 0) {
    const char *msg = lua_tostring(L, -1);
    fprintf(stderr, "Failed to register rig modules: %s\n",
            msg ? msg : "unknown error");
    lua_pop(L, 1);
    lua_close(L);
    return NULL;
  }

  if (rig_require_module(L, "fennel") != 0 || rig_require_module(L, "rig") != 0) {
    const char *msg = lua_tostring(L, -1);
    fprintf(stderr, "Failed to initialize rig builtin modules: %s\n",
            msg ? msg : "unknown error");
    if (lua_gettop(L) > 0) {
      lua_pop(L, 1);
    }
    lua_close(L);
    return NULL;
  }

  return L;
}

int main(int argc, char **argv) {
  lua_State *L;
  int status = 0;

  if (argc != 2) {
    print_usage(argv[0]);
    return 1;
  }

  L = init_lua_runtime();
  if (L == NULL) {
    return 1;
  }

  if (set_rig_string_field(L, "executable_path", argv[0]) != 0) {
    lua_close(L);
    return 1;
  }

  if (run_user_script(L, argv[1]) != 0) {
    status = report_lua_error(L, "Error running script");
  }

  lua_close(L);
  return status;
}
