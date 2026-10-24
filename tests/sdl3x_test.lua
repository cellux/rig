local color = require("color")
local ffi = require("ffi")
local sdl3 = require("sdl3")
local sdl3x = require("sdl3x")
local test = require("test")

local function list_contains(list, expected)
   for i = 1, #list do
      if list[i] == expected then
         return true
      end
   end
   return false
end

local function with_sdl3_property_stubs(run)
   local old_create_properties = sdl3.CreateProperties
   local old_destroy_properties = sdl3.DestroyProperties
   local old_set_pointer_property = sdl3.SetPointerProperty
   local old_set_string_property = sdl3.SetStringProperty
   local old_set_number_property = sdl3.SetNumberProperty
   local old_set_float_property = sdl3.SetFloatProperty
   local old_set_boolean_property = sdl3.SetBooleanProperty
   local old_clear_property = sdl3.ClearProperty

   local observed = {}
   local next_id = 100

   sdl3.CreateProperties = function()
      next_id = next_id + 1
      table.insert(observed, "create:" .. next_id)
      return next_id
   end
   sdl3.DestroyProperties = function(id)
      table.insert(observed, "destroy:" .. tostring(id))
   end
   sdl3.SetPointerProperty = function(id, name, value)
      table.insert(observed, "pointer:" .. tostring(id) .. ":" .. name)
      return value ~= nil
   end
   sdl3.SetStringProperty = function(id, name, value)
      table.insert(observed, "string:" .. tostring(id) .. ":" .. name .. ":" .. value)
      return true
   end
   sdl3.SetNumberProperty = function(id, name, value)
      table.insert(observed, "number:" .. tostring(id) .. ":" .. name .. ":" .. tostring(value))
      return true
   end
   sdl3.SetFloatProperty = function(id, name, value)
      table.insert(observed, "float:" .. tostring(id) .. ":" .. name .. ":" .. tostring(value))
      return true
   end
   sdl3.SetBooleanProperty = function(id, name, value)
      table.insert(observed, "boolean:" .. tostring(id) .. ":" .. name .. ":" .. tostring(value))
      return true
   end
   sdl3.ClearProperty = function(id, name)
      table.insert(observed, "clear:" .. tostring(id) .. ":" .. name)
      return true
   end

   local ok, result_or_err = pcall(run, observed)

   sdl3.CreateProperties = old_create_properties
   sdl3.DestroyProperties = old_destroy_properties
   sdl3.SetPointerProperty = old_set_pointer_property
   sdl3.SetStringProperty = old_set_string_property
   sdl3.SetNumberProperty = old_set_number_property
   sdl3.SetFloatProperty = old_set_float_property
   sdl3.SetBooleanProperty = old_set_boolean_property
   sdl3.ClearProperty = old_clear_property

   if not ok then
      error(result_or_err)
   end

   return result_or_err
end

local function find_font_path()
   local candidates = {
      "/usr/share/fonts/TTF/DejaVuSans.ttf",
      "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
      "/usr/share/fonts/dejavu/DejaVuSans.ttf",
   }

   for i = 1, #candidates do
      local path = candidates[i]
      local file = io.open(path, "rb")
      if file ~= nil then
         file:close()
         return path
      end
   end

   return nil
end

test.case("sdl3x.App stores resize events in app fields", function()
   local app = sdl3x.App()
   app:on_resize({
      width = 320,
      height = 200,
      pixel_width = 640,
      pixel_height = 400,
   })

   test.equal(app.window_width, 320)
   test.equal(app.window_height, 200)
   test.equal(app.pixel_width, 640)
   test.equal(app.pixel_height, 400)
end)

