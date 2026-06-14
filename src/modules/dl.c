#include <lua.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__unix__) || defined(__APPLE__)
#include <dlfcn.h>
#endif

static void set_int_constant(lua_State *L, const char *name, int value) {
  lua_pushinteger(L, (lua_Integer)value);
  lua_setfield(L, -2, name);
}

void *rig_dl_open(const char *path) {
#if defined(__unix__) || defined(__APPLE__)
  dlerror();
  return dlopen(path, RTLD_NOW | RTLD_LOCAL);
#else
  (void)path;
  return NULL;
#endif
}

void *rig_dl_open_flags(const char *path, int flags) {
#if defined(__unix__) || defined(__APPLE__)
  dlerror();
  return dlopen(path, flags);
#else
  (void)path;
  (void)flags;
  return NULL;
#endif
}

void *rig_dl_sym(void *handle, const char *name) {
#if defined(__unix__) || defined(__APPLE__)
  void *symbol;

  dlerror();
  symbol = dlsym(handle, name);
  if (symbol == NULL) {
    size_t len = strlen(name);
    char *alt_name = (char *)malloc(len + 2);
    if (alt_name != NULL) {
      alt_name[0] = '_';
      memcpy(alt_name + 1, name, len + 1);
      dlerror();
      symbol = dlsym(handle, alt_name);
      free(alt_name);
    }

    if (symbol == NULL) {
      return NULL;
    }
  }

  return symbol;
#else
  (void)handle;
  (void)name;
  return NULL;
#endif
}

int rig_dl_close(void *handle) {
#if defined(__unix__) || defined(__APPLE__)
  dlerror();
  return dlclose(handle);
#else
  (void)handle;
  return -1;
#endif
}

const char *rig_dl_error(void) {
#if defined(__unix__) || defined(__APPLE__)
  return dlerror();
#else
  return "dl module is not implemented on this platform";
#endif
}

void rig_register_dl(lua_State *L) {
#if defined(_WIN32)
  lua_pushboolean(L, 1);
  lua_setfield(L, -2, "SUPPORTED");
#elif defined(__unix__) || defined(__APPLE__)
  lua_pushboolean(L, 1);
  lua_setfield(L, -2, "SUPPORTED");

  set_int_constant(L, "RTLD_LAZY", RTLD_LAZY);
  set_int_constant(L, "RTLD_NOW", RTLD_NOW);
  set_int_constant(L, "RTLD_LOCAL", RTLD_LOCAL);
  set_int_constant(L, "RTLD_GLOBAL", RTLD_GLOBAL);
#else
  lua_pushboolean(L, 0);
  lua_setfield(L, -2, "SUPPORTED");
#endif
}
