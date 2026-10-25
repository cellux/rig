local color = require("color")
local mathx = require("mathx")
local mesh = require("mesh")
local render = require("render")
local rig = require("rig")

-- Phase 3 lit-material gallery. Uses the built-in OpenGL lit material with a
-- directional daylight, warm local point lights, base-colour and normal maps,
-- and the Phase 2 indexed generators.
--
-- Controls: drag to orbit, Q/E to dolly.
--
--    ./build/rig examples/material_lighting.lua

local backend = rig.require("./backend").select {
   backends = { gl = true },
}

local function translation(x, y, z)
   return mathx.mat4_translation(mathx.mat4(), x, y, z)
end

local function rotation_y(angle)
   return mathx.mat4_rotation_y(mathx.mat4(), angle)
end

local function compose(a, b)
   return mathx.mat4_multiply(mathx.mat4(), a, b)
end

-- A subtle warm-stone base-colour texture with soft joints and grain.
local function stone_image(size)
   local pixels = {}
   for y = 0, size - 1 do
      for x = 0, size - 1 do
         local u = x / size
         local v = y / size
         local grain = math.sin(u * 37.0) * math.cos(v * 29.0) * 5.0
            + math.sin((u + v) * 61.0) * 2.5
         local joint = (x % 8 == 0 or y % 8 == 0) and -12.0 or 0.0
         local r = math.floor(196 + grain + joint)
         local g = math.floor(185 + grain * 0.9 + joint)
         local b = math.floor(164 + grain * 0.75 + joint)
         pixels[#pixels + 1] = string.char(
            math.max(0, math.min(255, r)),
            math.max(0, math.min(255, g)),
            math.max(0, math.min(255, b)),
            255
         )
      end
   end
   return {
      width = size,
      height = size,
      channels = 4,
      pixels = table.concat(pixels),
   }
end

-- A small procedural tangent-space normal map with a soft diagonal groove. The
-- pixel order is top-down RGBA, matching render.texture.
local function normal_map_image(size)
   local pixels = {}
   for y = 0, size - 1 do
      for x = 0, size - 1 do
         local u = (x + 0.5) / size
         local v = (y + 0.5) / size
         local wave = math.sin((u + v) * math.pi * 4.0) * 0.35
         local nx = wave
         local ny = math.cos((u - v) * math.pi * 4.0) * 0.25
         local nz = math.sqrt(math.max(0.05, 1.0 - nx * nx - ny * ny))
         local length = math.sqrt(nx * nx + ny * ny + nz * nz)
         nx, ny, nz = nx / length, ny / length, nz / length
         pixels[#pixels + 1] = string.char(
            math.floor((nx * 0.5 + 0.5) * 255 + 0.5),
            math.floor((ny * 0.5 + 0.5) * 255 + 0.5),
            math.floor((nz * 0.5 + 0.5) * 255 + 0.5),
            255
         )
      end
   end
   return {
      width = size,
      height = size,
      channels = 4,
      pixels = table.concat(pixels),
   }
end

local floor_mesh = mesh.make_floor_bay {
   width = 20.0,
   depth = 16.0,
   segments = 10,
   color = color.rgb(255, 255, 255),
   uv_scale = 0.35,
}

local wall_mesh = mesh.make_wall {
   width = 7.0,
   height = 4.5,
   thickness = 0.35,
   color = color.rgb(255, 255, 255),
   reveal_color = color.rgb(220, 205, 180),
   openings = {
      { x = 2.2, y = 1.2, width = 2.6, height = 2.1 },
   },
}

local column_mesh = mesh.make_column {
   radius = 0.32,
   height = 3.8,
   base_height = 0.35,
   base_radius = 0.48,
   capital_height = 0.45,
   capital_radius = 0.48,
   abacus_height = 0.16,
   abacus_width = 1.15,
   segments = 20,
   color = color.rgb(255, 255, 255),
   base_color = color.rgb(235, 225, 205),
   capital_color = color.rgb(235, 225, 205),
   abacus_color = color.rgb(255, 255, 255),
}

local horseshoe_mesh = mesh.make_horseshoe_arch {
   radius = 1.5,
   thickness = 0.28,
   depth = 0.45,
   segments = 22,
   stripe_colors = {
      color.rgb(165, 58, 44),
      color.rgb(236, 222, 193),
   },
}

