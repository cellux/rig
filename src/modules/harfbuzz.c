#include <hb.h>

#include <lua.h>

static void set_u32_constant(lua_State *L, const char *name, uint32_t value) {
  lua_pushinteger(L, (lua_Integer)value);
  lua_setfield(L, -2, name);
}

static void set_i32_constant(lua_State *L, const char *name, int value) {
  lua_pushinteger(L, (lua_Integer)value);
  lua_setfield(L, -2, name);
}

#define SET_U32_CONST(name) set_u32_constant(L, #name, HB_##name)
#define SET_I32_CONST(name) set_i32_constant(L, #name, HB_##name)

void rig_register_harfbuzz(lua_State *L) {
  SET_U32_CONST(TAG_NONE);
  SET_U32_CONST(TAG_MAX);
  SET_U32_CONST(TAG_MAX_SIGNED);

  SET_I32_CONST(DIRECTION_INVALID);
  SET_I32_CONST(DIRECTION_LTR);
  SET_I32_CONST(DIRECTION_RTL);
  SET_I32_CONST(DIRECTION_TTB);
  SET_I32_CONST(DIRECTION_BTT);

  SET_U32_CONST(SCRIPT_INVALID);
  SET_U32_CONST(SCRIPT_LATIN);

  SET_I32_CONST(BUFFER_CONTENT_TYPE_INVALID);
  SET_I32_CONST(BUFFER_CONTENT_TYPE_UNICODE);
  SET_I32_CONST(BUFFER_CONTENT_TYPE_GLYPHS);

  SET_I32_CONST(BUFFER_CLUSTER_LEVEL_MONOTONE_GRAPHEMES);
  SET_I32_CONST(BUFFER_CLUSTER_LEVEL_MONOTONE_CHARACTERS);
  SET_I32_CONST(BUFFER_CLUSTER_LEVEL_CHARACTERS);
  SET_I32_CONST(BUFFER_CLUSTER_LEVEL_GRAPHEMES);
  SET_I32_CONST(BUFFER_CLUSTER_LEVEL_DEFAULT);
}
