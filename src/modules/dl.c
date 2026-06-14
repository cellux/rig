#include <lua.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#elif defined(__unix__) || defined(__APPLE__)
#include <dlfcn.h>
#endif

static void set_int_constant(lua_State *L, const char *name, int value) {
  lua_pushinteger(L, (lua_Integer)value);
  lua_setfield(L, -2, name);
}

#if defined(_WIN32)

static char rig_dl_last_error[512];

static void rig_dl_set_windows_error_message(const char *prefix) {
  DWORD code = GetLastError();
  DWORD flags = FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS;
  DWORD rc = FormatMessageA(flags, NULL, code, 0, rig_dl_last_error,
                            (DWORD)sizeof(rig_dl_last_error), NULL);

  if (rc == 0) {
    _snprintf(rig_dl_last_error, sizeof(rig_dl_last_error),
              "%s (Windows error %lu)", prefix, (unsigned long)code);
    rig_dl_last_error[sizeof(rig_dl_last_error) - 1] = '\0';
    return;
  }

  while (rc > 0 &&
         (rig_dl_last_error[rc - 1] == '\r' || rig_dl_last_error[rc - 1] == '\n' ||
          rig_dl_last_error[rc - 1] == ' ')) {
    rig_dl_last_error[rc - 1] = '\0';
    rc--;
  }

  {
    char message[sizeof(rig_dl_last_error)];
    strncpy(message, rig_dl_last_error, sizeof(message));
    message[sizeof(message) - 1] = '\0';
    _snprintf(rig_dl_last_error, sizeof(rig_dl_last_error), "%s: %s", prefix,
              message);
    rig_dl_last_error[sizeof(rig_dl_last_error) - 1] = '\0';
  }
}

static wchar_t *rig_dl_utf8_to_utf16(const char *text) {
  int length;
  wchar_t *buffer;

  if (text == NULL) {
    return NULL;
  }

  length = MultiByteToWideChar(CP_UTF8, 0, text, -1, NULL, 0);
  if (length <= 0) {
    rig_dl_set_windows_error_message("failed to convert UTF-8 path to UTF-16");
    return NULL;
  }

  buffer = (wchar_t *)malloc((size_t)length * sizeof(wchar_t));
  if (buffer == NULL) {
    strncpy(rig_dl_last_error, "out of memory", sizeof(rig_dl_last_error));
    rig_dl_last_error[sizeof(rig_dl_last_error) - 1] = '\0';
    return NULL;
  }

  if (MultiByteToWideChar(CP_UTF8, 0, text, -1, buffer, length) <= 0) {
    free(buffer);
    rig_dl_set_windows_error_message("failed to convert UTF-8 path to UTF-16");
    return NULL;
  }

  return buffer;
}

#endif

void *rig_dl_open(const char *path) {
#if defined(_WIN32)
  HMODULE handle;
  wchar_t *wpath;

  if (path == NULL) {
    handle = GetModuleHandleW(NULL);
    if (handle == NULL) {
      rig_dl_set_windows_error_message("failed to get current process module");
      return NULL;
    }
    return (void *)handle;
  }

  wpath = rig_dl_utf8_to_utf16(path);
  if (wpath == NULL) {
    return NULL;
  }

  handle = LoadLibraryW(wpath);
  free(wpath);

  if (handle == NULL) {
    rig_dl_set_windows_error_message("failed to load shared object");
    return NULL;
  }

  return (void *)handle;
#elif defined(__unix__) || defined(__APPLE__)
  dlerror();
  return dlopen(path, RTLD_NOW | RTLD_LOCAL);
#else
  (void)path;
  return NULL;
#endif
}

void *rig_dl_open_flags(const char *path, int flags) {
#if defined(_WIN32)
  (void)flags;
  return rig_dl_open(path);
#elif defined(__unix__) || defined(__APPLE__)
  dlerror();
  return dlopen(path, flags);
#else
  (void)path;
  (void)flags;
  return NULL;
#endif
}

void *rig_dl_sym(void *handle, const char *name) {
#if defined(_WIN32)
  FARPROC symbol;

  if (handle == NULL || name == NULL) {
    return NULL;
  }

  symbol = GetProcAddress((HMODULE)handle, name);
  if (symbol == NULL) {
    rig_dl_set_windows_error_message("failed to load symbol");
    return NULL;
  }

  return (void *)symbol;
#elif defined(__unix__) || defined(__APPLE__)
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
#if defined(_WIN32)
  if (FreeLibrary((HMODULE)handle) == 0) {
    rig_dl_set_windows_error_message("failed to unload shared object");
    return -1;
  }
  return 0;
#elif defined(__unix__) || defined(__APPLE__)
  dlerror();
  return dlclose(handle);
#else
  (void)handle;
  return -1;
#endif
}

const char *rig_dl_error(void) {
#if defined(_WIN32)
  return rig_dl_last_error[0] != '\0' ? rig_dl_last_error
                                      : "unknown dynamic loader error";
#elif defined(__unix__) || defined(__APPLE__)
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
