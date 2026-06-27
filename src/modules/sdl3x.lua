local M = ... or {}
local animator = require("animator")
local font = require("font")
local ffi = require("ffi")
local profiler = require("profiler")
local rig = require("rig")
local schema = require("schema")
local sdl3 = require("sdl3")

local module_config_schema = schema.record({
   frame_profiler = schema.one_of({
      schema.boolean(),
      schema.table(),
   }, "a boolean or table"):optional(),
   fullscreen = schema.boolean():optional(),
   vsync = schema.boolean():optional(),
})

local function normalize_module_config(options)
   if options == nil then
      return {}
   end
   return schema.assert(module_config_schema, options, "sdl3x module configuration")
end

local function get_module_config(runtime_options)
   local module_config = runtime_options.module_config
   if module_config == nil then
      return {}
   end
   if type(module_config) ~= "table" then
      rig.raise("rig.run expects options.module_config to be a table if provided")
   end

   local sdl3x_config = module_config.sdl3x
   if sdl3x_config == nil then
      return {}
   end

   return normalize_module_config(sdl3x_config)
end

local function create_frame_profiler(spec)
   if spec == nil or spec == false then
      return nil
   end
   if spec == true then
      return profiler.FrameProfiler()
   end
   return profiler.FrameProfiler(spec)
end

local function get_error_string()
   local err = sdl3.GetError()
   if err == nil or err == ffi.NULL then
      return "unknown SDL error"
   end
   return ffi.string(err)
end

local function init_common_state(self, runtime_options, scope_label)
   local config = get_module_config(runtime_options or {})

   self.window_width = 0
   self.window_height = 0
   self.pixel_width = 0
   self.pixel_height = 0
   self.fullscreen_enabled = config.fullscreen == true
   self.vsync_enabled = config.vsync ~= false
   self.frame_profiler = create_frame_profiler(config.frame_profiler)
   self.frame_profiler_enabled = self.frame_profiler ~= nil
   self.font_faces = {}
   self.owned_resources = rig.ResourceScope(self, scope_label)
   self._sdl3x_module_config = config
end

local function release_common_state(self)
   if self.owned_resources ~= nil then
      self.owned_resources:release()
      self.owned_resources = nil
   end

   self.font_faces = {}
   self.frame_profiler = nil
   self.frame_profiler_enabled = false
end

local function apply_runtime_toggles(self)
   local config = self._sdl3x_module_config or {}

   if config.vsync ~= nil then
      self:set_vsync(config.vsync)
   end
   if config.fullscreen ~= nil then
      self:set_fullscreen(config.fullscreen)
   end
end

local function before_frame_common(self)
   if self.frame_profiler ~= nil and self.frame_profiler_enabled then
      self.frame_profiler:begin_frame()
   end
end

local function after_frame_common(self)
   if self.frame_profiler ~= nil and self.frame_profiler_enabled then
      self.frame_profiler:end_frame()
   end
end

local function invoke_render_common(self, ...)
   if type(self.render) ~= "function" then
      return
   end

   if self.frame_profiler ~= nil and self.frame_profiler_enabled then
      self.frame_profiler:begin_cpu()
      local ok, result_or_err = pcall(self.render, self, ...)
      self.frame_profiler:end_cpu()
      if not ok then
         rig.raise(result_or_err)
      end
      return result_or_err
   end

   return self:render(...)
end

local function set_vsync_common(self, enabled)
   if type(enabled) ~= "boolean" then
      rig.raise("sdl3x.App:set_vsync expects enabled to be a boolean")
   end

   local renderer = sdl3.get_renderer()
   if renderer ~= nil then
      local interval = enabled and 1 or 0
      if not sdl3.SetRenderVSync(renderer, interval) then
         rig.raise("failed to set renderer vsync: " .. get_error_string())
      end
      self.vsync_enabled = enabled
      return enabled
   end

   if sdl3.get_gl_context() ~= nil then
      local interval = enabled and 1 or 0
      if not sdl3.GL_SetSwapInterval(interval) then
         rig.raise("failed to set OpenGL swap interval: " .. get_error_string())
      end
      self.vsync_enabled = enabled
      return enabled
   end

   rig.raise("sdl3x.App:set_vsync is not supported by the active SDL runtime")
end

local function toggle_vsync_common(self)
   return self:set_vsync(not self.vsync_enabled)
end

local function set_fullscreen_common(self, enabled)
   if type(enabled) ~= "boolean" then
      rig.raise("sdl3x.App:set_fullscreen expects enabled to be a boolean")
   end

   local window = sdl3.get_window()
   if window == nil then
      rig.raise("sdl3 runtime did not provide a window")
   end
   if not sdl3.SetWindowFullscreen(window, enabled) then
      rig.raise("failed to set window fullscreen: " .. get_error_string())
   end
   if not sdl3.SyncWindow(window) then
      rig.raise("failed to synchronize fullscreen state: " .. get_error_string())
   end

   self.fullscreen_enabled = enabled
   return enabled
