-- Phase 8 permanent contents for the Córdoba route.
--
-- Everything here is present-day permanent or semi-permanent furniture: chapel
-- rejas and rails, hanging lamps, pews, an organ, framed paintings, candelabra,
-- statues, and interpretation panels. Repeated props share one generated source
-- mesh and are merged into per-material builders, so the scene stays bounded.
-- Collision is authored only for physically obstructive contents.

local collision = require("collision")
local color = require("color")
local mathx = require("mathx")
local mesh = require("mesh")

local M = {}

local function translation(x, y, z)
   return mathx.mat4_translation(mathx.mat4(), x, y, z)
end

local function rotation_y(angle)
   return mathx.mat4_rotation_y(mathx.mat4(), angle)
end

-- Mirrors the architecture module's composition convention: `combined(a, b)`
-- yields the transform that applies `b` then `a`.
local function combined(a, b)
   return mathx.mat4_multiply(mathx.mat4(), b, a)
end

-- ---------------------------------------------------------------------------
-- Cached source meshes
-- ---------------------------------------------------------------------------

local function build_lamp(chain_length, palette)
   local bronze = palette.bronze
   local dark = palette.bronze_dark
   local builder = mesh.builder()
   builder:add(mesh.make_cylinder {
      radius = 0.012,
      height = chain_length,
      segments = 5,
      caps = false,
      center = { 0.0, -chain_length * 0.5, 0.0 },
      color = dark,
   })
   builder:add(mesh.make_cylinder {
      radius = 0.14,
      top_radius = 0.03,
      height = 0.16,
      segments = 10,
      center = { 0.0, -chain_length - 0.08, 0.0 },
      color = bronze,
   })
   builder:add(mesh.make_cylinder {
      radius = 0.05,
      top_radius = 0.12,
      height = 0.14,
      segments = 10,
      center = { 0.0, -chain_length - 0.22, 0.0 },
      color = dark,
   })
   builder:add(mesh.make_cylinder {
      radius = 0.24,
      top_radius = 0.30,
      height = 0.16,
      segments = 12,
      center = { 0.0, -chain_length - 0.37, 0.0 },
      color = bronze,
   })
   builder:add(mesh.make_cylinder {
      radius = 0.30,
      top_radius = 0.20,
      height = 0.34,
      segments = 12,
      center = { 0.0, -chain_length - 0.62, 0.0 },
      color = bronze,
   })
   builder:add(mesh.make_cylinder {
      radius = 0.20,
      top_radius = 0.26,
      height = 0.10,
      segments = 12,
      center = { 0.0, -chain_length - 0.84, 0.0 },
      color = dark,
   })
   builder:add(mesh.make_cylinder {
      radius = 0.03,
      top_radius = 0.13,
      height = 0.20,
      segments = 10,
      center = { 0.0, -chain_length - 0.99, 0.0 },
      color = bronze,
   })
   return builder:build()
end

