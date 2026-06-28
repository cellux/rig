local M = ... or {}
local ffi = require("ffi")
local gl = require("gl")
local rig = require("rig")

local Shader = rig.Class()
local Program = rig.Class()
local Buffer = rig.Class()
local VertexArray = rig.Class()
local Texture2D = rig.Class()

M.Shader = Shader
M.Program = Program
M.Buffer = Buffer
M.VertexArray = VertexArray
M.Texture2D = Texture2D

local function ensure_shader(value)
   if getmetatable(value) ~= Shader then
      rig.raise("glx operation expects a glx.Shader")
   end
end

local function ensure_program(value)
   if getmetatable(value) ~= Program then
      rig.raise("glx operation expects a glx.Program")
   end
end

local function ensure_buffer(value)
   if getmetatable(value) ~= Buffer then
      rig.raise("glx operation expects a glx.Buffer")
   end
end

local function ensure_vertex_array(value)
   if getmetatable(value) ~= VertexArray then
      rig.raise("glx operation expects a glx.VertexArray")
   end
end

local function ensure_texture_2d(value)
   if getmetatable(value) ~= Texture2D then
      rig.raise("glx operation expects a glx.Texture2D")
   end
end

local function ensure_shader_live(shader)
   ensure_shader(shader)
   if shader.id == 0 then
      rig.raise("OpenGL shader has been released")
   end
end

local function ensure_program_live(program)
   ensure_program(program)
   if program.id == 0 then
      rig.raise("OpenGL program has been released")
   end
end

local function ensure_buffer_live(buffer)
   ensure_buffer(buffer)
   if buffer.id == 0 then
      rig.raise("OpenGL buffer has been released")
   end
end

local function ensure_vertex_array_live(vertex_array)
   ensure_vertex_array(vertex_array)
   if vertex_array.id == 0 then
      rig.raise("OpenGL vertex array has been released")
   end
end

local function ensure_texture_2d_live(texture)
   ensure_texture_2d(texture)
   if texture.id == 0 then
      rig.raise("OpenGL texture has been released")
   end
end

local function normalize_size(label, value)
   local size = tonumber(value)
   if size == nil then
      rig.raise("%s must be numeric", label)
   end

   size = math.floor(size)
   if size < 0 then
      rig.raise("%s must be non-negative", label)
   end

   return size
end

local function normalize_usage(value)
   local usage = tonumber(value)
   if usage == nil then
      rig.raise("OpenGL buffer usage must be numeric")
   end
   return usage
end

local function normalize_gl_enum(label, value)
   local normalized = tonumber(value)
   if normalized == nil then
      rig.raise("%s must be numeric", label)
   end
   return normalized
end

local function normalize_gl_boolean(label, value)
   if value == nil then
      return gl.FALSE
   end

   local normalized = tonumber(value)
   if normalized == nil then
      rig.raise("%s must be numeric", label)
   end

   if normalized == 0 then
      return gl.FALSE
   end

   return gl.TRUE
end

local function normalize_pointer(value)
   if value == nil then
      return ffi.cast("const void *", 0)
   end

   if type(value) == "number" then
      return ffi.cast("const void *", value)
   end

   return value
end

local function normalize_texture_unit(unit)
   if unit == nil then
      return nil
   end

   local normalized = normalize_size("OpenGL texture unit", unit)
   return normalized
end

local function shader_stage_constant(stage)
   if stage == "vertex" then
      return gl.VERTEX_SHADER
   end
   if stage == "fragment" then
      return gl.FRAGMENT_SHADER
   end
   if stage == "compute" then
      local compute_shader = rawget(gl, "COMPUTE_SHADER")
      if compute_shader == nil then
         rig.raise("OpenGL compute shaders are not available in this build")
      end
      return compute_shader
   end

   rig.raise("unsupported OpenGL shader stage '%s'", tostring(stage))
end

