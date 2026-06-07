#include <stdio.h>

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

#include "runtime.h"

struct rig_args {
  int argc;
  char **argv;
  int script_index;
  const char *script_path;
};

static void print_usage(const char *argv0) {
  fprintf(stderr, "Usage: %s <scriptfile> [args...]\n", argv0);
}

static int parse_args(int argc, char **argv, struct rig_args *out) {
  if (argc < 2) {
    print_usage(argv[0]);
    return -1;
  }

  out->argc = argc;
  out->argv = argv;

  out->script_index = 1;
  out->script_path = argv[out->script_index];

  return 0;
}

static void set_arg(lua_State *L, const struct rig_args *rig_args) {
  int i;

  int argc = rig_args->argc;
  char **argv = rig_args->argv;

  int script_index = rig_args->script_index;

  int positive_arg_count = argc - script_index - 1;
  int negative_arg_count = script_index;

  int arg_table_array_size = positive_arg_count > 0 ? positive_arg_count : 0;
  int arg_table_hash_size = negative_arg_count + 1;

  lua_createtable(L, arg_table_array_size, arg_table_hash_size);

  for (i = 0; i < argc; ++i) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i - script_index);
  }

  lua_setglobal(L, "arg");
}

static int set_rig_argv(lua_State *L, const struct rig_args *rig_args) {
  int i;

  lua_getglobal(L, "rig");
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    fprintf(stderr, "Failed to initialize rig runtime field 'argv'\n");
    return -1;
  }

  int argc = rig_args->argc;
  char **argv = rig_args->argv;

  lua_createtable(L, argc, 0);

  for (i = 0; i < argc; ++i) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i);
  }

  lua_setfield(L, -2, "argv");
  lua_pop(L, 1);
  return 0;
}

static lua_State *init_lua_runtime(const struct rig_args *rig_args) {
  lua_State *L = luaL_newstate();
  if (L == NULL) {
    fprintf(stderr, "Failed to initialize LuaJIT state\n");
    return NULL;
  }

  luaL_openlibs(L);
  set_arg(L, rig_args);

  if (rig_register_preloaded_modules(L) != 0) {
    const char *msg = lua_tostring(L, -1);
    fprintf(stderr, "Failed to register rig modules: %s\n",
            msg ? msg : "unknown error");
    lua_pop(L, 1);
    lua_close(L);
    return NULL;
  }

  if (rig_require_module(L, "fennel") != 0 ||
      rig_require_module(L, "rig") != 0) {
    const char *msg = lua_tostring(L, -1);
    fprintf(stderr, "Failed to initialize rig builtin modules: %s\n",
            msg ? msg : "unknown error");
    lua_pop(L, 1);
    lua_close(L);
    return NULL;
  }

  if (set_rig_argv(L, rig_args) != 0) {
    lua_close(L);
    return NULL;
  }

  return L;
}

int main(int argc, char **argv) {
  lua_State *L;
  struct rig_args rig_args;
  const char *msg;
  int status = 0;

  if (parse_args(argc, argv, &rig_args) != 0) {
    return 1;
  }

  L = init_lua_runtime(&rig_args);
  if (L == NULL) {
    return 1;
  }

  lua_pushstring(L, rig_args.script_path);
  if (rig_invoke_module_function(L, "rig", "run_script_file") != 0) {
    msg = lua_tostring(L, -1);
    fprintf(stderr, "Error running script: %s\n", msg ? msg : "unknown error");
    lua_pop(L, 1);
    status = 1;
  }

  lua_close(L);
  return status;
}