local function build_candelabrum(palette)
   local dark = palette.bronze_dark
   local bronze = palette.bronze
   local builder = mesh.builder()
   local function add(source)
      builder:add(source)
   end
   add(mesh.make_cylinder {
      radius = 0.42,
      top_radius = 0.30,
      height = 0.16,
      segments = 12,
      center = { 0.0, 0.08, 0.0 },
      color = dark,
   })
   add(mesh.make_cylinder {
      radius = 0.10,
      top_radius = 0.05,
      height = 0.30,
      segments = 10,
      center = { 0.0, 0.30, 0.0 },
      color = dark,
   })
   add(mesh.make_cylinder {
      radius = 0.06,
      height = 2.10,
      segments = 8,
      center = { 0.0, 1.50, 0.0 },
      color = dark,
   })
   add(mesh.make_cylinder {
      radius = 0.16,
      height = 0.20,
      segments = 10,
      center = { 0.0, 1.00, 0.0 },
      color = bronze,
   })
   add(mesh.make_cylinder {
      radius = 0.13,
      height = 0.18,
      segments = 10,
      center = { 0.0, 2.10, 0.0 },
      color = bronze,
   })
   -- Three candle arms radiating from a knop below the top.
   for i = 0, 2 do
      local angle = i * (math.pi * 2.0 / 3.0)
      local arm_length = 0.42
      local cx = math.cos(angle) * arm_length
      local cz = math.sin(angle) * arm_length
      builder:add(mesh.make_box {
         width = arm_length,
         height = 0.05,
         depth = 0.05,
         color = bronze,
      }, {
         transform = combined(
            translation(cx * 0.5, 2.62, cz * 0.5),
            rotation_y(-angle)
         ),
      })
      add(mesh.make_cylinder {
         radius = 0.07,
         height = 0.12,
         segments = 8,
         center = { cx, 2.72, cz },
         color = bronze,
      })
      add(mesh.make_cylinder {
         radius = 0.035,
         height = 0.28,
         segments = 6,
         center = { cx, 2.92, cz },
         color = color.rgb(238, 230, 210),
      })
   end
   add(mesh.make_cylinder {
      radius = 0.03,
      top_radius = 0.10,
      height = 0.24,
      segments = 8,
      center = { 0.0, 3.00, 0.0 },
      color = bronze,
   })
   return builder:build()
end

local function build_statue(palette)
   local stone = palette.stone_pale
   local builder = mesh.builder()
   builder:add(mesh.make_cylinder {
      radius = 0.16,
      height = 0.70,
      segments = 10,
      center = { 0.0, 0.35, 0.0 },
      color = stone,
   })
   builder:add(mesh.make_cylinder {
      radius = 0.30,
      top_radius = 0.24,
      height = 0.50,
      segments = 10,
      center = { 0.0, 0.95, 0.0 },
      color = stone,
   })
   builder:add(mesh.make_cylinder {
      radius = 0.20,
      height = 0.55,
      segments = 10,
      center = { 0.0, 1.45, 0.0 },
      color = stone,
   })
   builder:add(mesh.make_box {
      width = 0.36,
      height = 0.28,
      depth = 0.20,
      center = { 0.0, 1.80, 0.0 },
      color = stone,
   })
   builder:add(mesh.make_cylinder {
      radius = 0.13,
      height = 0.22,
      segments = 10,
      center = { 0.0, 1.99, 0.0 },
      color = stone,
   })
   return builder:build()
end

local function build_sign_stand(palette)
   local builder = mesh.builder()
   builder:add(mesh.make_box {
      width = 0.10,
      height = 1.90,
      depth = 0.10,
      center = { 0.0, 0.95, 0.0 },
      color = palette.bronze_dark,
   })
   builder:add(mesh.make_box {
      width = 0.70,
      height = 0.24,
      depth = 0.10,
      center = { 0.0, 0.12, 0.0 },
      color = palette.bronze_dark,
   })
   return builder:build()
end

local function build_sign_panel()
   local builder = mesh.builder()
   builder:add(mesh.make_box {
      width = 1.20,
      height = 0.95,
      depth = 0.06,
      center = { 0.0, 1.55, 0.06 },
      color = color.rgb(248, 244, 232),
   })
   builder:add(mesh.make_box {
      width = 0.90,
      height = 0.10,
      depth = 0.02,
      center = { 0.0, 1.25, 0.10 },
      color = color.rgb(120, 30, 34),
   })
   builder:add(mesh.make_box {
      width = 0.90,
      height = 0.55,
      depth = 0.02,
      center = { 0.0, 1.70, 0.10 },
      color = color.rgb(56, 92, 74),
   })
   return builder:build()
end