local function shader_info_log(shader_id)
   local info_log_length = ffi.new("GLint[1]")
   gl.GetShaderiv(shader_id, gl.INFO_LOG_LENGTH, info_log_length)

   local capacity = tonumber(info_log_length[0]) or 0
   if capacity <= 1 then
      return nil
   end

   local actual_length = ffi.new("GLsizei[1]")
   local buffer = ffi.new("GLchar[?]", capacity)
   gl.GetShaderInfoLog(shader_id, capacity, actual_length, buffer)

   local length = tonumber(actual_length[0]) or 0
   if length <= 0 then
      return ffi.string(buffer)
   end
   return ffi.string(buffer, length)
end

local function program_info_log(program_id)
   local info_log_length = ffi.new("GLint[1]")
   gl.GetProgramiv(program_id, gl.INFO_LOG_LENGTH, info_log_length)

   local capacity = tonumber(info_log_length[0]) or 0
   if capacity <= 1 then
      return nil
   end

   local actual_length = ffi.new("GLsizei[1]")
   local buffer = ffi.new("GLchar[?]", capacity)
   gl.GetProgramInfoLog(program_id, capacity, actual_length, buffer)

   local length = tonumber(actual_length[0]) or 0
   if length <= 0 then
      return ffi.string(buffer)
   end
   return ffi.string(buffer, length)
end

local function release_shader_list(shaders)
   if type(shaders) ~= "table" then
      return
   end

   for i = #shaders, 1, -1 do
      local shader = shaders[i]
      if shader ~= nil and getmetatable(shader) == Shader then
         shader:release()
      end
      shaders[i] = nil
   end
end

local function compile_shader(stage, source, source_name)
   if type(source) ~= "string" then
      rig.raise("glx.Shader expects source to be a string")
   end
   if source_name ~= nil and (type(source_name) ~= "string" or source_name == "") then
      rig.raise("glx.Shader expects source_name to be a non-empty string if provided")
   end

   local shader_id = tonumber(gl.CreateShader(shader_stage_constant(stage))) or 0
   if shader_id == 0 then
      rig.raise("failed to create OpenGL %s shader", tostring(stage))
   end

   local source_ptr = ffi.new("const GLchar *[1]")
   source_ptr[0] = source
   gl.ShaderSource(shader_id, 1, source_ptr, nil)
   gl.CompileShader(shader_id)

   local compile_status = ffi.new("GLint[1]")
   gl.GetShaderiv(shader_id, gl.COMPILE_STATUS, compile_status)
   if tonumber(compile_status[0]) ~= gl.TRUE then
      local info_log = shader_info_log(shader_id)
      gl.DeleteShader(shader_id)
      rig.raise(
         "failed to compile OpenGL %s shader%s%s",
         tostring(stage),
         source_name ~= nil and " '" or "",
         source_name ~= nil and (source_name .. "': " .. (info_log or "unknown error")) or (": " .. (info_log or "unknown error"))
      )
   end

   return shader_id
end

local function normalize_shader_list(options)
   local shaders = options.shaders
   if shaders ~= nil then
      if type(shaders) ~= "table" then
         rig.raise("glx.Program expects shaders to be a table if provided")
      end
      if options.vertex_source ~= nil or options.fragment_source ~= nil or options.compute_source ~= nil then
         rig.raise("glx.Program expects either shaders or *_source fields, not both")
      end

      local normalized = {}
      for i = 1, #shaders do
         ensure_shader_live(shaders[i])
         normalized[i] = shaders[i]
      end
      if #normalized == 0 then
         rig.raise("glx.Program requires at least one shader")
      end
      return normalized
   end

   local created = {}
   local ok, err = pcall(function()
      if options.vertex_source ~= nil then
         created[#created + 1] = Shader {
            stage = "vertex",
            source = options.vertex_source,
            source_name = options.vertex_source_name,
         }
      end
      if options.fragment_source ~= nil then
         created[#created + 1] = Shader {
            stage = "fragment",
            source = options.fragment_source,
            source_name = options.fragment_source_name,
         }
      end
      if options.compute_source ~= nil then
         created[#created + 1] = Shader {
            stage = "compute",
            source = options.compute_source,
            source_name = options.compute_source_name,
         }
      end
   end)

   if not ok then
      release_shader_list(created)
      rig.raise(err)
   end
   if #created == 0 then
      rig.raise("glx.Program requires shaders or at least one *_source field")
   end

   return created
