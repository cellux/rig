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

function M.get_error(fallback)
   local err = sdl3.GetError()
   if err == nil or err == ffi.NULL or err[0] == 0 then
      return fallback or "unknown SDL error"
   end
   return ffi.string(err)
end

local Properties = rig.Class()

local function ensure_properties(properties)
   if getmetatable(properties) ~= Properties then
      rig.raise("sdl3x.Properties operation expects an sdl3x.Properties instance")
   end
   if properties._released then
      rig.raise("sdl3x.Properties has been released")
   end
end

local function copy_property_values(values)
   local copy = {}
   for key, value in pairs(values) do
      copy[key] = value
   end
   return copy
end

local function set_property_value(properties, name, value)
   if type(name) ~= "string" or name == "" then
      rig.raise("sdl3x.Properties expects property names to be non-empty strings")
   end

   if value == nil then
      if not sdl3.ClearProperty(properties.id, name) then
         rig.raise(("failed to clear property '%s': %s"):format(
            name,
            M.get_error()
         ))
      end
      properties._values[name] = nil
      return properties
   end

   local ok = nil
   local value_type = type(value)
   if value_type == "boolean" then
      ok = sdl3.SetBooleanProperty(properties.id, name, value)
   elseif value_type == "number" then
      if value == math.floor(value) then
         ok = sdl3.SetNumberProperty(properties.id, name, value)
      else
         ok = sdl3.SetFloatProperty(properties.id, name, value)
      end
   elseif value_type == "string" then
      ok = sdl3.SetStringProperty(properties.id, name, value)
   elseif value_type == "cdata" then
      ok = sdl3.SetPointerProperty(properties.id, name, ffi.cast("void *", value))
   else
      rig.raise(
         ("unsupported SDL property value type for '%s': %s"):format(
            name,
            value_type
         )
      )
   end

   if not ok then
      rig.raise(("failed to set property '%s': %s"):format(
         name,
         M.get_error()
      ))
   end

   properties._values[name] = value
   return properties
end

M.Properties = Properties

function Properties:init(values)
   if values ~= nil and type(values) ~= "table" then
      rig.raise("sdl3x.Properties expects a table if initialized with values")
   end

   self.id = sdl3.CreateProperties()
   if self.id == 0 then
      rig.raise("failed to create SDL properties: " .. M.get_error())
   end

   self._released = false
   self._values = {}

   local initial_values = values
   if getmetatable(values) == Properties then
      initial_values = values._values
   end

   local ok, err = pcall(function()
      if initial_values ~= nil then
         self:merge(initial_values)
      end
   end)
   if not ok then
      self:release()
      rig.raise(err)
   end
end

function Properties:set(name, value)
   ensure_properties(self)
   return set_property_value(self, name, value)
end

function Properties:clear(name)
   return self:set(name, nil)
end

function Properties:merge(values)
   ensure_properties(self)

   local source = values
   if getmetatable(values) == Properties then
      source = values._values
   elseif type(values) ~= "table" then
      rig.raise("sdl3x.Properties:merge expects a table or sdl3x.Properties")
   end

   for key, value in pairs(source) do
      set_property_value(self, key, value)
   end
   return self
end

function Properties:get(name, default)
   ensure_properties(self)
   local value = self._values[name]
   if value == nil then
      return default
   end
   return value
end

function Properties:has(name)
   ensure_properties(self)
   return self._values[name] ~= nil
end

function Properties:to_table()
   ensure_properties(self)
   return copy_property_values(self._values)
end

function Properties:clone()
   ensure_properties(self)
   return Properties(self._values)
end

function Properties:release()
   if self._released then
      return
   end

   if self.id ~= nil and self.id ~= 0 then
      sdl3.DestroyProperties(self.id)
   end

   self.id = 0
   self._values = {}
   self._released = true
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
         rig.raise("failed to set renderer vsync: " .. M.get_error())
      end
      self.vsync_enabled = enabled
      return enabled
   end

   if sdl3.get_gl_context() ~= nil then
      local interval = enabled and 1 or 0
      if not sdl3.GL_SetSwapInterval(interval) then
         rig.raise("failed to set OpenGL swap interval: " .. M.get_error())
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
      rig.raise("failed to set window fullscreen: " .. M.get_error())
   end
   if not sdl3.SyncWindow(window) then
      rig.raise("failed to synchronize fullscreen state: " .. M.get_error())
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
