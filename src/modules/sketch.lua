local M = ... or {}

local color = require("color")
local render = require("render")
local rig = require("rig")
local scene = require("scene")
local sdl3 = require("sdl3")
local sdl3x = require("sdl3x")

-- The code-first sketch facade. It assembles a default runtime composition --
-- bundle, clock, scene with camera, entities, and frame callbacks -- on top of
-- the same builder/compiler/component machinery that power users use directly.
-- Nothing here is a parallel runtime; it is a thin front door.

local DEFAULT_CAMERA = {
   eye = { 0.0, 0.0, -4.5 },
   target = { 0.0, 0.0, 0.0 },
   up = { 0.0, 1.0, 0.0 },
   fov_degrees = 60.0,
   near = 0.1,
   far = 100.0,
}

local DEFAULT_BACKGROUND = color.rgbaf(0.07, 0.08, 0.11, 1.0)

local App = rig.Class()
M.App = App

function App:init()
   self.entities = {}
   self.update = nil
   self.draw = nil
   self.overlay = nil
   self.key = nil
   self.mouse = nil
   self.resize = nil
   self.camera_controllers = {}
   self.overlays = {}
   self.input = nil
   self.scene = nil
   self.surface = nil
   self.ctx = nil
   self.runtime = nil
end

-- Queues an entity spec to be composed into the scene at startup. Called from
-- the sketch build callback, before compilation.
function App:add_entity(options)
   self.entities[#self.entities + 1] = options or {}
   return self
end

-- Registers `fn(app, frame)`, run once per frame before the frame is drawn.
function App:on_update(fn)
   self.update = fn
   return self
end

-- Registers `fn(app, frame)`, run once per frame after the camera is current.
function App:on_draw(fn)
   self.draw = fn
   return self
end

-- Registers `fn(app, frame)`, run once per frame after the scene is drawn, for
-- screen-space overlays and HUDs.
function App:on_overlay(fn)
   self.overlay = fn
   return self
end

-- Registers an overlay value (for example `overlay.overlay(params)`). Its
-- `:update(input, scene)` runs each frame before drawing and `:draw(scene)` runs
-- in the overlay phase.
function App:add_overlay(value)
   if value == nil or type(value.draw) ~= "function" then
      rig.raise("sketch.App:add_overlay expects an overlay with a draw method")
   end
   self.overlays[#self.overlays + 1] = value
   return value
end

-- Registers `fn(app, key_info)`, run for every key event.
function App:on_key(fn)
   self.key = fn
   return self
end

-- Registers `fn(app, mouse_info)`, run for every mouse event.
function App:on_mouse(fn)
   self.mouse = fn
   return self
end

-- Registers `fn(app, resize_info)`, run for every resize event.
function App:on_resize(fn)
   self.resize = fn
   return self
end

-- Opts the sketch into a camera controller. `options.kind` is `"orbit"` (the
-- default) or `"fly"`. Controllers are optional and never added automatically.
function App:add_camera_controls(options)
   local camera = require("camera")
   options = options or {}
   local kind = options.kind or "orbit"

   local controller
   if kind == "orbit" then
      controller = camera.orbit(options)
   elseif kind == "fly" then
      controller = camera.fly(options)
   else
      rig.raise("sketch camera controls kind must be 'orbit' or 'fly'")
   end

   self.camera_controllers[#self.camera_controllers + 1] = controller
   return controller
end

local function resolve_call_options(first, second)
   if type(first) == "function" then
      return {}, first
   end

   local options = first or {}
   local build = second or options.build
   return options, build
end

local function window_props(title, base)
   local props = {}
   if type(base) == "table" then
      for key, value in pairs(base) do
         props[key] = value
      end
   end
   if title ~= nil and props[sdl3.PROP_WINDOW_CREATE_TITLE_STRING] == nil then
      props[sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = title
   end
   return props
end

-- options:
--   title          window title
--   bundle         backend bundle (defaults to sdl3x.bundle_sdl3_gl)
--   bundle_options forwarded to the bundle
--   camera         scene camera table
--   background     background color value
--   build          function(app) called before startup
--   update         function(app, frame) per frame
--   draw           function(app, frame) per frame
--
-- `run` blocks until the sketch exits. `run(build)` is shorthand for
-- `run { build = build }`.
function M.run(first, second)
   local options, build = resolve_call_options(first, second)

   local bundle = options.bundle or sdl3x.bundle_sdl3_gl
   if type(bundle) ~= "function" then
      rig.raise("rig.run options.bundle must be a function")
   end

   local app = App()
   app.input = require("input").Input()
   if build ~= nil then
      build(app)
   end

   if options.camera_controls ~= nil then
      local spec = options.camera_controls
      if spec[1] ~= nil then
         for i = 1, #spec do
            app:add_camera_controls(spec[i])
         end
      else
         app:add_camera_controls(spec)
      end
   end

   local bundle_options = {}
   for key, value in pairs(options.bundle_options or {}) do
      bundle_options[key] = value
   end
   bundle_options.window_props = window_props(options.title, bundle_options.window_props)

   local scene_plugin = scene.plugin()
   local render_plugin = render.plugin()

   local function on_update(frame)
      app.scene = frame.scene
      app.surface = frame.surface
      frame.input = app.input

      for i = 1, #app.camera_controllers do
         local controller = app.camera_controllers[i]
         controller:update(frame.dt)
         controller:apply(frame.scene)
      end

      for i = 1, #app.overlays do
         app.overlays[i]:update(app.input, frame.scene)
      end

      require("audio").update()

      if app.update ~= nil then
         app.update(app, frame)
      end
   end

   local function on_draw(frame)
      frame.input = app.input
      if app.draw ~= nil then
         app.draw(app, frame)
      end
   end

   -- Runs after the scene's children, so overlays land on top of the camera
   -- pass. Input edges stay valid through it, then reset for the next frame.
   local function on_overlay(frame)
      frame.input = app.input
      for i = 1, #app.overlays do
         app.overlays[i]:draw(frame.surface)
      end
      if app.overlay ~= nil then
         app.overlay(app, frame)
      end
      app.input:begin_frame()
   end

   local builder = rig.runtime()
   bundle(builder, bundle_options)
   builder:use(scene_plugin)
   builder:use(render_plugin)
   builder:add(scene.container_component(scene_plugin, {
      name = "scene",
      background_color = options.background or DEFAULT_BACKGROUND,
      camera = options.camera or DEFAULT_CAMERA,
      on_update = on_update,
      on_draw = on_draw,
      on_overlay = on_overlay,
   }))

   for i = 1, #app.entities do
      builder:add(render.entity_component(render_plugin, app.entities[i]))
   end

   -- A per-run execution class that forwards input events to the sketch and its
   -- camera controllers. Defined here so it closes over the sketch instance.
   local RuntimeApp = rig.Class(sdl3x.App)

   function RuntimeApp:init(context)
      self:super().init(self, context)
   end

   function RuntimeApp:on_key(payload)
      app.input:on_key(payload)
      for i = 1, #app.camera_controllers do
         app.camera_controllers[i]:on_key(payload)
      end
      if app.key ~= nil then
         app.key(app, payload)
      end
   end

   function RuntimeApp:on_mouse(payload)
      app.input:on_mouse(payload)
      for i = 1, #app.camera_controllers do
         app.camera_controllers[i]:on_mouse(payload)
      end
      if app.mouse ~= nil then
         app.mouse(app, payload)
      end
   end

   function RuntimeApp:on_resize(payload)
      sdl3x.App.on_resize(self, payload)
      if app.resize ~= nil then
         app.resize(app, payload)
      end
   end

   local compiled = builder:execute(RuntimeApp):compile()
   app.runtime = compiled
   compiled:start()
   app.ctx = compiled.ctx
   return app
end

return M