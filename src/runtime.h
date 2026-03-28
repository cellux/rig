#ifndef RIG_RUNTIME_H
#define RIG_RUNTIME_H

#include <stddef.h>

#include <lua.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rig_module_desc {
    const char *name;
    void (*register_fn)(lua_State *L);
    const unsigned char *bytecode;
    const size_t *bytecode_len;
} rig_module_desc;

extern const rig_module_desc rig_modules[];
extern const size_t rig_module_count;

void rig_push_module(lua_State *L, const char *module_name);
int rig_push_global_handler(lua_State *L, const char *handler_name);
int rig_init_modules(lua_State *L);

#ifdef __cplusplus
}
#endif

#endif
