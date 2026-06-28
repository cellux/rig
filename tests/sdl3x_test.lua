local animator = require("animator")
local ffi = require("ffi")
local scenegraph = require("scenegraph")
local sdl3 = require("sdl3")
local sdl3x = require("sdl3x")
local test = require("test")

local Object = scenegraph.Object

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

test.case("sdl3x runtime options validate driver config shapes", function()
   local bad_config_ok, bad_config_err = pcall(function()
      rig.run {
         driver = "sdl3",
         driver_config = {
            sdl3 = "bad",
         },
      }
   end)
   test.falsey(bad_config_ok)
   test.match(
      tostring(bad_config_err),
      "rig%.run options%.driver_config%.sdl3 expects a table"
   )
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
      "props must be a number, cdata SDL_PropertiesID, or sdl3x%.Properties"
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
      local buffer_info = sdl3x.build_gpu_buffer_create_info({
         usage = 5,
         size = 64,
         props = props,
      })

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
         format = "float3",
         offset = 12,
      },
   })
   test.equal(tonumber(attributes[0].location), 3)
   test.equal(tonumber(attributes[0].offset), 12)

   local color_targets = sdl3x.build_color_target_descriptions({
      {
         format = 9,
         blend_state = {
            enable_blend = true,
         },
      },
   })
   test.equal(tonumber(color_targets[0].format), 9)
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
                  format = "float3",
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

test.case("sdl3x graphics pipeline builder populates FFI structs", function()
   local bundle = sdl3x.build_graphics_pipeline_create_info({
      primitive_type = 3,
      props = 22,
      target_info = {
         depth_stencil_format = 7,
         has_depth_stencil_target = true,
         color_target_descriptions = {
            {
               format = 9,
            },
         },
      },
   })

   test.equal(tonumber(bundle.create_info[0].primitive_type), 3)
   test.equal(tonumber(bundle.create_info[0].props), 22)
   test.equal(
      tonumber(bundle.create_info[0].target_info.depth_stencil_format),
      7
   )
   test.equal(tonumber(bundle.create_info[0].target_info.num_color_targets), 1)
   test.truthy(bundle.create_info[0].target_info.has_depth_stencil_target)
end)

test.case("sdl3x.create_gpu_shader builds SDL_GPUShaderCreateInfo through schema", function()
   local old_create_gpu_shader = sdl3.CreateGPUShader
   local observed = nil
   local device = ffi.cast("SDL_GPUDevice *", 0x1234)
   local shader = ffi.cast("SDL_GPUShader *", 0x5678)

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
         return shader
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

      test.equal(result, shader)
   end)

   sdl3.CreateGPUShader = old_create_gpu_shader
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

test.case("sdl3x.App toggles renderer vsync through SDL", function()
   local app = sdl3x.App()
   local old_get_renderer = sdl3x.get_renderer
   local old_get_gl_context = sdl3x.get_gl_context
   local old_set_render_vsync = sdl3.SetRenderVSync
   local observed_interval = nil

   sdl3x.get_renderer = function()
      return {}
   end
   sdl3x.get_gl_context = function()
      return nil
   end
   sdl3.SetRenderVSync = function(_, interval)
      observed_interval = interval
      return true
   end

   app:set_vsync(false)
   test.equal(observed_interval, 0)
   test.falsey(app.vsync_enabled)

   sdl3x.get_renderer = old_get_renderer
   sdl3x.get_gl_context = old_get_gl_context
   sdl3.SetRenderVSync = old_set_render_vsync
end)

test.case("sdl3x.App toggles fullscreen through SDL", function()
   local app = sdl3x.App()
   local old_get_window = sdl3x.get_window
   local observed_enabled = nil
   local observed_sync = false

   sdl3x.get_window = function()
      return {
         set_fullscreen = function(_, enabled)
            observed_enabled = enabled
         end,
         sync = function()
            observed_sync = true
         end,
      }
   end

   app:set_fullscreen(true)
   test.truthy(observed_enabled)
   test.truthy(observed_sync)
   test.truthy(app.fullscreen_enabled)

   sdl3x.get_window = old_get_window
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

test.case("sdl3x.SceneApp combines animator and owned-resource lifecycles", function()
   local released = {}
   local root = nil
   local scene_animator = nil
   local TestRoot = rig.Class(Object)
   local TestApp = rig.Class(sdl3x.SceneApp)

   function TestRoot:init()
      self:super().init(self)
      self.released = false
   end

   function TestRoot:release()
      self.released = true
   end

   function TestApp:init()
      self:super().init(self, {
         module_config = {
            animator = {
               start = false,
            },
         },
      })
   end

   function TestApp:create_root()
      root = TestRoot()
      return root
   end

   function TestApp:create_scene_animator(created_root)
      scene_animator = animator.Animator(created_root, self.animator_options)
      return scene_animator
   end

   local app = TestApp()
   app:own("owned", function(_, resource)
      table.insert(released, resource)
   end)

   app:after_setup()
   test.equal(app.root, root)
   test.equal(app.animator, scene_animator)

   app:before_shutdown()
   test.truthy(root.released)
   test.equal(app.root, nil)
   test.equal(app.animator, nil)
   test.equal(#released, 1)
   test.equal(released[1], "owned")
end)
