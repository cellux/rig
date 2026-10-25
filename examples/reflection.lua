-- Planar reflection demo.
--
-- The pass renders the scene from a camera mirrored across Y = 0 into a
-- `render.target`, then the floor's built-in lit material samples that target in
-- screen space. The floor itself is skipped during the reflection pass to avoid
-- recursion. OpenGL is the reference backend.

local color = require("color")
local mathx = require("mathx")
local rig = require("rig")

local mesh = require("mesh")
local render = require("render")

local backend = rig.require("./backend").select {
   backends = { gl = true },
}

local reflection_target = render.target {
   width = 640,
   height = 360,
   name = "planar reflection",
   filter = "linear",
   wrap = "clamp",
   depth = true,
}

local floor_material = render.material {
   name = "reflective floor",
   shading = "lit",
   albedo = color.rgb(176, 160, 140),
   roughness = 0.50,
   specular = 0.22,
   reflection_texture = reflection_target,
   reflection_strength = 0.34,
}

local floor = mesh.make_floor_bay {
   width = 24.0,
   depth = 24.0,
   segments = 2,
   color = color.rgb(255, 255, 255),
   uv_scale = 0.5,
}

local objects = {
   {
      mesh = mesh.make_box { width = 1.2, height = 2.4, depth = 1.2, color = color.rgb(210, 94, 64) },
      transform = { x = -2.2, y = 1.2, z = 0.0 },
      material = render.material { shading = "lit", albedo = color.rgb(210, 94, 64), roughness = 0.6 },
   },
   {
      mesh = mesh.make_box { width = 1.6, height = 1.2, depth = 1.6, color = color.rgb(92, 142, 184) },
      transform = { x = 0.0, y = 0.6, z = 0.6 },
      material = render.material { shading = "lit", albedo = color.rgb(92, 142, 184), roughness = 0.45 },
   },
   {
      mesh = mesh.make_cylinder { radius = 0.5, height = 3.2, color = color.rgb(210, 180, 96) },
      transform = { x = 2.4, y = 1.6, z = -0.2 },
      material = render.material { shading = "lit", albedo = color.rgb(210, 180, 96), roughness = 0.30, environment_strength = 0.16 },
   },
}

local function mirror_camera(camera)
   local eye = camera.eye
   local target = camera.target
   return {
      eye = { eye[1], -eye[2], eye[3] },
      target = { target[1], -target[2], target[3] },
      up = { 0.0, -1.0, 0.0 },
      fov_degrees = camera.fov_degrees,
      near = camera.near,
      far = camera.far,
   }
end

local function draw_objects(surface)
   for i = 1, #objects do
      local object = objects[i]
      local transform = object.transform
      surface:push_transform(mathx.mat4_translation(
         mathx.mat4(),
         transform.x,
         transform.y,
         transform.z
      ))
      surface:draw_mesh(object.mesh, nil, object.material)
      surface:pop_transform()
   end
   surface:draw_mesh(floor, nil, floor_material)
end

local function draw_reflection_objects(surface)
   for i = 1, #objects do
      local object = objects[i]
      local transform = object.transform
      surface:push_transform(mathx.mat4_translation(
         mathx.mat4(),
         transform.x,
         transform.y,
         transform.z
      ))
      surface:draw_mesh(object.mesh, nil, object.material)
      surface:pop_transform()
   end
end

rig.run {
   title = "Rig planar reflection",
   bundle = backend.bundle,
   bundle_options = backend.bundle_options,
   background = color.rgb(18, 20, 26),
   lighting = render.lighting {
      ambient = color.rgb(76, 74, 70),
      directional = {
         direction = { 0.35, 0.85, -0.4 },
         color = color.rgb(255, 244, 220),
         intensity = 1.2,
      },
      local_lights = {
         {
            position = { -4.0, 3.0, 4.0 },
            color = color.rgb(255, 178, 108),
            intensity = 3.0,
            range = 12.0,
         },
      },
      exposure = 1.05,
   },
   camera = {
      eye = { 0.0, 2.3, 7.5 },
      target = { 0.0, 1.0, 0.0 },
      fov_degrees = 58.0,
      near = 0.08,
      far = 80.0,
   },
   build = function(app)
      app:on_draw(function(_, frame)
         frame.surface:render_to(
            reflection_target,
            function(pass_frame)
               draw_reflection_objects(pass_frame.surface)
            end,
            { camera = mirror_camera(frame.surface.camera) }
         )
         draw_objects(frame.surface)
      end)
   end,
}