local function build_organ_case(palette)
   local wood = palette.wood_dark
   local builder = mesh.builder()
   builder:add(mesh.make_box {
      width = 1.50,
      height = 1.00,
      depth = 6.70,
      center = { 0.20, 0.50, 0.0 },
      color = wood,
   })
   builder:add(mesh.make_box {
      width = 0.40,
      height = 7.00,
      depth = 6.50,
      center = { 0.55, 4.50, 0.0 },
      color = wood,
   })
   for _, z in ipairs { -3.20, 3.20 } do
      builder:add(mesh.make_box {
         width = 1.30,
         height = 6.40,
         depth = 0.36,
         center = { 0.05, 4.20, z },
         color = wood,
      })
   end
   builder:add(mesh.make_box {
      width = 1.80,
      height = 0.45,
      depth = 7.00,
      center = { 0.10, 7.20, 0.0 },
      color = wood,
   })
   return builder:build()
end

local function build_organ_pipes(palette)
   local builder = mesh.builder()
   local metal = color.rgb(236, 228, 212)
   local function rank(z_center, count, radius, base_height, spacing, x)
      for i = 1, count do
         local t = (i - 0.5) / count
         local z = z_center - spacing * (count - 1) * 0.5 + (i - 1) * spacing
         -- Taller pipes towards the centre of the rank.
         local profile = 0.55 + 0.45 * math.sin(t * math.pi)
         local height = base_height * (0.55 + profile * 0.65)
         builder:add(mesh.make_cylinder {
            radius = radius,
            height = height,
            segments = 8,
            center = { x, 1.00 + height * 0.5, z },
            color = metal,
         })
      end
   end
   rank(0.0, 13, 0.11, 4.8, 0.46, -0.25)
   rank(0.0, 15, 0.075, 3.4, 0.40, 0.15)
   return builder:build()
end

local function add_painting(groups, palette, x, y, z, width, height, angle)
   local normal = { math.sin(angle), 0.0, math.cos(angle) }
   local outward = 0.05
   local frame_transform = combined(translation(x, y, z), rotation_y(angle))
   groups.gold:add(mesh.make_box {
      width = width + 0.30,
      height = height + 0.30,
      depth = 0.10,
      color = palette.gold,
   }, { transform = frame_transform })
   groups.painting:add(mesh.make_box {
      width = width,
      height = height,
      depth = 0.06,
      color = color.rgb(255, 255, 255),
   }, {
      transform = combined(
         translation(x + normal[1] * outward, y, z + normal[3] * outward),
         rotation_y(angle)
      ),
   })
end

-- ---------------------------------------------------------------------------
-- Scene content
-- ---------------------------------------------------------------------------

