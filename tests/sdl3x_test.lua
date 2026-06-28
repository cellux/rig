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

test.case("sdl3 GPU builders accept sdl3x.Properties", function()
   local props = {
      id = 55,
   }
   local buffer_info = sdl3.build_gpu_buffer_create_info({
      usage = 5,
      size = 64,
      props = props,
   })

   test.equal(tonumber(buffer_info[0].props), 55)
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
   local old_get_renderer = sdl3.get_renderer
   local old_get_gl_context = sdl3.get_gl_context
   local old_set_render_vsync = sdl3.SetRenderVSync
   local observed_interval = nil

   sdl3.get_renderer = function()
      return {}
   end
   sdl3.get_gl_context = function()
      return nil
   end
   sdl3.SetRenderVSync = function(_, interval)
      observed_interval = interval
      return true
   end

   app:set_vsync(false)
   test.equal(observed_interval, 0)
   test.falsey(app.vsync_enabled)

   sdl3.get_renderer = old_get_renderer
   sdl3.get_gl_context = old_get_gl_context
   sdl3.SetRenderVSync = old_set_render_vsync
end)

test.case("sdl3x.App toggles fullscreen through SDL", function()
   local app = sdl3x.App()
   local old_get_window = sdl3.get_window
   local old_set_window_fullscreen = sdl3.SetWindowFullscreen
   local old_sync_window = sdl3.SyncWindow
   local observed_enabled = nil

   sdl3.get_window = function()
      return {}
   end
   sdl3.SetWindowFullscreen = function(_, enabled)
      observed_enabled = enabled
      return true
   end
   sdl3.SyncWindow = function()
      return true
   end

   app:set_fullscreen(true)
   test.truthy(observed_enabled)
   test.truthy(app.fullscreen_enabled)

   sdl3.get_window = old_get_window
   sdl3.SetWindowFullscreen = old_set_window_fullscreen
   sdl3.SyncWindow = old_sync_window
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
