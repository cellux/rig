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

test.case("glx provides high-level OpenGL shader, program, buffer, and vertex-array helpers", function()
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
      generated_buffers = {},
      bound_buffers = {},
      buffer_uploads = {},
      deleted_buffers = {},
      generated_vertex_arrays = {},
      bound_vertex_arrays = {},
      deleted_vertex_arrays = {},
      enabled_vertex_attributes = {},
      vertex_attributes = {},
   }
   next_shader_id = 101
   next_program_id = 201
   next_buffer_id = 301
   next_vertex_array_id = 401

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
   test.equal(observed.uniform_location_calls, 1)
   test.equal(observed.version, "4.6 test")
   test.equal(observed.version_name, gl.VERSION)

   test.equal(observed.sourced_shader_id_1, 0)
   test.equal(observed.sourced_shader_id_2, 0)
   test.equal(observed.sourced_program_id_after_release, 0)
   test.equal(observed.manual_shader.id, 0)
   test.equal(observed.adopted_program_id_after_release, 0)
   test.equal(observed.buffer_id_after_release, 0)
   test.equal(observed.vertex_array_id_after_release, 0)

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

   local resolved = {}
   for i = 1, #resolved_names do
      resolved[resolved_names[i]] = true
   end

   test.truthy(resolved.glCreateShader ~= nil)
   test.truthy(resolved.glCreateProgram ~= nil)
   test.truthy(resolved.glGetUniformLocation ~= nil)
   test.truthy(resolved.glGenBuffers ~= nil)
   test.truthy(resolved.glGenVertexArrays ~= nil)
   test.truthy(resolved.glGetString ~= nil)
end)