local round_arch_mesh = mesh.make_round_arch {
   radius = 1.2,
   thickness = 0.24,
   depth = 0.4,
   segments = 18,
   color = color.rgb(255, 255, 255),
}

local vault_mesh = mesh.make_barrel_vault {
   radius = 2.0,
   thickness = 0.24,
   length = 3.4,
   segments = 20,
   color = color.rgb(255, 255, 255),
}

-- The normal-mapped panel needs tangents. Build it through the Phase 2 builder
-- so its layout is position_normal_tangent_color_uv_f32.
local panel_mesh = mesh.builder { tangents = true }
   :add(mesh.make_box {
      width = 3.0,
      height = 2.4,
      depth = 0.18,
      color = color.rgb(255, 255, 255),
   })
   :build()

local materials = {}

rig.run {
   title = "Rig " .. backend.label .. " Material and Lighting",
   bundle = backend.bundle,
   bundle_options = backend.bundle_options,
   background = color.rgb(24, 28, 34),
   lighting = render.lighting {
      ambient = color.rgb(54, 58, 68),
      directional = {
         direction = { 0.45, 0.82, -0.4 },
         color = color.rgb(255, 240, 214),
         intensity = 1.55,
      },
      local_lights = {
         {
            position = { -3.6, 2.8, -2.4 },
            color = color.rgb(255, 158, 92),
            intensity = 3.6,
            range = 9.0,
         },
         {
            position = { 4.2, 2.2, 1.2 },
            color = color.rgb(255, 206, 142),
            intensity = 2.4,
            range = 8.0,
         },
      },
      exposure = 1.12,
   },
   camera_controls = {
      kind = "orbit",
      target = { 0.0, 1.5, 0.0 },
      distance = 13.0,
      pitch = 0.28,
      yaw = math.pi,
   },
   start = function()
      local stone_texture = render.texture {
         image = stone_image(32),
         name = "lit-stone-detail",
      }
      local normal_map = render.texture {
         image = normal_map_image(16),
         name = "lit-normal-map",
      }

      materials.floor = render.material {
         name = "floor stone",
         shading = "lit",
         albedo = color.rgb(176, 163, 142),
         roughness = 0.82,
         specular = 0.06,
         texture = stone_texture,
      }
      materials.stone = render.material {
         name = "warm stone",
         shading = "lit",
         albedo = color.rgb(224, 211, 187),
         roughness = 0.78,
         specular = 0.08,
      }
      materials.brick = render.material {
         name = "brick",
         shading = "lit",
         albedo = color.rgb(170, 72, 54),
         roughness = 0.86,
         specular = 0.05,
      }
      materials.cream = render.material {
         name = "cream plaster",
         shading = "lit",
         albedo = color.rgb(238, 226, 201),
         roughness = 0.9,
         specular = 0.04,
      }
      materials.wood = render.material {
         name = "dark wood",
         shading = "lit",
         albedo = color.rgb(94, 64, 43),
         roughness = 0.55,
         specular = 0.18,
      }
      materials.panel = render.material {
         name = "normal-mapped panel",
         shading = "lit",
         albedo = color.rgb(230, 220, 202),
         roughness = 0.62,
         specular = 0.2,
         texture = stone_texture,
         normal_texture = normal_map,
      }
   end,
   build = function(app)
      app:on_draw(function(_, frame)
         local surface = frame.surface
         surface:draw_mesh(floor_mesh, translation(0.0, 0.0, 0.0), materials.floor)

         surface:draw_mesh(wall_mesh, translation(-3.2, 0.0, 3.0), materials.cream)
         surface:draw_mesh(vault_mesh, translation(2.0, 2.0, 3.2), materials.wood)

         for i = -1, 1 do
            surface:draw_mesh(
               column_mesh,
               translation(i * 3.2 - 0.2, 0.0, -2.6),
               materials.stone
            )
         end

         surface:draw_mesh(
            horseshoe_mesh,
            translation(-3.2, 1.7, -2.6),
            materials.brick
         )
         surface:draw_mesh(
            round_arch_mesh,
            translation(3.1, 1.55, -2.6),
            materials.cream
         )

         local spin = rotation_y(frame.time * 0.35)
         surface:draw_mesh(
            panel_mesh,
            compose(translation(0.0, 1.55, 0.2), spin),
            materials.panel
         )
      end)
   end,
}