test.case("sdl3x.get_error returns SDL error text or fallback", function()
   local old_get_error = sdl3.GetError
   local ok, err = pcall(function()
      local message = "stubbed SDL error"
      local buffer = ffi.new("char[?]", #message + 1)
      ffi.copy(buffer, message)
      sdl3.GetError = function()
         return buffer
      end
      test.equal(sdl3x.get_error(), message)

      sdl3.GetError = function()
         return ffi.NULL
      end
      test.equal(sdl3x.get_error("fallback"), "fallback")
      test.equal(sdl3x.get_error(), "unknown SDL error")
   end)

   sdl3.GetError = old_get_error
   if not ok then
      error(err)
   end
end)

test.case("sdl3x.free ignores nil and forwards non-null pointers to SDL", function()
   local old_free = sdl3.free
   local observed = {}

   local ok, err = pcall(function()
      sdl3.free = function(ptr)
         table.insert(observed, ptr)
      end

      sdl3x.free(nil)
      sdl3x.free(ffi.NULL)

      local pointer = ffi.new("uint8_t[1]")
      sdl3x.free(pointer)

      test.equal(#observed, 1)
      test.truthy(observed[1] ~= nil)
      test.truthy(observed[1] ~= ffi.NULL)
   end)

   sdl3.free = old_free
   if not ok then
      error(err)
   end
end)

test.case("sdl3x.Properties exposes a live props.id and owns SDL properties", function()
   with_sdl3_property_stubs(function(observed)
      local pointer = ffi.new("int[1]")
      local props = sdl3x.Properties({
         enabled = true,
         count = 7,
         scale = 1.5,
         title = "rig",
      })

      test.equal(props.id, 101)
      test.truthy(props:has("enabled"))
      test.equal(props:get("count"), 7)
      test.equal(props:get("missing", "fallback"), "fallback")

      props:set("pointer", pointer)
      props:clear("title")

      local clone = props:clone()
      test.equal(clone.id, 102)
      test.truthy(clone:has("pointer"))
      test.equal(clone:get("count"), 7)

      local values = props:to_table()
      test.equal(values.count, 7)
      test.falsey(values.title ~= nil)

      props:release()
      clone:release()

      test.equal(props.id, 0)
      test.equal(clone.id, 0)
      test.truthy(list_contains(observed, "create:101"))
      test.truthy(list_contains(observed, "boolean:101:enabled:true"))
      test.truthy(list_contains(observed, "number:101:count:7"))
      test.truthy(list_contains(observed, "float:101:scale:1.5"))
      test.truthy(list_contains(observed, "string:101:title:rig"))
      test.truthy(list_contains(observed, "pointer:101:pointer"))
      test.truthy(list_contains(observed, "clear:101:title"))
      test.truthy(list_contains(observed, "create:102"))
      test.truthy(list_contains(observed, "boolean:102:enabled:true"))
      test.truthy(list_contains(observed, "number:102:count:7"))
      test.truthy(list_contains(observed, "float:102:scale:1.5"))
      test.truthy(list_contains(observed, "pointer:102:pointer"))
      test.truthy(list_contains(observed, "destroy:101"))
      test.truthy(list_contains(observed, "destroy:102"))
   end)
end)

test.case("sdl3x.normalize_properties_id accepts raw ids and sdl3x.Properties", function()
   test.equal(sdl3x.normalize_properties_id(nil), 0)
   test.equal(sdl3x.normalize_properties_id(55), 55)

   with_sdl3_property_stubs(function()
      local props = sdl3x.Properties()
      test.equal(sdl3x.normalize_properties_id(props), 101)
      props:release()
   end)
end)

test.case("sdl3x.normalize_properties_id rejects ad hoc props tables", function()
   local ok, err = pcall(function()
      sdl3x.normalize_properties_id({
         id = 77,
      })
   end)

   test.falsey(ok)
   test.match(
      tostring(err),
      "props expects a number, cdata SDL_PropertiesID, or sdl3x%.Properties"
   )
end)

test.case("sdl3x.Window builds temporary SDL properties", function()
   local old_create_window = sdl3.CreateWindowWithProperties
   local old_get_primary_display = sdl3.GetPrimaryDisplay
   local old_get_display_usable_bounds = sdl3.GetDisplayUsableBounds

   with_sdl3_property_stubs(function(observed)
      local seen_props_id = nil
      local expected_window = ffi.cast("SDL_Window *", 0x1234)

      sdl3.GetPrimaryDisplay = function()
         return 0
      end
      sdl3.GetDisplayUsableBounds = function()
         return false
      end
      sdl3.CreateWindowWithProperties = function(props_id)
         seen_props_id = props_id
         return expected_window
      end

      local window = sdl3x.Window({
         window_props = {
            [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "hello",
            [sdl3.PROP_WINDOW_CREATE_WIDTH_NUMBER] = 320,
            [sdl3.PROP_WINDOW_CREATE_HEIGHT_NUMBER] = 180,
         },
      })

      test.truthy(sdl3x.Window:is_instance(window))
      test.equal(window.ptr, expected_window)
      test.equal(seen_props_id, 101)
      test.truthy(list_contains(observed, "create:101"))
      test.truthy(list_contains(
         observed,
         "string:101:" .. sdl3.PROP_WINDOW_CREATE_TITLE_STRING .. ":hello"
      ))
      test.truthy(list_contains(
         observed,
         "number:101:" .. sdl3.PROP_WINDOW_CREATE_WIDTH_NUMBER .. ":320"
      ))
      test.truthy(list_contains(
         observed,
         "number:101:" .. sdl3.PROP_WINDOW_CREATE_HEIGHT_NUMBER .. ":180"
      ))
      test.truthy(list_contains(observed, "destroy:101"))
   end)

   sdl3.CreateWindowWithProperties = old_create_window
   sdl3.GetPrimaryDisplay = old_get_primary_display
   sdl3.GetDisplayUsableBounds = old_get_display_usable_bounds
end)

test.case("sdl3x.Window exposes size, fullscreen, sync, and release", function()
   local old_create_window = sdl3.CreateWindowWithProperties
   local old_get_primary_display = sdl3.GetPrimaryDisplay
   local old_get_display_usable_bounds = sdl3.GetDisplayUsableBounds
   local old_get_window_size = sdl3.GetWindowSize
   local old_get_window_size_in_pixels = sdl3.GetWindowSizeInPixels
   local old_set_window_fullscreen = sdl3.SetWindowFullscreen
   local old_sync_window = sdl3.SyncWindow
   local old_destroy_window = sdl3.DestroyWindow

   with_sdl3_property_stubs(function()
      local expected_window = ffi.cast("SDL_Window *", 0x1234)
      local observed_fullscreen = nil
      local observed_sync = false
      local observed_destroy = nil

      sdl3.GetPrimaryDisplay = function()
         return 0
      end
      sdl3.GetDisplayUsableBounds = function()
         return false
      end
      sdl3.CreateWindowWithProperties = function()
         return expected_window
      end
      sdl3.GetWindowSize = function(_, width_out, height_out)
         width_out[0] = 320
         height_out[0] = 180
         return true
      end
      sdl3.GetWindowSizeInPixels = function(_, width_out, height_out)
         width_out[0] = 640
         height_out[0] = 360
         return true
      end
      sdl3.SetWindowFullscreen = function(_, enabled)
         observed_fullscreen = enabled
         return true
      end
      sdl3.SyncWindow = function()
         observed_sync = true
         return true
      end
      sdl3.DestroyWindow = function(ptr)
         observed_destroy = ptr
      end

      local window = sdl3x.Window()
      local width, height = window:get_size()
      local pixel_width, pixel_height = window:get_size_in_pixels()

      test.equal(width, 320)
      test.equal(height, 180)
      test.equal(pixel_width, 640)
      test.equal(pixel_height, 360)

      window:set_fullscreen(true)
      window:sync()
      window:release()

      test.truthy(observed_fullscreen)
      test.truthy(observed_sync)
      test.equal(observed_destroy, expected_window)
      test.equal(window.ptr, nil)
   end)

   sdl3.CreateWindowWithProperties = old_create_window
   sdl3.GetPrimaryDisplay = old_get_primary_display
   sdl3.GetDisplayUsableBounds = old_get_display_usable_bounds
   sdl3.GetWindowSize = old_get_window_size
   sdl3.GetWindowSizeInPixels = old_get_window_size_in_pixels
   sdl3.SetWindowFullscreen = old_set_window_fullscreen
   sdl3.SyncWindow = old_sync_window
   sdl3.DestroyWindow = old_destroy_window
end)

test.case("sdl3x GPU builders accept sdl3x.Properties", function()
   with_sdl3_property_stubs(function()
      local props = sdl3x.Properties()
      local usage = sdl3.GPU_BUFFERUSAGE_VERTEX + sdl3.GPU_BUFFERUSAGE_INDIRECT
      local buffer_info = sdl3x.build_gpu_buffer_create_info({
         usage = usage,
         size = 64,
         props = props,
      })

      test.equal(tonumber(buffer_info[0].usage), usage)
      test.equal(tonumber(buffer_info[0].props), 101)
      props:release()
   end)
end)

test.case("sdl3x.ResourceScope constructs an SDL GPU scope", function()
   local device = ffi.cast("SDL_GPUDevice *", 0x1234)
   local scope = sdl3x.ResourceScope(device)

   test.truthy(sdl3x.ResourceScope:is_instance(scope))
   test.truthy(rig.ResourceScope:is_instance(scope))
   test.equal(getmetatable(scope), sdl3x.ResourceScope)
   test.equal(scope.context, device)
   test.equal(scope._scope_label, "sdl3x resource scope")
end)

test.case("sdl3x GPU descriptor builders populate FFI structs", function()
   local vertex_buffers = sdl3x.build_vertex_buffer_descriptions({
      {
         pitch = 24,
      },
   })
   test.equal(tonumber(vertex_buffers[0].slot), 0)
   test.equal(tonumber(vertex_buffers[0].pitch), 24)

   local attributes = sdl3x.build_vertex_attributes({
      {
         location = 3,
         format = "FLOAT3",
         offset = 12,
      },
   })
   test.equal(tonumber(attributes[0].location), 3)
   test.equal(tonumber(attributes[0].offset), 12)

   local color_targets = sdl3x.build_color_target_descriptions({
      {
         format = sdl3.GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
         blend_state = {
            enable_blend = true,
            src_color_blendfactor = sdl3.GPU_BLENDFACTOR_SRC_ALPHA,
            dst_color_blendfactor = sdl3.GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
            color_blend_op = sdl3.GPU_BLENDOP_ADD,
            color_write_mask = sdl3.GPU_COLORCOMPONENT_R + sdl3.GPU_COLORCOMPONENT_A,
         },
      },
   })
   test.equal(
      tonumber(color_targets[0].format),
      sdl3.GPU_TEXTUREFORMAT_R8G8B8A8_UNORM
   )
   test.equal(
      tonumber(color_targets[0].blend_state.src_color_blendfactor),
      sdl3.GPU_BLENDFACTOR_SRC_ALPHA
   )
   test.equal(
      tonumber(color_targets[0].blend_state.dst_color_blendfactor),
      sdl3.GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA
   )
   test.equal(
      tonumber(color_targets[0].blend_state.color_blend_op),
      sdl3.GPU_BLENDOP_ADD
   )
   test.equal(
      tonumber(color_targets[0].blend_state.color_write_mask),
      sdl3.GPU_COLORCOMPONENT_R + sdl3.GPU_COLORCOMPONENT_A
   )
   test.truthy(color_targets[0].blend_state.enable_blend)
end)

test.case("sdl3x vertex input state builder retains descriptor storage", function()
   local bundle = sdl3x.build_vertex_input_state({
      buffers = {
         {
            pitch = 24,
            attributes = {
               {
                  location = 0,
                  format = "FLOAT3",
                  offset = 0,
               },
            },
         },
      },
   })

   test.equal(tonumber(bundle.cdata[0].num_vertex_buffers), 1)
   test.equal(tonumber(bundle.cdata[0].num_vertex_attributes), 1)
   test.equal(bundle.cdata[0].vertex_buffer_descriptions, bundle.vertex_buffer_descriptions)
   test.equal(bundle.cdata[0].vertex_attributes, bundle.vertex_attributes)
   test.equal(#bundle.keepalive, 2)
end)

test.case("sdl3x vertex input state builder rejects unsupported numeric input rates", function()
   local ok, err = pcall(function()
      sdl3x.build_vertex_input_state({
         buffers = {
            {
               pitch = 24,
               input_rate = 12345,
               attributes = {
                  {
                     location = 0,
                     format = "FLOAT3",
                     offset = 0,
                  },
               },
            },
         },
      })
   end)

   test.falsey(ok)
   test.match(
      tostring(err),
      "sdl3x%.build_vertex_input_state layout%.buffers%[1%]%.input_rate expects a vertex input rate"
   )
end)

test.case("sdl3x value schemas normalize supported values", function()
   test.equal(
      sdl3x.GPUShaderFormat("SPIRV"),
      sdl3.GPU_SHADERFORMAT_SPIRV
   )
   test.equal(
      sdl3x.GPUShaderStage("VERTEX"),
      sdl3.GPU_SHADERSTAGE_VERTEX
   )
   test.equal(
      sdl3x.GPUPrimitiveType("TRIANGLELIST"),
      sdl3.GPU_PRIMITIVETYPE_TRIANGLELIST
   )
   test.equal(
      sdl3x.GPUSampleCount("4"),
      sdl3.GPU_SAMPLECOUNT_4
   )
   test.equal(
      sdl3x.GPUFillMode("FILL"),
      sdl3.GPU_FILLMODE_FILL
   )
   test.equal(
      sdl3x.GPUCullMode("BACK"),
      sdl3.GPU_CULLMODE_BACK
   )
   test.equal(
      sdl3x.GPUFrontFace("COUNTER_CLOCKWISE"),
      sdl3.GPU_FRONTFACE_COUNTER_CLOCKWISE
   )
   test.equal(
      sdl3x.GPUCompareOp("LESS"),
      sdl3.GPU_COMPAREOP_LESS
   )
   test.equal(
      sdl3x.GPUStencilOp("KEEP"),
      sdl3.GPU_STENCILOP_KEEP
   )
   test.equal(
      sdl3x.GPUBlendOp("ADD"),
      sdl3.GPU_BLENDOP_ADD
   )
   test.equal(
      sdl3x.GPUBlendFactor("SRC_ALPHA"),
      sdl3.GPU_BLENDFACTOR_SRC_ALPHA
   )
   test.equal(
      sdl3x.GPUColorComponentFlags(
         sdl3.GPU_COLORCOMPONENT_R + sdl3.GPU_COLORCOMPONENT_A
      ),
      sdl3.GPU_COLORCOMPONENT_R + sdl3.GPU_COLORCOMPONENT_A
   )
   test.equal(
      sdl3x.GPUBufferUsageFlags(
         sdl3.GPU_BUFFERUSAGE_VERTEX + sdl3.GPU_BUFFERUSAGE_INDIRECT
      ),
      sdl3.GPU_BUFFERUSAGE_VERTEX + sdl3.GPU_BUFFERUSAGE_INDIRECT
   )
   test.equal(
      sdl3x.GPUVertexInputRate("vertex"),
      sdl3.GPU_VERTEXINPUTRATE_VERTEX
   )
   test.equal(
      sdl3x.GPUVertexInputRate(sdl3.GPU_VERTEXINPUTRATE_INSTANCE),
      sdl3.GPU_VERTEXINPUTRATE_INSTANCE
   )
   test.equal(
      sdl3x.GPUVertexElementFormat("FLOAT3"),
      sdl3.GPU_VERTEXELEMENTFORMAT_FLOAT3
   )
   test.equal(
      sdl3x.GPUVertexElementFormat("INT2"),
      sdl3.GPU_VERTEXELEMENTFORMAT_INT2
   )
   test.equal(
      sdl3x.GPUVertexElementFormat("HALF4"),
      sdl3.GPU_VERTEXELEMENTFORMAT_HALF4
   )
   test.equal(
      sdl3x.GPUVertexElementFormat(sdl3.GPU_VERTEXELEMENTFORMAT_FLOAT4),
      sdl3.GPU_VERTEXELEMENTFORMAT_FLOAT4
   )
   test.equal(
      sdl3x.GPUTextureFormat("R8G8B8A8_UNORM"),
      sdl3.GPU_TEXTUREFORMAT_R8G8B8A8_UNORM
   )
   test.equal(
      sdl3x.GPUTextureFormat(sdl3.GPU_TEXTUREFORMAT_R8G8B8A8_UNORM),
      sdl3.GPU_TEXTUREFORMAT_R8G8B8A8_UNORM
   )

   local input_rate_ok, input_rate_err = pcall(function()
      sdl3x.GPUVertexInputRate("bad")
   end)
   test.falsey(input_rate_ok)
   test.match(
      tostring(input_rate_err),
      "value expects a vertex input rate"
   )

   local format_ok, format_err = pcall(function()
      sdl3x.GPUVertexElementFormat("bad")
   end)
   test.falsey(format_ok)
   test.match(
      tostring(format_err),
      "value expects a vertex element format"
   )

   local texture_format_ok, texture_format_err = pcall(function()
      sdl3x.GPUTextureFormat(12345)
   end)
   test.falsey(texture_format_ok)
   test.match(
      tostring(texture_format_err),
      "value expects a GPU texture format"
   )

   local primitive_type_ok, primitive_type_err = pcall(function()
      sdl3x.GPUPrimitiveType("BAD")
   end)
   test.falsey(primitive_type_ok)
   test.match(
      tostring(primitive_type_err),
      "value expects a GPU primitive type"
   )

   local usage_ok, usage_err = pcall(function()
      sdl3x.GPUBufferUsageFlags(64)
   end)
   test.falsey(usage_ok)
   test.match(
      tostring(usage_err),
      "value expects GPU buffer usage flags"
   )

   local color_component_ok, color_component_err = pcall(function()
      sdl3x.GPUColorComponentFlags(16)
   end)
   test.falsey(color_component_ok)
   test.match(
      tostring(color_component_err),
      "value expects GPU color component flags"
   )

   local stencil_op_ok, stencil_op_err = pcall(function()
      sdl3x.GPUStencilOp("BAD")
   end)
   test.falsey(stencil_op_ok)
   test.match(
      tostring(stencil_op_err),
      "value expects a GPU stencil op"
   )
end)

test.case("sdl3x graphics pipeline builder populates FFI structs", function()
   local bundle = sdl3x.build_graphics_pipeline_create_info({
      primitive_type = sdl3.GPU_PRIMITIVETYPE_LINESTRIP,
      props = 22,
      depth_stencil_state = {
         compare_op = sdl3.GPU_COMPAREOP_LESS,
         back_stencil_state = {
            fail_op = sdl3.GPU_STENCILOP_KEEP,
            pass_op = sdl3.GPU_STENCILOP_REPLACE,
            depth_fail_op = sdl3.GPU_STENCILOP_ZERO,
            compare_op = sdl3.GPU_COMPAREOP_ALWAYS,
         },
         front_stencil_state = {
            fail_op = sdl3.GPU_STENCILOP_INVERT,
            pass_op = sdl3.GPU_STENCILOP_INCREMENT_AND_WRAP,
            depth_fail_op = sdl3.GPU_STENCILOP_DECREMENT_AND_WRAP,
            compare_op = sdl3.GPU_COMPAREOP_NOT_EQUAL,
         },
      },
      target_info = {
         depth_stencil_format = sdl3.GPU_TEXTUREFORMAT_D32_FLOAT,
         has_depth_stencil_target = true,
         color_target_descriptions = {
            {
               format = sdl3.GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
            },
         },
      },
   })

   test.equal(
      tonumber(bundle.create_info[0].primitive_type),
      sdl3.GPU_PRIMITIVETYPE_LINESTRIP
   )
   test.equal(tonumber(bundle.create_info[0].props), 22)
   test.equal(
      tonumber(bundle.create_info[0].depth_stencil_state.compare_op),
      sdl3.GPU_COMPAREOP_LESS
   )
   test.equal(
      tonumber(bundle.create_info[0].depth_stencil_state.back_stencil_state.fail_op),
      sdl3.GPU_STENCILOP_KEEP
   )
   test.equal(
      tonumber(bundle.create_info[0].depth_stencil_state.back_stencil_state.pass_op),
      sdl3.GPU_STENCILOP_REPLACE
   )
   test.equal(
      tonumber(bundle.create_info[0].depth_stencil_state.back_stencil_state.depth_fail_op),
      sdl3.GPU_STENCILOP_ZERO
   )
   test.equal(
      tonumber(bundle.create_info[0].depth_stencil_state.back_stencil_state.compare_op),
      sdl3.GPU_COMPAREOP_ALWAYS
   )
   test.equal(
      tonumber(bundle.create_info[0].depth_stencil_state.front_stencil_state.fail_op),
      sdl3.GPU_STENCILOP_INVERT
   )
   test.equal(
      tonumber(bundle.create_info[0].depth_stencil_state.front_stencil_state.pass_op),
      sdl3.GPU_STENCILOP_INCREMENT_AND_WRAP
   )
   test.equal(
      tonumber(bundle.create_info[0].depth_stencil_state.front_stencil_state.depth_fail_op),
      sdl3.GPU_STENCILOP_DECREMENT_AND_WRAP
   )
   test.equal(
      tonumber(bundle.create_info[0].depth_stencil_state.front_stencil_state.compare_op),
      sdl3.GPU_COMPAREOP_NOT_EQUAL
   )
   test.equal(
      tonumber(bundle.create_info[0].target_info.depth_stencil_format),
      sdl3.GPU_TEXTUREFORMAT_D32_FLOAT
   )
   test.equal(
      tonumber(bundle.create_info[0].target_info.color_target_descriptions[0].format),
      sdl3.GPU_TEXTUREFORMAT_R8G8B8A8_UNORM
   )
   test.equal(tonumber(bundle.create_info[0].target_info.num_color_targets), 1)
   test.truthy(bundle.create_info[0].target_info.has_depth_stencil_target)
end)

test.case("sdl3x graphics pipeline builder rejects out-of-range Uint8 masks", function()
   local ok, err = pcall(function()
      sdl3x.build_graphics_pipeline_create_info({
         primitive_type = sdl3.GPU_PRIMITIVETYPE_LINESTRIP,
         depth_stencil_state = {
            compare_mask = 256,
         },
      })
   end)

   test.falsey(ok)
   test.match(
      tostring(err),
      "sdl3x%.build_graphics_pipeline_create_info spec%.depth_stencil_state%.compare_mask expects an integer >= 0 and <= 255"
   )
end)

test.case("sdl3x graphics pipeline builder accepts sdl3x.GPUShader objects", function()
   local vertex_shader_ptr = ffi.cast("SDL_GPUShader *", 0x1234)
   local fragment_shader_ptr = ffi.cast("SDL_GPUShader *", 0x5678)
   local vertex_shader = setmetatable({
      device = ffi.cast("SDL_GPUDevice *", 0x1111),
      ptr = vertex_shader_ptr,
      _released = false,
   }, sdl3x.GPUShader)
   local fragment_shader = setmetatable({
      device = ffi.cast("SDL_GPUDevice *", 0x1111),
      ptr = fragment_shader_ptr,
      _released = false,
   }, sdl3x.GPUShader)

   local bundle = sdl3x.build_graphics_pipeline_create_info({
      primitive_type = sdl3.GPU_PRIMITIVETYPE_LINESTRIP,
      vertex_shader = vertex_shader,
      fragment_shader = fragment_shader,
      props = 0,
   })

   test.equal(bundle.create_info[0].vertex_shader, vertex_shader_ptr)
   test.equal(bundle.create_info[0].fragment_shader, fragment_shader_ptr)
   test.equal(#bundle.keepalive, 2)
   test.truthy(list_contains(bundle.keepalive, vertex_shader))
   test.truthy(list_contains(bundle.keepalive, fragment_shader))
end)

test.case("sdl3x.create_gpu_shader returns an sdl3x.GPUShader", function()
   local old_create_gpu_shader = sdl3.CreateGPUShader
   local old_release_gpu_shader = sdl3.ReleaseGPUShader
   local observed = nil
   local released = nil
   local device = ffi.cast("SDL_GPUDevice *", 0x1234)
   local shader_ptr = ffi.cast("SDL_GPUShader *", 0x5678)

   local ok, err = pcall(function()
      sdl3.CreateGPUShader = function(seen_device, create_info)
         observed = {
            device = seen_device,
            code = ffi.string(create_info[0].code, create_info[0].code_size),
            code_size = tonumber(create_info[0].code_size),
            entrypoint = ffi.string(create_info[0].entrypoint),
            format = tonumber(create_info[0].format),
            stage = tonumber(create_info[0].stage),
            num_samplers = tonumber(create_info[0].num_samplers),
            num_storage_textures = tonumber(create_info[0].num_storage_textures),
            num_storage_buffers = tonumber(create_info[0].num_storage_buffers),
            num_uniform_buffers = tonumber(create_info[0].num_uniform_buffers),
            props = tonumber(create_info[0].props),
         }
         return shader_ptr
      end
      sdl3.ReleaseGPUShader = function(seen_device, seen_shader)
         released = {
            device = seen_device,
            shader = seen_shader,
         }
      end

      local result = sdl3x.create_gpu_shader(device, {
         stage = "vertex",
         format = "spirv",
         entrypoint = "vs_main",
         bytecode = "\1\2\3\4",
         reflection = {
            resource_info = {
               num_uniform_buffers = 2,
            },
            resources = {
               uniform_buffers = {
                  {
                     name = "Globals",
                     set = 1,
                  },
               },
            },
         },
      }, 77)

      test.truthy(sdl3x.GPUShader:is_instance(result))
      test.equal(result.device, device)
      test.equal(result.ptr, shader_ptr)
      test.equal(result.stage, "vertex")
      test.equal(result.entrypoint, "vs_main")

      result:release()
      test.equal(result.ptr, nil)
   end)

   sdl3.CreateGPUShader = old_create_gpu_shader
   sdl3.ReleaseGPUShader = old_release_gpu_shader
   if not ok then
      error(err)
   end

   test.equal(observed.device, device)
   test.equal(observed.code, "\1\2\3\4")
   test.equal(observed.code_size, 4)
   test.equal(observed.entrypoint, "vs_main")
   test.equal(observed.format, tonumber(sdl3.GPU_SHADERFORMAT_SPIRV))
   test.equal(observed.stage, tonumber(sdl3.GPU_SHADERSTAGE_VERTEX))
   test.equal(observed.num_samplers, 0)
   test.equal(observed.num_storage_textures, 0)
   test.equal(observed.num_storage_buffers, 0)
   test.equal(observed.num_uniform_buffers, 2)
   test.equal(observed.props, 77)
   test.equal(released.device, device)
   test.equal(released.shader, shader_ptr)
end)

test.case("sdl3x.App wraps render calls with profiler hooks when enabled", function()
   local observed = {}
   local TestApp = rig.Class(sdl3x.App)

   function TestApp:init()
      self:super().init(self)
      self.frame_profiler = {
         begin_frame = function()
            table.insert(observed, "begin_frame")
         end,
         end_frame = function()
            table.insert(observed, "end_frame")
         end,
         begin_cpu = function()
            table.insert(observed, "begin_cpu")
         end,
         end_cpu = function()
            table.insert(observed, "end_cpu")
         end,
      }
      self.frame_profiler_enabled = true
   end

   function TestApp:render(label)
      table.insert(observed, "render:" .. label)
      return "ok:" .. label
   end

   local app = TestApp()
   app:before_frame()
   local result = app:invoke_render("frame")
   app:after_frame()

   test.equal(result, "ok:frame")
   test.equal(#observed, 5)
   test.equal(observed[1], "begin_frame")
   test.equal(observed[2], "begin_cpu")
   test.equal(observed[3], "render:frame")
   test.equal(observed[4], "end_cpu")
   test.equal(observed[5], "end_frame")
end)

test.case("sdl3x.App toggles renderer vsync through the graphics context", function()
   local app = sdl3x.App()
   local observed_enabled = nil

   app.graphics = {
      set_vsync = function(enabled)
         observed_enabled = enabled
      end,
   }

   app:set_vsync(false)
   test.equal(observed_enabled, false)
   test.falsey(app.vsync_enabled)
end)

test.case("sdl3x.App toggles fullscreen through SDL", function()
   local app = sdl3x.App()
   local observed_enabled = nil
   local observed_sync = false

   app.window = {
      set_fullscreen = function(_, enabled)
         observed_enabled = enabled
      end,
      sync = function()
         observed_sync = true
      end,
   }

   app:set_fullscreen(true)
   test.truthy(observed_enabled)
   test.truthy(observed_sync)
   test.truthy(app.fullscreen_enabled)
end)

test.case("sdl3x.App owns loaded font faces and releases them on shutdown", function()
   local font_path = find_font_path()
   if font_path == nil then
      return
   end

   local app = sdl3x.App()
   local face = app:load_font_face("body", font_path)

   test.equal(app:get_font_face("body"), face)

   app:before_shutdown()
   test.equal(app:get_font_face("body"), nil)
end)

test.case("GpuRenderScene keeps the inherited scene interface fields", function()
   local graphics = { device = {}, window = {} }
   local gpu_scene = sdl3x.GpuRenderScene {
      name = "scene",
      graphics = graphics,
   }

   test.equal(gpu_scene.graphics, graphics)
   test.equal(gpu_scene.device, graphics.device)
   test.equal(gpu_scene.window, graphics.window)
   test.truthy(gpu_scene.children ~= nil)
   test.truthy(gpu_scene.local_matrix ~= nil)
   test.equal(gpu_scene.depth_format, nil)
end)

test.case("RendererRenderScene tracks the window pixel size each frame", function()
   local cleared = 0
   local graphics = {
      window = {
         get_size_in_pixels = function()
            return 640, 480
         end,
      },
      clear = function()
         cleared = cleared + 1
      end,
   }

   local renderer_scene = sdl3x.RendererRenderScene {
      name = "scene",
      graphics = graphics,
      background_color = color.rgb(0, 0, 0),
   }

   test.equal(renderer_scene.width, 1)
   test.equal(renderer_scene.height, 1)

   renderer_scene:begin_frame()

   test.equal(renderer_scene.width, 640)
   test.equal(renderer_scene.height, 480)
   test.equal(cleared, 1)
end)
