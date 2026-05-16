#include <lua.h>

#if defined(__linux__)
#include <dlfcn.h>

static void set_int_constant(lua_State *L, const char *name, int value) {
  lua_pushinteger(L, (lua_Integer)value);
  lua_setfield(L, -2, name);
}
#endif

void *rig_dl_open(const char *path) {
#if defined(__linux__)
  dlerror();
  return dlopen(path, RTLD_NOW | RTLD_LOCAL);
#else
  (void)path;
  return NULL;
#endif
}

void *rig_dl_open_flags(const char *path, int flags) {
#if defined(__linux__)
  dlerror();
  return dlopen(path, flags);
#else
  (void)path;
  (void)flags;
  return NULL;
#endif
}

void *rig_dl_sym(void *handle, const char *name) {
#if defined(__linux__)
  dlerror();
  return dlsym(handle, name);
#else
  (void)handle;
  (void)name;
  return NULL;
#endif
}

int rig_dl_close(void *handle) {
#if defined(__linux__)
  dlerror();
  return dlclose(handle);
#else
  (void)handle;
  return -1;
#endif
}

const char *rig_dl_error(void) {
#if defined(__linux__)
  return dlerror();
#else
  return "dl module is only implemented on Linux";
#endif
}

void rig_register_dl(lua_State *L) {
#if defined(__linux__)
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