end

function Shader:init(options)
   if type(options) ~= "table" then
      rig.raise("glx.Shader expects an options table")
   end

   self.stage = options.stage
   self.source = options.source
   self.source_name = options.source_name
   self.id = compile_shader(self.stage, self.source, self.source_name)
end

function Shader:release()
   ensure_shader(self)
   if self.id == 0 then
      return
   end

   gl.DeleteShader(self.id)
   self.id = 0
end

function Program:init(options)
   if type(options) ~= "table" then
      rig.raise("glx.Program expects an options table")
   end

   self.id = 0
   self.uniform_locations = {}
   self.shaders = normalize_shader_list(options)

   local ok, err = pcall(function()
      local program_id = tonumber(gl.CreateProgram()) or 0
      if program_id == 0 then
         rig.raise("failed to create OpenGL program")
      end

      for i = 1, #self.shaders do
         gl.AttachShader(program_id, self.shaders[i].id)
      end

      gl.LinkProgram(program_id)

      local link_status = ffi.new("GLint[1]")
      gl.GetProgramiv(program_id, gl.LINK_STATUS, link_status)
      if tonumber(link_status[0]) ~= gl.TRUE then
         local info_log = program_info_log(program_id)
         gl.DeleteProgram(program_id)
         rig.raise("failed to link OpenGL program: %s", info_log or "unknown error")
      end

      self.id = program_id
   end)

   if not ok then
      release_shader_list(self.shaders)
      self.shaders = {}
      rig.raise(err)
   end
end

function Program:uniform_location(name)
   ensure_program_live(self)
   if type(name) ~= "string" or name == "" then
      rig.raise("glx.Program:uniform_location expects name to be a non-empty string")
   end

   local cached = self.uniform_locations[name]
   if cached ~= nil then
      return cached
   end

   local location = gl.GetUniformLocation(self.id, name)
   self.uniform_locations[name] = location
   return location
end

function Program:use()
   ensure_program_live(self)
   gl.UseProgram(self.id)
   return self
end

function Program:release()
   ensure_program(self)
   if self.id ~= 0 then
      gl.DeleteProgram(self.id)
      self.id = 0
   end

   release_shader_list(self.shaders)
   self.shaders = {}
   self.uniform_locations = {}
end

function Buffer:init(options)
   if type(options) ~= "table" then
      rig.raise("glx.Buffer expects an options table")
   end

   local target = tonumber(options.target)
   if target == nil then
      rig.raise("glx.Buffer expects target to be numeric")
   end

   local buffers = ffi.new("GLuint[1]")
   gl.GenBuffers(1, buffers)

   self.target = target
   self.id = tonumber(buffers[0]) or 0
   if self.id == 0 then
      rig.raise("failed to create OpenGL buffer")
   end
end

function Buffer:bind()
   ensure_buffer_live(self)
   gl.BindBuffer(self.target, self.id)
   return self
end

