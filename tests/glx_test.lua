local test = require("test")
local ffi = require("ffi")
local gl = require("gl")
local glx = require("glx")

local fake_version = ffi.new("GLubyte[9]")
ffi.copy(fake_version, "4.6 test", 8)

local resolved_names
local observed
local next_shader_id
local next_program_id
local next_buffer_id
local next_vertex_array_id
local next_texture_id

local callbacks = {}

callbacks.glGetString = ffi.cast("rig_gl__GetString", function(name)
   observed.version_name = tonumber(name)
   return fake_version
end)

callbacks.glCreateShader = ffi.cast("rig_gl__CreateShader", function(stage)
   local shader_id = next_shader_id
   next_shader_id = next_shader_id + 1
   observed.created_shaders[#observed.created_shaders + 1] = {
      id = shader_id,
      stage = tonumber(stage),
   }
   return shader_id
end)

callbacks.glShaderSource = ffi.cast("rig_gl__ShaderSource", function(shader, count, strings, lengths)
   observed.shader_sources[#observed.shader_sources + 1] = {
      shader = tonumber(shader),
      count = tonumber(count),
      source = ffi.string(strings[0]),
      has_lengths = lengths ~= nil and lengths ~= ffi.NULL,
   }
end)

callbacks.glCompileShader = ffi.cast("rig_gl__CompileShader", function(shader)
   observed.compiled_shaders[#observed.compiled_shaders + 1] = tonumber(shader)
end)

callbacks.glGetShaderiv = ffi.cast("rig_gl__GetShaderiv", function(shader, pname, params)
   local resolved_pname = tonumber(pname)
   observed.shader_iv_calls[#observed.shader_iv_calls + 1] = {
      shader = tonumber(shader),
      pname = resolved_pname,
   }

   if resolved_pname == gl.COMPILE_STATUS then
      params[0] = gl.TRUE
   elseif resolved_pname == gl.INFO_LOG_LENGTH then
      params[0] = 0
   else
      params[0] = 0
   end
end)

callbacks.glDeleteShader = ffi.cast("rig_gl__DeleteShader", function(shader)
   observed.deleted_shaders[#observed.deleted_shaders + 1] = tonumber(shader)
end)

callbacks.glCreateProgram = ffi.cast("rig_gl__CreateProgram", function()
   local program_id = next_program_id
   next_program_id = next_program_id + 1
   observed.created_programs[#observed.created_programs + 1] = program_id
   return program_id
end)

callbacks.glAttachShader = ffi.cast("rig_gl__AttachShader", function(program, shader)
   observed.attached_shaders[#observed.attached_shaders + 1] = {
      program = tonumber(program),
      shader = tonumber(shader),
   }
end)

callbacks.glLinkProgram = ffi.cast("rig_gl__LinkProgram", function(program)
   observed.linked_programs[#observed.linked_programs + 1] = tonumber(program)
end)

callbacks.glGetProgramiv = ffi.cast("rig_gl__GetProgramiv", function(program, pname, params)
   local resolved_pname = tonumber(pname)
   observed.program_iv_calls[#observed.program_iv_calls + 1] = {
      program = tonumber(program),
      pname = resolved_pname,
   }

   if resolved_pname == gl.LINK_STATUS then
      params[0] = gl.TRUE
   elseif resolved_pname == gl.INFO_LOG_LENGTH then
      params[0] = 0
   else
      params[0] = 0
   end
end)

callbacks.glDeleteProgram = ffi.cast("rig_gl__DeleteProgram", function(program)
   observed.deleted_programs[#observed.deleted_programs + 1] = tonumber(program)
end)

callbacks.glUseProgram = ffi.cast("rig_gl__UseProgram", function(program)
   observed.used_programs[#observed.used_programs + 1] = tonumber(program)
end)

callbacks.glUniform1i = ffi.cast("rig_gl__Uniform1i", function(location, v0)
   observed.uniform1i_calls[#observed.uniform1i_calls + 1] = {
      location = tonumber(location),
      v0 = tonumber(v0),
   }
end)

callbacks.glUniform2f = ffi.cast("rig_gl__Uniform2f", function(location, v0, v1)
   observed.uniform2f_calls[#observed.uniform2f_calls + 1] = {
      location = tonumber(location),
      v0 = tonumber(v0),
      v1 = tonumber(v1),
   }
end)

callbacks.glUniform4f = ffi.cast("rig_gl__Uniform4f", function(location, v0, v1, v2, v3)
   observed.uniform4f_calls[#observed.uniform4f_calls + 1] = {
      location = tonumber(location),
      v0 = tonumber(v0),
      v1 = tonumber(v1),
      v2 = tonumber(v2),
      v3 = tonumber(v3),
   }
end)

callbacks.glUniformMatrix4fv = ffi.cast("rig_gl__UniformMatrix4fv", function(location, count, transpose, value)
   observed.uniform_matrix4fv_calls[#observed.uniform_matrix4fv_calls + 1] = {
      location = tonumber(location),
      count = tonumber(count),
      transpose = tonumber(transpose),
      first = tonumber(value[0]),
   }
end)

callbacks.glGetUniformLocation = ffi.cast("rig_gl__GetUniformLocation", function(program, name)
   observed.uniform_location_calls = observed.uniform_location_calls + 1
   observed.uniform_queries[#observed.uniform_queries + 1] = {
      program = tonumber(program),
      name = ffi.string(name),
   }
   return 17
end)

callbacks.glGenBuffers = ffi.cast("rig_gl__GenBuffers", function(n, buffers)
   for i = 0, tonumber(n) - 1 do
      buffers[i] = next_buffer_id
      observed.generated_buffers[#observed.generated_buffers + 1] = next_buffer_id
      next_buffer_id = next_buffer_id + 1
   end
end)

callbacks.glBindBuffer = ffi.cast("rig_gl__BindBuffer", function(target, buffer)
   observed.bound_buffers[#observed.bound_buffers + 1] = {
      target = tonumber(target),
      buffer = tonumber(buffer),
   }
end)

callbacks.glBufferData = ffi.cast("rig_gl__BufferData", function(target, size, data, usage)
   local entry = {
      target = tonumber(target),
      size = tonumber(size),
      usage = tonumber(usage),
      has_data = data ~= nil and data ~= ffi.NULL,
   }
   if entry.has_data and entry.size > 0 then
      entry.bytes = ffi.string(ffi.cast("const char *", data), entry.size)
   end
   observed.buffer_uploads[#observed.buffer_uploads + 1] = entry
end)

callbacks.glDeleteBuffers = ffi.cast("rig_gl__DeleteBuffers", function(n, buffers)
   for i = 0, tonumber(n) - 1 do
      observed.deleted_buffers[#observed.deleted_buffers + 1] = tonumber(buffers[i])
   end
end)

callbacks.glGenVertexArrays = ffi.cast("rig_gl__GenVertexArrays", function(n, arrays)
   for i = 0, tonumber(n) - 1 do
      arrays[i] = next_vertex_array_id
      observed.generated_vertex_arrays[#observed.generated_vertex_arrays + 1] = next_vertex_array_id
      next_vertex_array_id = next_vertex_array_id + 1
   end
end)

callbacks.glBindVertexArray = ffi.cast("rig_gl__BindVertexArray", function(array)
   observed.bound_vertex_arrays[#observed.bound_vertex_arrays + 1] = tonumber(array)
end)

callbacks.glDeleteVertexArrays = ffi.cast("rig_gl__DeleteVertexArrays", function(n, arrays)
   for i = 0, tonumber(n) - 1 do
      observed.deleted_vertex_arrays[#observed.deleted_vertex_arrays + 1] = tonumber(arrays[i])
   end
end)

callbacks.glEnableVertexAttribArray = ffi.cast("rig_gl__EnableVertexAttribArray", function(index)
   observed.enabled_vertex_attributes[#observed.enabled_vertex_attributes + 1] = tonumber(index)
end)

callbacks.glVertexAttribPointer = ffi.cast("rig_gl__VertexAttribPointer", function(index, size, value_type, normalized, stride, pointer)
   observed.vertex_attributes[#observed.vertex_attributes + 1] = {
      index = tonumber(index),
      size = tonumber(size),
      value_type = tonumber(value_type),
      normalized = tonumber(normalized),
      stride = tonumber(stride),
      pointer = tonumber(ffi.cast("uintptr_t", pointer)),
   }
end)

callbacks.glGenTextures = ffi.cast("rig_gl__GenTextures", function(n, textures)
   for i = 0, tonumber(n) - 1 do
      textures[i] = next_texture_id
      observed.generated_textures[#observed.generated_textures + 1] = next_texture_id
      next_texture_id = next_texture_id + 1
   end
end)

callbacks.glBindTexture = ffi.cast("rig_gl__BindTexture", function(target, texture)
   observed.bound_textures[#observed.bound_textures + 1] = {
      target = tonumber(target),
      texture = tonumber(texture),
   }
end)

callbacks.glTexParameteri = ffi.cast("rig_gl__TexParameteri", function(target, pname, param)
   observed.texture_parameters[#observed.texture_parameters + 1] = {
      target = tonumber(target),
      pname = tonumber(pname),
      param = tonumber(param),
   }
end)

callbacks.glDeleteTextures = ffi.cast("rig_gl__DeleteTextures", function(n, textures)
   for i = 0, tonumber(n) - 1 do
      observed.deleted_textures[#observed.deleted_textures + 1] = tonumber(textures[i])
   end
end)

callbacks.glActiveTexture = ffi.cast("rig_gl__ActiveTexture", function(texture)
   observed.active_textures[#observed.active_textures + 1] = tonumber(texture)
end)

callbacks.glTexImage2D = ffi.cast("rig_gl__TexImage2D", function(target, level, internalformat, width, height, border, format, value_type, pixels)
   local entry = {
      target = tonumber(target),
      level = tonumber(level),
      internalformat = tonumber(internalformat),
      width = tonumber(width),
      height = tonumber(height),
      border = tonumber(border),
      format = tonumber(format),
      value_type = tonumber(value_type),
      has_pixels = pixels ~= nil and pixels ~= ffi.NULL,
   }
   if entry.has_pixels and entry.width > 0 and entry.height > 0 then
      local byte_count = entry.width * entry.height * 4
      entry.bytes = ffi.string(ffi.cast("const char *", pixels), byte_count)
   end
   observed.texture_images[#observed.texture_images + 1] = entry
end)

test.case("glx provides high-level OpenGL shader, program, buffer, vertex-array, and texture helpers", function()
   resolved_names = {}
   observed = {
      created_shaders = {},
      shader_sources = {},
      compiled_shaders = {},
      shader_iv_calls = {},
      deleted_shaders = {},
      created_programs = {},
      attached_shaders = {},
      linked_programs = {},
      program_iv_calls = {},
      deleted_programs = {},
      used_programs = {},
      uniform_location_calls = 0,
      uniform_queries = {},
      uniform1i_calls = {},
      uniform2f_calls = {},
      uniform4f_calls = {},
      uniform_matrix4fv_calls = {},
      generated_buffers = {},
      bound_buffers = {},
      buffer_uploads = {},
      deleted_buffers = {},
      generated_vertex_arrays = {},
      bound_vertex_arrays = {},
      deleted_vertex_arrays = {},
      enabled_vertex_attributes = {},
      vertex_attributes = {},
      generated_textures = {},
      bound_textures = {},
      texture_parameters = {},
      deleted_textures = {},
      active_textures = {},
      texture_images = {},
   }
   next_shader_id = 101
   next_program_id = 201
   next_buffer_id = 301
   next_vertex_array_id = 401
   next_texture_id = 501

   rig.register_service_provider("gl.resolver", "glx_test_provider", {
      get_gl_proc_address = function(name)
         resolved_names[#resolved_names + 1] = name
         local callback = callbacks[name]
         if callback == nil then
            return nil, "missing fake callback"
         end
         return ffi.cast("void *", callback)
      end,
   })

   rig.register_runtime_driver("glx_test_driver", {
      loop = function()
         local sourced_program = glx.Program {
            vertex_source = "void main() { }",
            fragment_source = "void main() { }",
         }
         local sourced_shaders = {
            sourced_program.shaders[1],
            sourced_program.shaders[2],
         }

         observed.cached_location_1 = sourced_program:uniform_location("u_color")
         observed.cached_location_2 = sourced_program:uniform_location("u_color")
         observed.sourced_program_id = sourced_program.id
         observed.sourced_program_shader_count = #sourced_program.shaders
         observed.version = glx.get_version_string()
         sourced_program:use()
         sourced_program:set_uniform1i("u_mode", 3)
         sourced_program:set_uniform2f("u_size", 10.5, 20.25)
         sourced_program:set_uniform4f("u_color", 0.1, 0.2, 0.3, 0.4)
         local matrix = ffi.new("float[16]", {
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
         })
         sourced_program:set_uniform_matrix4fv("u_matrix", matrix)
         sourced_program:release()

         observed.sourced_shader_id_1 = sourced_shaders[1].id
         observed.sourced_shader_id_2 = sourced_shaders[2].id
         observed.sourced_program_id_after_release = sourced_program.id

         local manual_shader = glx.Shader {
            stage = "vertex",
            source = "void main() { }",
            source_name = "manual.vert",
         }
         local adopted_program = glx.Program {
            shaders = { manual_shader },
         }

         observed.manual_shader = manual_shader
         observed.adopted_program_id = adopted_program.id
         adopted_program:release()
         observed.adopted_program_id_after_release = adopted_program.id

         local buffer = glx.Buffer {
            target = gl.ARRAY_BUFFER,
         }
         local bytes = ffi.new("uint8_t[4]", { 1, 2, 3, 4 })
         observed.buffer_id = buffer.id
         buffer:set_data("ABCD", gl.STATIC_DRAW)
         buffer:set_data(bytes, gl.DYNAMIC_DRAW)
         buffer:set_data(nil, gl.DYNAMIC_DRAW, 16)
         buffer:release()
         observed.buffer_id_after_release = buffer.id

         local vertex_array = glx.VertexArray()
         observed.vertex_array_id = vertex_array.id
         vertex_array:bind()
         vertex_array:attribute(3, 2, gl.FLOAT, gl.TRUE, 24, 12)
         vertex_array:release()
         observed.vertex_array_id_after_release = vertex_array.id

         local texture = glx.Texture2D()
         local pixels = ffi.new("uint8_t[16]", {
            1, 2, 3, 4,
            5, 6, 7, 8,
            9, 10, 11, 12,
            13, 14, 15, 16,
         })
         observed.texture_id = texture.id
         texture:bind(2)
         texture:parameter(gl.TEXTURE_MIN_FILTER, gl.LINEAR)
         texture:image(0, gl.RGBA, 2, 2, gl.RGBA, gl.UNSIGNED_BYTE, pixels)
         texture:release()
         observed.texture_id_after_release = texture.id
      end,
   })

   rig.run {
      driver = "glx_test_driver",
      providers = {
         ["gl.resolver"] = "glx_test_provider",
      },
   }

   test.equal(observed.sourced_program_shader_count, 2)
   test.equal(observed.cached_location_1, 17)
   test.equal(observed.cached_location_2, 17)
   test.equal(observed.uniform_location_calls, 4)
   test.equal(observed.version, "4.6 test")
   test.equal(observed.version_name, gl.VERSION)
   test.equal(observed.uniform1i_calls[1].location, 17)
   test.equal(observed.uniform1i_calls[1].v0, 3)
   test.equal(observed.uniform2f_calls[1].location, 17)
   test.truthy(math.abs(observed.uniform2f_calls[1].v0 - 10.5) < 0.000001)
   test.truthy(math.abs(observed.uniform2f_calls[1].v1 - 20.25) < 0.000001)
   test.equal(observed.uniform4f_calls[1].location, 17)
   test.truthy(math.abs(observed.uniform4f_calls[1].v0 - 0.1) < 0.000001)
   test.truthy(math.abs(observed.uniform4f_calls[1].v1 - 0.2) < 0.000001)
   test.truthy(math.abs(observed.uniform4f_calls[1].v2 - 0.3) < 0.000001)
   test.truthy(math.abs(observed.uniform4f_calls[1].v3 - 0.4) < 0.000001)
   test.equal(observed.uniform_matrix4fv_calls[1].location, 17)
   test.equal(observed.uniform_matrix4fv_calls[1].count, 1)
   test.equal(observed.uniform_matrix4fv_calls[1].transpose, gl.FALSE)
   test.equal(observed.uniform_matrix4fv_calls[1].first, 1)

   test.equal(observed.sourced_shader_id_1, 0)
   test.equal(observed.sourced_shader_id_2, 0)
   test.equal(observed.sourced_program_id_after_release, 0)
   test.equal(observed.manual_shader.id, 0)
   test.equal(observed.adopted_program_id_after_release, 0)
   test.equal(observed.buffer_id_after_release, 0)
   test.equal(observed.vertex_array_id_after_release, 0)
   test.equal(observed.texture_id_after_release, 0)

   test.equal(observed.buffer_uploads[1].bytes, "ABCD")
   test.equal(observed.buffer_uploads[1].size, 4)
   test.equal(observed.buffer_uploads[2].bytes, string.char(1, 2, 3, 4))
   test.equal(observed.buffer_uploads[2].size, 4)
   test.falsey(observed.buffer_uploads[3].has_data)
   test.equal(observed.buffer_uploads[3].size, 16)
   test.equal(observed.vertex_attributes[1].index, 3)
   test.equal(observed.vertex_attributes[1].size, 2)
   test.equal(observed.vertex_attributes[1].value_type, gl.FLOAT)
   test.equal(observed.vertex_attributes[1].normalized, gl.TRUE)
   test.equal(observed.vertex_attributes[1].stride, 24)
   test.equal(observed.vertex_attributes[1].pointer, 12)
   test.equal(observed.active_textures[1], gl.TEXTURE0 + 2)
   test.equal(observed.texture_parameters[1].target, gl.TEXTURE_2D)
   test.equal(observed.texture_parameters[1].pname, gl.TEXTURE_MIN_FILTER)
   test.equal(observed.texture_parameters[1].param, gl.LINEAR)
   test.equal(observed.texture_images[1].target, gl.TEXTURE_2D)
   test.equal(observed.texture_images[1].width, 2)
   test.equal(observed.texture_images[1].height, 2)
   test.equal(observed.texture_images[1].format, gl.RGBA)
   test.equal(observed.texture_images[1].value_type, gl.UNSIGNED_BYTE)
   test.equal(
      observed.texture_images[1].bytes,
      string.char(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)
   )

   local resolved = {}
   for i = 1, #resolved_names do
      resolved[resolved_names[i]] = true
   end

   test.truthy(resolved.glCreateShader ~= nil)
   test.truthy(resolved.glCreateProgram ~= nil)
   test.truthy(resolved.glGetUniformLocation ~= nil)
   test.truthy(resolved.glUniform1i ~= nil)
   test.truthy(resolved.glUniform2f ~= nil)
   test.truthy(resolved.glUniform4f ~= nil)
   test.truthy(resolved.glUniformMatrix4fv ~= nil)
   test.truthy(resolved.glGenBuffers ~= nil)
   test.truthy(resolved.glGenVertexArrays ~= nil)
   test.truthy(resolved.glGenTextures ~= nil)
   test.truthy(resolved.glBindTexture ~= nil)
   test.truthy(resolved.glTexParameteri ~= nil)
   test.truthy(resolved.glTexImage2D ~= nil)
   test.truthy(resolved.glActiveTexture ~= nil)
   test.truthy(resolved.glGetString ~= nil)
end)