function M.build(config, materials)
   local palette = materials.palette
   local h = config.hypostyle
   local c = config.cathedral
   local world = collision.world()

   local group_specs = {
      { key = "bronze", material = materials.bronze },
      { key = "iron", material = materials.iron },
      { key = "wood", material = materials.wood },
      { key = "gold", material = materials.gold },
      { key = "stone", material = materials.cathedral },
      { key = "statue", material = materials.statue },
      { key = "painting", material = materials.painting },
      { key = "organ", material = materials.organ_pipe },
      { key = "sign", material = materials.sign },
      { key = "dark", material = materials.dark },
   }
   local groups = {}
   for _, spec in ipairs(group_specs) do
      groups[spec.key] = mesh.builder()
   end
   local instances = 0
   local used = {}
   local function place(key, source, transform)
      groups[key]:add(source, transform and { transform = transform } or nil)
      instances = instances + 1
      used[key] = true
   end

   -- Cached sources: one generated mesh reused by every instance.
   local lamp_short = build_lamp(2.20, palette)
   local lamp_long = build_lamp(4.00, palette)
   local candelabrum = build_candelabrum(palette)
   local statue = build_statue(palette)
   local sign_stand = build_sign_stand(palette)
   local sign_panel = build_sign_panel()
   local organ_case = build_organ_case(palette)
   local organ_pipes = build_organ_pipes(palette)
   local pew = mesh.make_pew {
      length = 1.90,
      back_height = 1.02,
      color = palette.wood_dark,
      seat_color = palette.wood,
      back_color = palette.wood_dark,
   }
   local altar_rail = mesh.make_railing {
      length = 5.0,
      height = 1.02,
      color = palette.iron,
      cap_color = palette.gold,
   }
   local chapel_rail = mesh.make_railing {
      length = 4.0,
      height = 0.96,
      color = palette.iron,
      cap_color = palette.gold,
   }

   -- ---- Hanging lamps -----------------------------------------------------
   -- Central-nave mosque lamps under the hypostyle ceiling.
   for _, z in ipairs { -46.0, -40.0, 20.0, 26.0, 32.0, 38.0 } do
      place("bronze", lamp_short, translation(0.0, h.ceiling_center, z))
   end
   for _, x in ipairs { -15.0, 15.0 } do
      place("bronze", lamp_short, translation(x, h.ceiling_side, 24.0))
   end
   -- Cathedral crossing: a long chain from the vault.
   place("bronze", lamp_long, translation(0.0, 24.0, 0.0))
   -- Villaviciosa chapel lamp over the altar.
   place("bronze", lamp_short, translation(-22.0, 13.4, -18.0))

   -- ---- Chapel reja (Villaviciosa) ---------------------------------------
   -- Panels cover the two solid wall segments either side of the 6 m opening
   -- (world Z = -21 … -15); that clear opening stays as the route gate.
   local reja = mesh.make_grille {
      width = 3.0,
      height = 6.0,
      depth = 0.12,
      frame_size = 0.14,
      bar_size = 0.06,
      spacing = 0.30,
      rails = 3,
      frame_color = palette.bronze_dark,
      bar_color = palette.iron,
   }
   for _, z in ipairs { -22.5, -13.5 } do
      place("iron", reja, combined(
         translation(-11.65, 0.0, z),
         rotation_y(math.pi * 0.5)
      ))
      world:add_box { x = -11.65, z = z, width = 0.12, depth = 3.0 }
   end
   -- Gilded cresting over each reja panel.
   for _, z in ipairs { -22.5, -13.5 } do
      place("gold", mesh.make_box {
         width = 0.24,
         height = 0.55,
         depth = 2.8,
         center = { 0.0, 0.0, 0.0 },
         color = palette.gold,
      }, combined(translation(-11.60, 6.25, z), rotation_y(math.pi * 0.5)))
   end

   -- Altar rail flush with the front of the Villaviciosa altar platform.
   place("iron", chapel_rail, combined(
      translation(-24.1, 0.0, -18.0),
      rotation_y(math.pi * 0.5)
   ))
   world:add_box { x = -24.1, z = -18.0, width = 0.2, depth = 4.2 }

   -- ---- Capilla Mayor altar rail -----------------------------------------
   -- Two rails with a central opening keep the approach to the retablo open.
   for _, x in ipairs { -3.5, 3.5 } do
      place("iron", altar_rail, translation(x, 0.0, 5.5))
      world:add_box { x = x, z = 5.5, width = 5.2, depth = 0.24 }
   end

   -- ---- Pews --------------------------------------------------------------
   local pew_rows = { -26.0, -23.0, -20.0, -17.0, -14.0, -11.0, -8.0 }
   for _, x in ipairs { -8.6, 8.6 } do
      for _, z in ipairs(pew_rows) do
         -- Face the altar at +Z.
         place("wood", pew, translation(x, 0.0, z))
         world:add_box { x = x, z = z, width = 2.05, depth = 0.95 }
      end
   end

   -- ---- Organ -------------------------------------------------------------
   place("wood", organ_case, translation(26.4, 0.0, 0.0))
   place("organ", organ_pipes, translation(26.4, 0.0, 0.0))
   place("gold", mesh.make_box {
      width = 0.30,
      height = 0.20,
      depth = 6.90,
      center = { 0.0, 0.0, 0.0 },
      color = palette.gold,
   }, translation(25.7, 7.45, 0.0))
   world:add_box { x = 26.0, z = 0.0, width = 1.8, depth = 7.0 }

   -- ---- Framed paintings --------------------------------------------------
   -- Cathedral side walls, hung above head height and facing the aisles.
   local painting_jobs = {
      { x = c.x0 + 0.62, y = 8.2, z = -24.0, width = 2.4, height = 3.2, angle = math.pi * 0.5 },
      { x = c.x0 + 0.62, y = 8.2, z = -14.0, width = 2.4, height = 3.2, angle = math.pi * 0.5 },
      { x = c.x0 + 0.62, y = 8.2, z = -2.0, width = 2.4, height = 3.2, angle = math.pi * 0.5 },
      { x = c.x0 + 0.62, y = 8.2, z = 10.0, width = 2.4, height = 3.2, angle = math.pi * 0.5 },
      { x = c.x1 - 0.62, y = 8.2, z = -22.0, width = 2.4, height = 3.2, angle = -math.pi * 0.5 },
      { x = c.x1 - 0.62, y = 8.2, z = -8.0, width = 2.4, height = 3.2, angle = -math.pi * 0.5 },
      { x = c.x1 - 0.62, y = 8.2, z = 8.0, width = 2.4, height = 3.2, angle = -math.pi * 0.5 },
      { x = -26.2, y = 4.6, z = -15.0, width = 1.6, height = 2.1, angle = math.pi * 0.5 },
      { x = -26.2, y = 4.6, z = -21.0, width = 1.6, height = 2.1, angle = math.pi * 0.5 },
   }
   used.painting = true
   used.gold = true
   for _, job in ipairs(painting_jobs) do
      add_painting(
         groups,
         palette,
         job.x,
         job.y,
         job.z,
         job.width,
         job.height,
         job.angle
      )
      instances = instances + 2
   end

   -- ---- Candelabra --------------------------------------------------------
   for _, x in ipairs { -6.6, 6.6 } do
      place("bronze", candelabrum, translation(x, 0.0, 6.6))
      world:add_circle { x = x, z = 6.6, radius = 0.45 }
   end

   -- ---- Statues -----------------------------------------------------------
   for _, x in ipairs { -16.0, 16.0 } do
      place("stone", mesh.make_box {
         width = 1.10,
         height = 0.90,
         depth = 1.10,
         center = { 0.0, 0.45, 0.0 },
         color = palette.stone_warm,
      }, translation(x, 0.0, 0.0))
      place("statue", statue, translation(x, 0.90, 0.0))
      place("gold", mesh.make_cylinder {
         radius = 0.34,
         height = 0.05,
         segments = 16,
         center = { 0.0, 0.0, 0.0 },
         color = palette.gold,
      }, translation(x, 2.78, -0.06))
      world:add_box { x = x, z = 0.0, width = 1.1, depth = 1.1 }
   end

   -- ---- Interpretation panels --------------------------------------------
   for _, job in ipairs {
      { x = 4.0, z = -44.0, angle = math.pi },
      { x = -9.5, z = -30.0, angle = math.pi * 0.5 },
      { x = -9.0, z = -12.0, angle = math.pi * 0.5 },
   } do
      local transform = combined(translation(job.x, 0.0, job.z), rotation_y(job.angle))
      place("dark", sign_stand, transform)
      place("sign", sign_panel, transform)
      world:add_box { x = job.x, z = job.z, width = 0.45, depth = 0.45 }
   end

   -- ---- Assembled result --------------------------------------------------
   local drawables = {}
   local stats = { instances = instances, vertex_count = 0, index_count = 0 }
   for _, spec in ipairs(group_specs) do
      if used[spec.key] then
         local merged = groups[spec.key]:build()
         stats.vertex_count = stats.vertex_count + merged.vertex_count
         stats.index_count = stats.index_count + merged.index_count
         drawables[#drawables + 1] = {
            name = "contents-" .. spec.key,
            mesh = merged,
            material = spec.material,
         }
      end
   end

   return {
      drawables = drawables,
      collision = world,
      stats = stats,
   }
end

return M
