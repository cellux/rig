local M = ... or {}
local ffi = require("ffi")
local sdl3 = require("sdl3")

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
]]

local function bind_function(name)
   local ptr, err = sdl3.get_gl_proc_address("gl" .. name)
   if ptr == nil then
      error(
         ("failed to resolve OpenGL function gl%s: %s"):format(
            name,
            tostring(err or "unknown error")
         ),
         0
      )
   end

   local typedef_name = "rig_gl__" .. name
   local ok, fn_or_err = pcall(ffi.cast, typedef_name, ptr)
   if not ok then
      error(
         ("resolved OpenGL function gl%s, but %s is not declared in gl.lua ffi.cdef"):format(
            name,
            typedef_name
         ),
         0
      )
   end

   return fn_or_err
end

local function shader_log(shader)
   local length_out = ffi.new("GLint[1]")
   M.GetShaderiv(shader, M.INFO_LOG_LENGTH, length_out)
   local length = tonumber(length_out[0]) or 0
   if length <= 1 then
      return ""
   end

   local buffer = ffi.new("GLchar[?]", length)
   M.GetShaderInfoLog(shader, length, nil, buffer)
   return ffi.string(buffer)
end

local function program_log(program)
   local length_out = ffi.new("GLint[1]")
   M.GetProgramiv(program, M.INFO_LOG_LENGTH, length_out)
   local length = tonumber(length_out[0]) or 0
   if length <= 1 then
      return ""
   end

   local buffer = ffi.new("GLchar[?]", length)
   M.GetProgramInfoLog(program, length, nil, buffer)
   return ffi.string(buffer)
end

function M.create_shader(shader_type, source)
   if type(source) ~= "string" then
      error("gl.create_shader requires shader source to be a string", 0)
   end

   local shader = M.CreateShader(shader_type)
   if shader == 0 then
      error("glCreateShader returned 0", 0)
   end

   local source_ptrs = ffi.new("const GLchar *[1]")
   local lengths = ffi.new("GLint[1]")
   source_ptrs[0] = source
   lengths[0] = #source
   M.ShaderSource(shader, 1, source_ptrs, lengths)
   M.CompileShader(shader)

   local compiled = ffi.new("GLint[1]")
   M.GetShaderiv(shader, M.COMPILE_STATUS, compiled)
   if compiled[0] == 0 then
      local log = shader_log(shader)
      M.DeleteShader(shader)
      error("OpenGL shader compilation failed:\n" .. log, 0)
   end

   return shader
end

function M.create_program(options)
   if type(options) ~= "table" then
      error("gl.create_program expects a table", 0)
   end
   if type(options.vertex_source) ~= "string" then
      error("gl.create_program requires vertex_source", 0)
   end
   if type(options.fragment_source) ~= "string" then
      error("gl.create_program requires fragment_source", 0)
   end

   local vertex_shader = M.create_shader(M.VERTEX_SHADER, options.vertex_source)
   local fragment_shader = M.create_shader(M.FRAGMENT_SHADER, options.fragment_source)

   local program = M.CreateProgram()
   if program == 0 then
      M.DeleteShader(vertex_shader)
      M.DeleteShader(fragment_shader)
      error("glCreateProgram returned 0", 0)
   end

   M.AttachShader(program, vertex_shader)
   M.AttachShader(program, fragment_shader)
   M.LinkProgram(program)

   local linked = ffi.new("GLint[1]")
   M.GetProgramiv(program, M.LINK_STATUS, linked)
   M.DeleteShader(vertex_shader)
   M.DeleteShader(fragment_shader)

   if linked[0] == 0 then
      local log = program_log(program)
      M.DeleteProgram(program)
      error("OpenGL program link failed:\n" .. log, 0)
   end

   return program
end

function M.buffer_data(target, data, usage)
   if type(data) ~= "string" then
      error("gl.buffer_data currently expects data to be a string", 0)
   end

   M.BufferData(target, #data, data, usage)
end

function M.get_uniform_location(program, name)
   if type(name) ~= "string" then
      error("gl.get_uniform_location expects name to be a string", 0)
   end

   return tonumber(M.GetUniformLocation(program, name)) or -1
end

function M.get_version_string()
   local ptr = M.GetString(M.VERSION)
   if ptr == nil or ptr == ffi.NULL then
      return nil
   end
   return ffi.string(ptr)
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

return M
