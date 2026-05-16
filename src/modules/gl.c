#include <GL/glcorearb.h>

#include <lua.h>

static void set_u32_constant(lua_State *L, const char *name, unsigned int value) {
  lua_pushinteger(L, (lua_Integer)value);
  lua_setfield(L, -2, name);
}

#define SET_GL_CONST(name) set_u32_constant(L, #name, GL_##name)

void rig_register_gl(lua_State *L) {
  SET_GL_CONST(FALSE);
  SET_GL_CONST(TRUE);

  SET_GL_CONST(VERSION);
  SET_GL_CONST(COLOR_BUFFER_BIT);
  SET_GL_CONST(DEPTH_BUFFER_BIT);
  SET_GL_CONST(FLOAT);
  SET_GL_CONST(TRIANGLES);
  SET_GL_CONST(ARRAY_BUFFER);
  SET_GL_CONST(STATIC_DRAW);
  SET_GL_CONST(VERTEX_SHADER);
  SET_GL_CONST(FRAGMENT_SHADER);
  SET_GL_CONST(COMPILE_STATUS);
  SET_GL_CONST(LINK_STATUS);
  SET_GL_CONST(INFO_LOG_LENGTH);
  SET_GL_CONST(DEPTH_TEST);
  SET_GL_CONST(LEQUAL);
}
