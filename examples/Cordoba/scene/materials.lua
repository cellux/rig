local color = require("color")
local render = require("render")
local rig = require("rig")

local textures = rig.require("./textures")

local M = {}

M.palette = {
   floor_mosque = color.rgb(192, 144, 104),
   floor_nave = color.rgb(208, 174, 136),
   floor_cathedral = color.rgb(214, 198, 172),
   stone = color.rgb(220, 210, 190),
   stone_warm = color.rgb(194, 176, 146),
   stone_pale = color.rgb(234, 226, 208),
   brick = color.rgb(158, 62, 46),
   cream = color.rgb(232, 219, 190),
   wood = color.rgb(160, 128, 98),
   wood_dark = color.rgb(112, 84, 62),
   recess = color.rgb(26, 22, 20),
   glass = color.rgb(118, 146, 166),
   gold = color.rgb(230, 180, 80),
   column_shaft = color.rgb(82, 78, 72),
   burgundy = color.rgb(112, 24, 24),
   bronze = color.rgb(126, 92, 48),
   bronze_dark = color.rgb(74, 54, 30),
   sign_green = color.rgb(74, 118, 92),
   sign_red = color.rgb(126, 40, 46),
}

function M.create()
   local palette = M.palette
   local images = textures.create()

   local function texture(name)
      return render.texture {
         image = images[name],
         name = "cordoba-" .. name,
         filter = "linear",
         wrap = "repeat",
      }
   end

   local reflection_high = render.target {
      width = 640,
      height = 360,
      name = "cordoba reflection high",
      filter = "linear",
      wrap = "clamp",
      depth = true,
   }
   local reflection_balanced = render.target {
      width = 384,
      height = 216,
      name = "cordoba reflection balanced",
      filter = "linear",
      wrap = "clamp",
      depth = true,
   }

   local materials = {
      surfaces = render.material {
         name = "cordoba limestone",
         shading = "lit",
         albedo = color.rgb(255, 255, 255),
         texture = texture("limestone"),
         texture_scale = 0.55,
         roughness = 0.82,
         specular = 0.08,
      },
      plaster = render.material {
         name = "cordoba plaster",
         shading = "lit",
         albedo = color.rgb(255, 255, 255),
         texture = texture("plaster"),
         texture_scale = 0.45,
         roughness = 0.90,
         specular = 0.03,
      },
      cathedral = render.material {
         name = "cordoba cathedral marble",
         shading = "lit",
         albedo = color.rgb(255, 255, 255),
         texture = texture("marble"),
         texture_scale = 0.42,
         roughness = 0.66,
         specular = 0.14,
         environment_strength = 0.06,
      },
      column = render.material {
         name = "cordoba polished column",
         shading = "lit",
         albedo = color.rgb(255, 255, 255),
         texture = texture("marble"),
         texture_scale = 1.0,
         roughness = 0.38,
         specular = 0.38,
         environment_strength = 0.18,
      },
      arches = render.material {
         name = "cordoba striped arches",
         shading = "lit",
         albedo = color.rgb(255, 255, 255),
         texture = texture("limestone"),
         texture_scale = 0.70,
         roughness = 0.76,
         specular = 0.10,
      },
      floor = render.material {
         name = "cordoba floor high reflection",
         shading = "lit",
         albedo = color.rgb(255, 255, 255),
         texture = texture("terracotta_floor"),
         texture_scale = 0.65,
         roughness = 0.58,
         specular = 0.18,
         reflection_texture = reflection_high,
         reflection_strength = 0.32,
      },
      floor_balanced = render.material {
         name = "cordoba floor balanced reflection",
         shading = "lit",
         albedo = color.rgb(255, 255, 255),
         texture = texture("terracotta_floor"),
         texture_scale = 0.65,
         roughness = 0.64,
         specular = 0.14,
         reflection_texture = reflection_balanced,
         reflection_strength = 0.26,
      },
      floor_fallback = render.material {
         name = "cordoba floor fallback",
         shading = "lit",
         albedo = color.rgb(255, 255, 255),
         texture = texture("terracotta_floor"),
         texture_scale = 0.65,
         roughness = 0.78,
         specular = 0.08,
         environment_strength = 0.10,
      },
      wood = render.material {
         name = "cordoba timber",
         shading = "lit",
         albedo = color.rgb(255, 255, 255),
         texture = texture("wood"),
         texture_scale = 2.2,
         roughness = 0.66,
         specular = 0.10,
      },
      brick = render.material {
         name = "cordoba brick",
         shading = "lit",
         albedo = color.rgb(255, 255, 255),
         texture = texture("brick"),
         texture_scale = 1.1,
         roughness = 0.84,
         specular = 0.05,
      },
      glass = render.material {
         name = "cordoba glass",
         shading = "lit",
         albedo = palette.glass,
         emissive = color.rgb(104, 142, 172),
         roughness = 0.42,
         specular = 0.35,
         cull_mode = "none",
      },
      stained_glass = render.material {
         name = "cordoba stained glass",
         texture = texture("stained_glass"),
         texture_scale = 1.0,
         cull_mode = "none",
      },
      statue = render.material {
         name = "cordoba sculpted stone",
         shading = "lit",
         albedo = palette.stone_pale,
         roughness = 0.74,
         specular = 0.08,
      },
      cloth = render.material {
         name = "cordoba altar cloth",
         shading = "lit",
         albedo = palette.burgundy,
         roughness = 0.92,
         specular = 0.02,
      },
      gold = render.material {
         name = "cordoba gold",
         shading = "lit",
         albedo = palette.gold,
         emissive = color.rgb(46, 28, 4),
         roughness = 0.28,
         specular = 0.65,
         environment_strength = 0.20,
      },
      dark = render.material {
         name = "cordoba recess",
         shading = "lit",
         albedo = palette.recess,
         roughness = 0.96,
         specular = 0.02,
      },
      iron = render.material {
         name = "cordoba iron",
         shading = "lit",
         albedo = color.rgb(255, 255, 255),
         texture = texture("metal"),
         texture_scale = 1.0,
         roughness = 0.42,
         specular = 0.48,
         environment_strength = 0.16,
      },
      bronze = render.material {
         name = "cordoba bronze",
         shading = "lit",
         albedo = color.rgb(255, 255, 255),
         texture = texture("metal"),
         texture_scale = 1.4,
         roughness = 0.34,
         specular = 0.55,
         environment_strength = 0.20,
      },
      organ_pipe = render.material {
         name = "cordoba organ pipes",
         shading = "lit",
         albedo = color.rgb(232, 224, 210),
         roughness = 0.26,
         specular = 0.68,
         environment_strength = 0.24,
      },
      painting = render.material {
         name = "cordoba painting canvas",
         shading = "lit",
         albedo = color.rgb(255, 255, 255),
         texture = texture("painting"),
         texture_scale = 1.0,
         roughness = 0.72,
         specular = 0.05,
      },
      sign = render.material {
         name = "cordoba interpretation panel",
         shading = "lit",
         albedo = color.rgb(255, 255, 255),
         texture = texture("plaster"),
         texture_scale = 0.6,
         roughness = 0.5,
         specular = 0.12,
      },
   }

   materials.lighting_full = render.lighting {
      ambient = color.rgb(86, 82, 77),
      directional = {
         direction = { 0.28, 0.86, -0.34 },
         color = color.rgb(255, 240, 214),
         intensity = 1.08,
      },
      local_lights = {
         {
            position = { -6.0, 5.8, -42.0 },
            color = color.rgb(255, 166, 98),
            intensity = 4.6,
            range = 20.0,
         },
         {
            position = { -20.0, 9.0, -18.0 },
            color = color.rgb(255, 200, 138),
            intensity = 4.6,
            range = 16.0,
         },
         {
            position = { 0.0, 12.0, -6.0 },
            color = color.rgb(255, 212, 158),
            intensity = 5.4,
            range = 28.0,
         },
         {
            position = { 0.0, 6.5, 46.0 },
            color = color.rgb(255, 196, 130),
            intensity = 4.4,
            range = 26.0,
         },
      },
      exposure = 1.18,
   }

   materials.palette = palette
   materials.lighting_simple = render.lighting {
      ambient = color.rgb(82, 80, 76),
      directional = {
         direction = { 0.28, 0.86, -0.34 },
         color = color.rgb(255, 242, 220),
         intensity = 1.42,
      },
      exposure = 1.0,
   }

   materials.reflection_targets = {
      high = reflection_high,
      balanced = reflection_balanced,
   }
   materials.provenance = textures.provenance

   return materials
end

return M
