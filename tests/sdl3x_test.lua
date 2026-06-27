local animator = require("animator")
local scenegraph = require("scenegraph")
local sdl3 = require("sdl3")
local sdl3x = require("sdl3x")
local test = require("test")

local Object = scenegraph.Object

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
