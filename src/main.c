#include <stdio.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "runtime.h"

typedef struct rig_startup_args {
  int script_index;
  const char *script_path;
} rig_startup_args;

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

static int set_rig_argv_field(lua_State *L, int argc, char **argv) {
  int i;

  lua_getglobal(L, "rig");
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    fprintf(stderr, "Failed to initialize rig runtime field 'argv'\n");
    return -1;
  }

  lua_createtable(L, argc, 0);
  for (i = 0; i < argc; ++i) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i);
  }

  lua_setfield(L, -2, "argv");
  lua_pop(L, 1);
  return 0;
}

static void print_usage(const char *argv0) {
  fprintf(stderr, "Usage: %s <scriptfile> [args...]\n", argv0);
}

static int parse_startup_args(int argc, char **argv, rig_startup_args *out) {
  if (argc < 2) {
    print_usage(argv[0]);
    return -1;
  }

  out->script_index = 1;
  out->script_path = argv[out->script_index];
  return 0;
}

static void init_global_arg(lua_State *L, int argc, char **argv, int script_index) {
  int i;
  int positive_arg_count = argc - script_index - 1;
  int negative_arg_count = script_index;

  lua_createtable(L, positive_arg_count > 0 ? positive_arg_count : 0,
                  negative_arg_count + 1);

  for (i = 0; i < script_index; ++i) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i - script_index);
  }

  lua_pushstring(L, argv[script_index]);
  lua_rawseti(L, -2, 0);

  for (i = script_index + 1; i < argc; ++i) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i - script_index);
  }

  lua_setglobal(L, "arg");
}

static lua_State *init_lua_runtime(int argc, char **argv,
                                   const rig_startup_args *startup_args) {
  lua_State *L = luaL_newstate();
  if (L == NULL) {
    fprintf(stderr, "Failed to initialize LuaJIT state\n");
    return NULL;
  }

  luaL_openlibs(L);
  init_global_arg(L, argc, argv, startup_args->script_index);

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
    lua_pop(L, 1);
    lua_close(L);
    return NULL;
  }

  if (set_rig_argv_field(L, argc, argv) != 0) {
    lua_close(L);
    return NULL;
  }

  return L;
}

int main(int argc, char **argv) {
  lua_State *L;
  rig_startup_args startup_args;
  const char *msg;
  int status = 0;

  if (parse_startup_args(argc, argv, &startup_args) != 0) {
    return 1;
  }

  L = init_lua_runtime(argc, argv, &startup_args);
  if (L == NULL) {
    return 1;
  }

  if (run_user_script(L, startup_args.script_path) != 0) {
    msg = lua_tostring(L, -1);
    fprintf(stderr, "Error running script: %s\n", msg ? msg : "unknown error");
    lua_pop(L, 1);
    status = 1;
  }

  lua_close(L);
  return status;
}
