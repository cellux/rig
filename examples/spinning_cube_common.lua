local color = require("color")
local mesh = require("mesh")
local render = require("render")
local scene = require("scene")
local sdl3 = require("sdl3")
local sdl3x = require("sdl3x")

local M = {}

M.cube_face_colors = {
   color.rgb(255, 96, 96),
   color.rgb(96, 224, 128),
   color.rgb(96, 144, 255),
   color.rgb(255, 220, 96),
   color.rgb(240, 112, 255),
   color.rgb(112, 232, 255),
}

local function window_props(title)
   return {
      [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = title,
      [sdl3.PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN] = true,
   }
end

-- options:
--   title          window title
--   bundle         sdl3x.bundle_sdl3_gl or sdl3x.bundle_sdl3_gpu (the backend hint)
--   bundle_options extra options forwarded to the bundle
function M.run(options)
   options = options or {}
   local bundle = options.bundle
   if type(bundle) ~= "function" then
      rig.raise("spinning_cube_common.run expects options.bundle to be a function")
   end

   local bundle_options = {}
   for key, value in pairs(options.bundle_options or {}) do
      bundle_options[key] = value
   end
   bundle_options.window_props = window_props(options.title or "Rig Spinning Cube")

   local scene_plugin = scene.plugin()
   local render_plugin = render.plugin()

   local builder = rig.runtime()
   bundle(builder, bundle_options)
   builder:use(scene_plugin)
   builder:use(render_plugin)
   builder:add(scene.container_component(scene_plugin, {
      name = "scene",
      background_color = color.rgbaf(0.07, 0.08, 0.11, 1.0),
      camera = {
         eye = { 0.0, 0.0, -4.5 },
         target = { 0.0, 0.0, 0.0 },
         up = { 0.0, 1.0, 0.0 },
         fov_degrees = 60.0,
         near = 0.1,
         far = 100.0,
      },
   }))
   builder:add(render.entity_component(render_plugin, {
      name = "cube",
      mesh = mesh.make_cube {
         size = 2.0,
         colors = M.cube_face_colors,
      },
      spin = { x = 0.7, y = 1.0 },
   }))
   builder:execute(sdl3x.App):compile():start()
end

return M