end

local function toggle_fullscreen_common(self)
   return self:set_fullscreen(not self.fullscreen_enabled)
end

local function set_frame_profiler_enabled_common(self, enabled)
   if type(enabled) ~= "boolean" then
      rig.raise("sdl3x.App:set_frame_profiler_enabled expects enabled to be a boolean")
   end
   if self.frame_profiler == nil and enabled then
      self.frame_profiler = profiler.FrameProfiler()
   end
   self.frame_profiler_enabled = enabled and self.frame_profiler ~= nil
   return self.frame_profiler_enabled
end

local function toggle_frame_profiler_common(self)
   return self:set_frame_profiler_enabled(not self.frame_profiler_enabled)
end

local function own_common(self, resource, release_fn)
   if self.owned_resources == nil then
      rig.raise("sdl3x.App has already released its owned resources")
   end
   return self.owned_resources:adopt(resource, release_fn)
end

local function replace_owned_common(self, key, resource, release_fn)
   if self.owned_resources == nil then
      rig.raise("sdl3x.App has already released its owned resources")
   end
   return self.owned_resources:replace(key, resource, release_fn)
end

local function create_owned_scope_common(self, label)
   local scope = rig.ResourceScope(self, label or "sdl3x owned scope")
   return self:own(scope, function(_, owned_scope)
      owned_scope:release()
   end)
end

local function release_owned_resources_common(self)
   if self.owned_resources == nil then
      return
   end
   self.owned_resources:release()
   self.owned_resources = nil
   self.font_faces = {}
end

local function load_font_face_common(self, name, path, face_index)
   if type(name) ~= "string" or name == "" then
      rig.raise("sdl3x.App:load_font_face expects name to be a non-empty string")
   end

   local face = font.load_face(path, face_index)
   self.font_faces[name] = self:replace_owned(
      "font_face:" .. name,
      face,
      function(_, resource)
         resource:release()
      end
   )
   return self.font_faces[name]
end

local function get_font_face_common(self, name)
   if type(name) ~= "string" or name == "" then
      rig.raise("sdl3x.App:get_font_face expects name to be a non-empty string")
   end
   return self.font_faces[name]
end

local function on_resize_common(self, resize_info)
   self.window_width = resize_info.width or 0
   self.window_height = resize_info.height or 0
   self.pixel_width = resize_info.pixel_width or 0
   self.pixel_height = resize_info.pixel_height or 0
end

local App = rig.Class(rig.App)
local SceneApp = rig.Class(animator.App)

M.App = App
M.SceneApp = SceneApp

function App:init(options)
   init_common_state(self, options or {}, "sdl3x app resources")
end

function App:after_setup()
   apply_runtime_toggles(self)
end

function App:before_shutdown()
   release_common_state(self)
end

function SceneApp:init(options)
   animator.App.init(self, options)
   init_common_state(self, options or {}, "sdl3x scene app resources")
end

function SceneApp:after_setup()
   animator.App.after_setup(self)
   apply_runtime_toggles(self)
end

function SceneApp:before_shutdown()
   local ok, err = pcall(function()
      animator.App.before_shutdown(self)
   end)
   release_common_state(self)
   if not ok then
      rig.raise(err)
   end
end

App.before_frame = before_frame_common
App.after_frame = after_frame_common
App.invoke_render = invoke_render_common
App.set_vsync = set_vsync_common
App.toggle_vsync = toggle_vsync_common
App.set_fullscreen = set_fullscreen_common
App.toggle_fullscreen = toggle_fullscreen_common
App.set_frame_profiler_enabled = set_frame_profiler_enabled_common
App.toggle_frame_profiler = toggle_frame_profiler_common
App.own = own_common
App.replace_owned = replace_owned_common
App.create_owned_scope = create_owned_scope_common
App.release_owned_resources = release_owned_resources_common
App.load_font_face = load_font_face_common
App.get_font_face = get_font_face_common
App.on_resize = on_resize_common

SceneApp.before_frame = before_frame_common
SceneApp.after_frame = after_frame_common
SceneApp.invoke_render = invoke_render_common
SceneApp.set_vsync = set_vsync_common
SceneApp.toggle_vsync = toggle_vsync_common
SceneApp.set_fullscreen = set_fullscreen_common
SceneApp.toggle_fullscreen = toggle_fullscreen_common
SceneApp.set_frame_profiler_enabled = set_frame_profiler_enabled_common
SceneApp.toggle_frame_profiler = toggle_frame_profiler_common
SceneApp.own = own_common
SceneApp.replace_owned = replace_owned_common
SceneApp.create_owned_scope = create_owned_scope_common
SceneApp.release_owned_resources = release_owned_resources_common
SceneApp.load_font_face = load_font_face_common
SceneApp.get_font_face = get_font_face_common
SceneApp.on_resize = on_resize_common

return M
