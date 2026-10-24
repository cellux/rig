local M = ... or {}
local font = require("font")
local profiler = require("profiler")
local rig = require("rig")
local schema = require("schema")

-- Generic application execution base. It owns lifecycle conveniences that are
-- independent of any particular window or graphics backend: the frame profiler,
-- app-owned resources, font faces, render invocation, presentation toggles, and
-- resize bookkeeping. Backends (for example `sdl3x`) provide the actual window
-- and graphics context; this module drives them through their duck-typed
-- interfaces.

local app_config_schema = schema.record({
   frame_profiler = schema.one_of({
      schema.boolean(),
      schema.table(),
   }, "a boolean or table"):optional(),
   fullscreen = schema.boolean():optional(),
   vsync = schema.boolean():optional(),
}, {
   allow_extra = true,
})

local function get_app_config(context, config_namespace)
   local options = {}
   if type(context) == "table" and type(context.options) == "table" then
      options = context.options
   end

   local config = options[config_namespace]
   if config == nil then
      config = options
   end

   return schema.assert(
      app_config_schema,
      config,
      config_namespace .. " configuration"
   )
end

local function app_name(self)
   return self.app_name or "app"
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

local function init_common_state(self, context, scope_label)
   local config = get_app_config(
      context or {},
      self.config_namespace or "app"
   )

   self.context = context
   self.window = context and context.window or nil
   self.graphics = context and context.graphics or nil
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
   self._owned_resources_adopted = false
   if context ~= nil and context.resources ~= nil then
      self._owned_resources_adopted = true
      context.resources:adopt(self, self.owned_resources, function(owned_scope)
         local errors = owned_scope:release()
         if errors ~= nil and #errors > 0 then
            error(table.concat(errors, "\n"), 0)
         end
      end)
   end
   self._app_config = config
end

local function release_common_state(self)
   if self.owned_resources ~= nil then
      if not self._owned_resources_adopted then
         local errors = self.owned_resources:release()
         if errors ~= nil and #errors > 0 then
            error(table.concat(errors, "\n"), 0)
         end
      end
      self.owned_resources = nil
   end

   self.font_faces = {}
   self.frame_profiler = nil
   self.frame_profiler_enabled = false
end

local function apply_runtime_toggles(self)
   local config = self._app_config or {}

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
      rig.raise("%s.App:set_vsync expects enabled to be a boolean", app_name(self))
   end

   local graphics = self.graphics
   if graphics == nil then
      rig.raise("%s.App:set_vsync requires a graphics context", app_name(self))
   end

   if type(graphics.set_vsync) == "function" then
      graphics.set_vsync(enabled)
   elseif type(graphics.set_swap_interval) == "function" then
      graphics.set_swap_interval(enabled and 1 or 0)
   else
      rig.raise(
         "%s.App:set_vsync is not supported by the active graphics context",
         app_name(self)
      )
   end

   self.vsync_enabled = enabled
   return enabled
end

local function toggle_vsync_common(self)
   return self:set_vsync(not self.vsync_enabled)
end

local function set_fullscreen_common(self, enabled)
   if type(enabled) ~= "boolean" then
      rig.raise(
         "%s.App:set_fullscreen expects enabled to be a boolean",
         app_name(self)
      )
   end

   local window = self.window
   if window == nil then
      rig.raise("the active runtime did not provide a window")
   end
   window:set_fullscreen(enabled)
   window:sync()

   self.fullscreen_enabled = enabled
   return enabled
end

local function toggle_fullscreen_common(self)
   return self:set_fullscreen(not self.fullscreen_enabled)
end

local function set_frame_profiler_enabled_common(self, enabled)
   if type(enabled) ~= "boolean" then
      rig.raise(
         "%s.App:set_frame_profiler_enabled expects enabled to be a boolean",
         app_name(self)
      )
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
      rig.raise("%s.App has already released its owned resources", app_name(self))
   end
   return self.owned_resources:adopt(resource, release_fn)
end

local function replace_owned_common(self, key, resource, release_fn)
   if self.owned_resources == nil then
      rig.raise("%s.App has already released its owned resources", app_name(self))
   end
   return self.owned_resources:replace(key, resource, release_fn)
end

local function create_owned_scope_common(self, label)
   local scope = rig.ResourceScope(self, label or "owned scope")
   return self:own(scope, function(_, owned_scope)
      local errors = owned_scope:release()
      if errors ~= nil and #errors > 0 then
         error(table.concat(errors, "\n"), 0)
      end
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
      rig.raise(
         "%s.App:load_font_face expects name to be a non-empty string",
         app_name(self)
      )
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
      rig.raise(
         "%s.App:get_font_face expects name to be a non-empty string",
         app_name(self)
      )
   end
   return self.font_faces[name]
end

local function on_resize_common(self, resize_info)
   self.window_width = resize_info.width or 0
   self.window_height = resize_info.height or 0
   self.pixel_width = resize_info.pixel_width or 0
   self.pixel_height = resize_info.pixel_height or 0
end

--[ App class ]--

local App = rig.Class()
M.App = App

App.app_name = "app"
App.config_namespace = "app"
App.scope_label = "app resources"

function App:init(context)
   init_common_state(self, context or {}, self.scope_label)
end

function App:after_setup()
   apply_runtime_toggles(self)
end

function App:before_shutdown()
   release_common_state(self)
end

--[ App method wiring ]--

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

return M
