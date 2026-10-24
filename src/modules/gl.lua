local M = ... or {}
local ffi = require("ffi")
local rig = require("rig")
local runtime = require("runtime")

ffi.cdef[[
typedef unsigned int GLenum;
typedef unsigned char GLboolean;
typedef unsigned int GLbitfield;
typedef signed char GLbyte;
typedef short GLshort;
typedef int GLint;
typedef int GLsizei;
typedef unsigned char GLubyte;
typedef unsigned short GLushort;
typedef unsigned int GLuint;
typedef float GLfloat;
typedef double GLdouble;
typedef char GLchar;
typedef ptrdiff_t GLintptr;
typedef ptrdiff_t GLsizeiptr;

typedef const GLubyte *(*rig_gl__GetString)(GLenum name);
typedef void (*rig_gl__Viewport)(GLint x, GLint y, GLsizei width, GLsizei height);
typedef void (*rig_gl__ClearColor)(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha);
typedef void (*rig_gl__Clear)(GLbitfield mask);
typedef void (*rig_gl__Enable)(GLenum cap);
typedef void (*rig_gl__DepthFunc)(GLenum func);
typedef GLuint (*rig_gl__CreateShader)(GLenum type);
typedef void (*rig_gl__ShaderSource)(GLuint shader, GLsizei count, const GLchar *const* string, const GLint *length);
typedef void (*rig_gl__CompileShader)(GLuint shader);
typedef void (*rig_gl__GetShaderiv)(GLuint shader, GLenum pname, GLint *params);
typedef void (*rig_gl__GetShaderInfoLog)(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
typedef void (*rig_gl__DeleteShader)(GLuint shader);
typedef GLuint (*rig_gl__CreateProgram)(void);
typedef void (*rig_gl__AttachShader)(GLuint program, GLuint shader);
typedef void (*rig_gl__LinkProgram)(GLuint program);
typedef void (*rig_gl__GetProgramiv)(GLuint program, GLenum pname, GLint *params);
typedef void (*rig_gl__GetProgramInfoLog)(GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
typedef void (*rig_gl__DeleteProgram)(GLuint program);
typedef void (*rig_gl__UseProgram)(GLuint program);
typedef void (*rig_gl__GenVertexArrays)(GLsizei n, GLuint *arrays);
typedef void (*rig_gl__BindVertexArray)(GLuint array);
typedef void (*rig_gl__DeleteVertexArrays)(GLsizei n, const GLuint *arrays);
typedef void (*rig_gl__GenBuffers)(GLsizei n, GLuint *buffers);
typedef void (*rig_gl__BindBuffer)(GLenum target, GLuint buffer);
typedef void (*rig_gl__BufferData)(GLenum target, GLsizeiptr size, const void *data, GLenum usage);
typedef void (*rig_gl__DeleteBuffers)(GLsizei n, const GLuint *buffers);
typedef void (*rig_gl__GenTextures)(GLsizei n, GLuint *textures);
typedef void (*rig_gl__BindTexture)(GLenum target, GLuint texture);
typedef void (*rig_gl__TexImage2D)(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const void *pixels);
typedef void (*rig_gl__TexParameteri)(GLenum target, GLenum pname, GLint param);
typedef void (*rig_gl__DeleteTextures)(GLsizei n, const GLuint *textures);
typedef void (*rig_gl__ActiveTexture)(GLenum texture);
typedef void (*rig_gl__Disable)(GLenum cap);
typedef void (*rig_gl__BlendFunc)(GLenum sfactor, GLenum dfactor);
typedef void (*rig_gl__EnableVertexAttribArray)(GLuint index);
typedef void (*rig_gl__VertexAttribPointer)(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const void *pointer);
typedef GLint (*rig_gl__GetUniformLocation)(GLuint program, const GLchar *name);
typedef void (*rig_gl__Uniform1i)(GLint location, GLint v0);
typedef void (*rig_gl__Uniform2f)(GLint location, GLfloat v0, GLfloat v1);
typedef void (*rig_gl__Uniform4f)(GLint location, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3);
typedef void (*rig_gl__UniformMatrix4fv)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);
typedef void (*rig_gl__DrawArrays)(GLenum mode, GLint first, GLsizei count);
typedef void (*rig_gl__GenFramebuffers)(GLsizei n, GLuint *framebuffers);
typedef void (*rig_gl__BindFramebuffer)(GLenum target, GLuint framebuffer);
typedef void (*rig_gl__DeleteFramebuffers)(GLsizei n, const GLuint *framebuffers);
typedef void (*rig_gl__FramebufferTexture2D)(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level);
typedef GLenum (*rig_gl__CheckFramebufferStatus)(GLenum target);
typedef void (*rig_gl__GenRenderbuffers)(GLsizei n, GLuint *renderbuffers);
typedef void (*rig_gl__BindRenderbuffer)(GLenum target, GLuint renderbuffer);
typedef void (*rig_gl__DeleteRenderbuffers)(GLsizei n, const GLuint *renderbuffers);
typedef void (*rig_gl__RenderbufferStorage)(GLenum target, GLenum internalformat, GLsizei width, GLsizei height);
typedef void (*rig_gl__FramebufferRenderbuffer)(GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer);
]]

local function bind_function(name)
   local resolver = rawget(M, "_resolver")
   if resolver == nil then
      rig.raise(
         "gl functions require a gl.resolver; add the gl component to the runtime"
      )
   end
   local ptr, err = resolver.get_gl_proc_address("gl" .. name)
   if ptr == nil then
      rig.raise(
         "failed to resolve OpenGL function gl%s: %s",
         name,
         err or "unknown error"
      )
   end

   local typedef_name = "rig_gl__" .. name
   local ok, fn_or_err = pcall(ffi.cast, typedef_name, ptr)
   if not ok then
      rig.raise(
         "resolved OpenGL function gl%s, but %s is not declared in gl.lua ffi.cdef",
         name,
         typedef_name
      )
   end

   return fn_or_err
end

setmetatable(M, {
   __index = function(self, key)
      if type(key) ~= "string" then
         return nil
      end

      local fn = bind_function(key)
      rawset(self, key, fn)
      return fn
   end,
})

-- Resolved GL entry points are context-specific dispatch stubs. Caching them
-- across a context change (for example a second runtime in the same process)
-- leaves stale pointers behind, so the cache is dropped whenever the resolver
-- changes.
local function clear_bound_functions()
   local keys = {}
   for key, value in pairs(M) do
      if type(value) == "cdata" then
         keys[#keys + 1] = key
      end
   end
   for i = 1, #keys do
      rawset(M, keys[i], nil)
   end
end

function M.set_resolver(provider)
   clear_bound_functions()
   rawset(M, "_resolver", provider)
end

function M.clear_resolver()
   clear_bound_functions()
   rawset(M, "_resolver", nil)
end

function M.plugin(spec)
   spec = spec or {}
   return runtime.plugin {
      id = spec.id or "gl",
      capabilities = {
         ["gl.resolver"] = {},
      },
   }
end

function M.component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      requires = {
         { capability = "gl.resolver" },
      },
      create = function(context)
         M.set_resolver(context:capability("gl.resolver"))
         return {}
      end,
      release = function()
         M.clear_resolver()
      end,
   })
end

return M
