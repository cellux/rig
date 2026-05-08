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
    const unsigned char *lua_bytecode;
    const size_t *lua_bytecode_len;
    const unsigned char *fennel_bytecode;
    const size_t *fennel_bytecode_len;
} rig_module_desc;

extern const rig_module_desc rig_modules[];
extern const size_t rig_module_count;

void rig_push_module(lua_State *L, const char *module_name);
int rig_push_module_function(lua_State *L, const char *module_name,
                             const char *function_name);
int rig_invoke_module_function(lua_State *L, const char *module_name,
                               const char *function_name);
void rig_remove_global(lua_State *L, const char *name);
int rig_register_preloaded_modules(lua_State *L);
int rig_require_module(lua_State *L, const char *module_name);

#ifdef __cplusplus
}
#endif

#endif