function Buffer:set_data(data, usage, size)
   ensure_buffer_live(self)

   local resolved_usage = normalize_usage(usage)
   local resolved_size
   local resolved_data = data
   local scratch = nil

   if data == nil then
      if size == nil then
         rig.raise("glx.Buffer:set_data requires size when data is nil")
      end
      resolved_size = normalize_size("OpenGL buffer size", size)
   elseif type(data) == "string" then
      resolved_size = size == nil and #data or normalize_size("OpenGL buffer size", size)
      scratch = ffi.new("uint8_t[?]", resolved_size)
      if resolved_size > 0 then
         ffi.copy(scratch, data, math.min(#data, resolved_size))
      end
      resolved_data = scratch
   else
      if size == nil then
         local ok, inferred_size = pcall(ffi.sizeof, data)
         if not ok then
            rig.raise("glx.Buffer:set_data requires size for this data value")
         end
         resolved_size = inferred_size
      else
         resolved_size = normalize_size("OpenGL buffer size", size)
      end
   end

   self:bind()
   gl.BufferData(self.target, resolved_size, resolved_data, resolved_usage)
   return resolved_size
end

function Buffer:release()
   ensure_buffer(self)
   if self.id == 0 then
      return
   end

   local buffers = ffi.new("GLuint[1]")
   buffers[0] = self.id
   gl.DeleteBuffers(1, buffers)
   self.id = 0
end

function VertexArray:init()
   local arrays = ffi.new("GLuint[1]")
   gl.GenVertexArrays(1, arrays)

   self.id = tonumber(arrays[0]) or 0
   if self.id == 0 then
      rig.raise("failed to create OpenGL vertex array")
   end
end

function VertexArray:bind()
   ensure_vertex_array_live(self)
   gl.BindVertexArray(self.id)
   return self
end

function VertexArray:attribute(index, size, value_type, normalized, stride, pointer)
   ensure_vertex_array_live(self)

   local resolved_index = normalize_size("OpenGL vertex attribute index", index)
   local resolved_size = normalize_size("OpenGL vertex attribute size", size)
   local resolved_type = tonumber(value_type)
   if resolved_type == nil then
      rig.raise("OpenGL vertex attribute type must be numeric")
   end
   local resolved_stride = normalize_size("OpenGL vertex attribute stride", stride or 0)
   local resolved_pointer = normalize_pointer(pointer)

   self:bind()
   gl.EnableVertexAttribArray(resolved_index)
   gl.VertexAttribPointer(
      resolved_index,
      resolved_size,
      resolved_type,
      normalize_gl_boolean("OpenGL vertex attribute normalized flag", normalized),
      resolved_stride,
      resolved_pointer
   )
   return self
end

function VertexArray:release()
   ensure_vertex_array(self)
   if self.id == 0 then
      return
   end

   local arrays = ffi.new("GLuint[1]")
   arrays[0] = self.id
   gl.DeleteVertexArrays(1, arrays)
   self.id = 0
end

function Texture2D:init()
   local textures = ffi.new("GLuint[1]")
   gl.GenTextures(1, textures)

   self.id = tonumber(textures[0]) or 0
   if self.id == 0 then
      rig.raise("failed to create OpenGL 2D texture")
   end
end

function Texture2D:bind(unit)
   ensure_texture_2d_live(self)

   local resolved_unit = normalize_texture_unit(unit)
   if resolved_unit ~= nil then
      gl.ActiveTexture(gl.TEXTURE0 + resolved_unit)
   end
   gl.BindTexture(gl.TEXTURE_2D, self.id)
   return self
end

function Texture2D:parameter(pname, param)
   ensure_texture_2d_live(self)

   local resolved_pname = normalize_gl_enum("OpenGL texture parameter name", pname)
   local resolved_param = normalize_gl_enum("OpenGL texture parameter value", param)
   self:bind()
   gl.TexParameteri(gl.TEXTURE_2D, resolved_pname, resolved_param)
   return self
end

function Texture2D:image(level, internalformat, width, height, format, value_type, pixels, border)
   ensure_texture_2d_live(self)

   local resolved_level = tonumber(level)
   if resolved_level == nil then
      rig.raise("OpenGL texture image level must be numeric")
   end

   local resolved_internalformat = normalize_gl_enum("OpenGL texture internalformat", internalformat)
   local resolved_width = normalize_size("OpenGL texture width", width)
   local resolved_height = normalize_size("OpenGL texture height", height)
   local resolved_format = normalize_gl_enum("OpenGL texture format", format)
   local resolved_type = normalize_gl_enum("OpenGL texture type", value_type)
   local resolved_border = border == nil and 0 or normalize_size("OpenGL texture border", border)

   self:bind()
   gl.TexImage2D(
      gl.TEXTURE_2D,
      resolved_level,
      resolved_internalformat,
      resolved_width,
      resolved_height,
      resolved_border,
      resolved_format,
      resolved_type,
      pixels
   )
   return self
end

function Texture2D:release()
   ensure_texture_2d(self)
   if self.id == 0 then
      return
   end

   local textures = ffi.new("GLuint[1]")
   textures[0] = self.id
   gl.DeleteTextures(1, textures)
   self.id = 0
end

function M.get_version_string()
   local version = gl.GetString(gl.VERSION)
   if version == nil or version == ffi.NULL then
      return nil
   end
   return ffi.string(version)
end

return M
