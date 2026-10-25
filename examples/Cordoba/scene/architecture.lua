local collision = require("collision")
local color = require("color")
local mathx = require("mathx")
local mesh = require("mesh")
local rig = require("rig")

local contents = rig.require("./contents")

local M = {}

local function translation(x, y, z)
   return mathx.mat4_translation(mathx.mat4(), x, y, z)
end

local function rotation_y(angle)
   return mathx.mat4_rotation_y(mathx.mat4(), angle)
end

local function rotation_x(angle)
   return mathx.mat4_rotation_x(mathx.mat4(), angle)
end

-- mathx.mat4_multiply is written for Rig's row-vector composition convention
-- and returns b * a. Architecture code reads more naturally as standard
-- `T * R`, so flip the arguments here.
local function combined(a, b)
   return mathx.mat4_multiply(mathx.mat4(), b, a)
end

local function add(builder, source, transform)
   builder:add(source, { transform = transform })
end

local function add_box(builder, options, x, y, z, angle)
   local source = mesh.make_box(options)
   add(builder, source, angle and combined(translation(x, y, z), rotation_y(angle))
      or translation(x, y, z))
end

local function add_cylinder(builder, options, x, y, z, angle)
   local source = mesh.make_cylinder(options)
   add(builder, source, angle and combined(translation(x, y, z), rotation_y(angle))
      or translation(x, y, z))
end

local function add_pointed_arch(builder, options, x, y, z, angle)
   local source = mesh.make_pointed_arch(options)
   add(builder, source, angle and combined(translation(x, y, z), rotation_y(angle))
      or translation(x, y, z))
end

local function add_slab(builder, x0, x1, z0, z1, underside_y, thickness, tint)
   local width = x1 - x0
   local depth = z1 - z0
   if width <= 0.0 or depth <= 0.0 then
      return
   end
   add_box(builder, {
      width = width,
      height = thickness,
      depth = depth,
      color = tint,
   }, (x0 + x1) * 0.5, underside_y + thickness * 0.5, (z0 + z1) * 0.5)
end

local function add_glass(builder, width, height, x, y, z, angle)
   add(builder, mesh.make_quad {
      width = width,
      height = height,
      color = color.rgb(255, 255, 255),
   }, combined(translation(x, y, z), rotation_y(angle)))
end

local function arch_source(kind, span, thickness, depth, palette)
   if kind == "horseshoe" then
      return mesh.make_horseshoe_arch {
         radius = span * 0.5,
         thickness = thickness,
         depth = depth,
         segments = span > 7.0 and 20 or 14,
         stripe_colors = { palette.brick, palette.cream },
      }
   end
   return mesh.make_round_arch {
      radius = span * 0.5,
      thickness = thickness,
      depth = depth,
      segments = span > 7.0 and 20 or 14,
      stripe_colors = { palette.brick, palette.cream },
   }
end

local function add_arch(builder, source, cx, cz, spring, along_z)
   local transform = translation(cx, spring, cz)
   if along_z then
      transform = combined(transform, rotation_y(math.pi * 0.5))
   end
   add(builder, source, transform)
end

local function build_hypostyle(config, palette)
   local columns = mesh.builder()
   local arches = mesh.builder()
   local world = collision.world()
   local h = config.hypostyle
   local grid = config.grid

   local column_mesh = mesh.make_column {
      radius = h.column.radius,
      height = h.column.shaft_height,
      base_height = h.column.base_height,
      base_radius = h.column.base_radius,
      capital_height = h.column.capital_height,
      capital_radius = h.column.capital_radius,
      abacus_height = h.column.abacus_height,
      abacus_width = h.column.abacus_width,
      segments = h.column.segments,
      color = palette.column_shaft,
      base_color = palette.stone_warm,
      capital_color = palette.stone_warm,
      abacus_color = palette.stone_pale,
   }

   local lower_cache = {}
   local upper_cache = {}
   local function cached_arch(cache, kind, span)
      local key = span .. ":" .. kind
      local source = cache[key]
      if source == nil then
         source = arch_source(
            kind,
            span,
            kind == "horseshoe" and h.lower_thickness or h.upper_thickness,
            h.arch_depth,
            palette
         )
         cache[key] = source
      end
      return source
   end

   local function has_column(x, z)
      return config.has_column(x, z)
   end

   for _, x in ipairs(grid.xs) do
      for _, z in ipairs(grid.zs) do
         if has_column(x, z) then
            add(columns, column_mesh, translation(x, 0.0, z))
            world:add_circle {
               x = x,
               z = z,
               radius = h.column.collision_radius,
            }
         end
      end
   end

   for _, z in ipairs(grid.zs) do
      for i = 1, #grid.xs - 1 do
         local x0, x1 = grid.xs[i], grid.xs[i + 1]
         if has_column(x0, z) and has_column(x1, z) then
            local span = x1 - x0
            local cx = (x0 + x1) * 0.5
            add_arch(
               arches,
               cached_arch(lower_cache, "horseshoe", span),
               cx,
               z,
               h.lower_spring,
               false
            )
            add_arch(
               arches,
               cached_arch(upper_cache, "round", span),
               cx,
               z,
               h.upper_spring,
               false
            )
         end
      end
   end

   for _, x in ipairs(grid.xs) do
      for j = 1, #grid.zs - 1 do
         local z0, z1 = grid.zs[j], grid.zs[j + 1]
         if has_column(x, z0) and has_column(x, z1) then
            local span = z1 - z0
            local cz = (z0 + z1) * 0.5
            add_arch(
               arches,
               cached_arch(lower_cache, "horseshoe", span),
               x,
               cz,
               h.lower_spring,
               true
            )
            add_arch(
               arches,
               cached_arch(upper_cache, "round", span),
               x,
               cz,
               h.upper_spring,
               true
            )
         end
      end
   end

   return columns, arches, world
end

local function build_floors(config, palette)
   local e = config.envelope
   local c = config.cathedral
   local builder = mesh.builder()

   local full_width = e.x1 - e.x0
   local full_depth = e.z1 - e.z0
   add(
      builder,
      mesh.make_floor_bay {
         width = full_width,
         depth = full_depth,
         segments_x = 20,
         segments_z = 22,
         color = palette.floor_mosque,
         uv_scale = 0.35,
      },
      translation(0.0, 0.0, (e.z0 + e.z1) * 0.5)
   )

   add(
      builder,
      mesh.make_floor_bay {
         width = 10.0,
         depth = full_depth,
         segments_x = 2,
         segments_z = 22,
         color = palette.floor_nave,
         uv_scale = 0.5,
      },
      translation(0.0, 0.008, (e.z0 + e.z1) * 0.5)
   )

   add(
      builder,
      mesh.make_floor_bay {
         width = c.x1 - c.x0,
         depth = c.z1 - c.z0,
         segments_x = 8,
         segments_z = 8,
         color = palette.floor_cathedral,
         uv_scale = 0.45,
      },
      translation(0.0, 0.016, (c.z0 + c.z1) * 0.5)
   )

   return builder
end

local function build_hypostyle_ceilings(config, materials)
   local builder = mesh.builder()
   local palette = materials.palette
   local h = config.hypostyle
   local c = config.cathedral
   local e = config.envelope

   add_slab(builder, e.x0, c.x0, e.z0, e.z1, h.ceiling_side, 0.30, palette.wood)
   add_slab(builder, c.x1, e.x1, e.z0, e.z1, h.ceiling_side, 0.30, palette.wood)

   add_slab(builder, c.x0, -5.0, e.z0, c.z0, h.ceiling_side, 0.30, palette.wood)
   add_slab(builder, 5.0, c.x1, e.z0, c.z0, h.ceiling_side, 0.30, palette.wood)
   add_slab(builder, c.x0, -5.0, c.z1, e.z1, h.ceiling_side, 0.30, palette.wood)
   add_slab(builder, 5.0, c.x1, c.z1, e.z1, h.ceiling_side, 0.30, palette.wood)

   add_slab(builder, -5.0, 5.0, e.z0, c.z0, h.ceiling_center, 0.32, palette.wood_dark)
   add_slab(builder, -5.0, 5.0, c.z1, e.z1, h.ceiling_center, 0.32, palette.wood_dark)

   local fascia_color = palette.stone_warm
   for _, x in ipairs { -5.0, 5.0 } do
      for _, range in ipairs { { e.z0, c.z0 }, { c.z1, e.z1 } } do
         add_box(builder, {
            width = 0.24,
            height = h.ceiling_center - h.ceiling_side,
            depth = range[2] - range[1],
            color = fascia_color,
         }, x, (h.ceiling_side + h.ceiling_center) * 0.5, (range[1] + range[2]) * 0.5)
      end
   end

   return builder
end

local function build_boundary(config, materials)
   local stone = mesh.builder()
   local dark = mesh.builder()
   local world = collision.world()
   local palette = materials.palette
   local e = config.envelope
   local width = e.x1 - e.x0
   local depth = e.z1 - e.z0
   local center_z = (e.z0 + e.z1) * 0.5
   local height = 14.0
   local thickness = 0.7

   local north = mesh.make_wall {
      width = width,
      height = height,
      thickness = thickness,
      color = palette.stone,
      reveal_color = palette.stone_warm,
      openings = {
         { x = (width - 8.0) * 0.5, y = 0.0, width = 8.0, height = 9.0 },
      },
   }
   add(stone, north, translation(0.0, 0.0, e.z0))
   world:add_box { x = 0.0, z = e.z0, width = width, depth = thickness }
   add(dark, mesh.make_quad { width = 8.0, height = 9.0, color = palette.recess },
      translation(0.0, 4.5, e.z0 - thickness * 0.5 - 0.02))

   -- The qibla wall is solid; the mihrab niche is added by `build_maqsura`.
   local south = mesh.make_wall {
      width = width,
      height = height,
      thickness = thickness,
      color = palette.stone,
      reveal_color = palette.stone_warm,
   }
   add(stone, south, translation(0.0, 0.0, e.z1))
   world:add_box { x = 0.0, z = e.z1, width = width, depth = thickness }

   local east = mesh.make_wall {
      width = depth,
      height = height,
      thickness = thickness,
      color = palette.stone,
      reveal_color = palette.stone_warm,
   }
   add(stone, east, combined(translation(e.x1, 0.0, center_z), rotation_y(math.pi * 0.5)))
   world:add_box { x = e.x1, z = center_z, width = thickness, depth = depth }

   local west = mesh.make_wall {
      width = depth,
      height = height,
      thickness = thickness,
      color = palette.stone,
      reveal_color = palette.stone_warm,
   }
   add(stone, west, combined(translation(e.x0, 0.0, center_z), rotation_y(-math.pi * 0.5)))
   world:add_box { x = e.x0, z = center_z, width = thickness, depth = depth }

   return stone, dark, world
end

local function build_cathedral(config, materials)
   local stone = mesh.builder()
   local glass = mesh.builder()
   local gold = mesh.builder()
   local iron = mesh.builder()
   local brick = mesh.builder()
   local world = collision.world()
   local palette = materials.palette
   local c = config.cathedral
   local width = c.x1 - c.x0
   local depth = c.z1 - c.z0
   local center_z = (c.z0 + c.z1) * 0.5

   local portal_x = (width - c.portal_width) * 0.5
   local north = mesh.make_wall {
      width = width,
      height = c.wall_height,
      thickness = c.wall_thickness,
      color = palette.stone_pale,
      reveal_color = palette.stone_warm,
      openings = {
         {
            x = portal_x,
            y = 0.0,
            width = c.portal_width,
            height = c.portal_height,
         },
      },
   }
   add(stone, north, translation(0.0, 0.0, c.z0))
   local side_width = (width - c.portal_width) * 0.5
   world:add_box {
      x = c.x0 + side_width * 0.5,
      z = c.z0,
      width = side_width,
      depth = c.wall_thickness,
   }
   world:add_box {
      x = c.x1 - side_width * 0.5,
      z = c.z0,
      width = side_width,
      depth = c.wall_thickness,
   }

   local south = mesh.make_wall {
      width = width,
      height = c.wall_height,
      thickness = c.wall_thickness,
      color = palette.stone_pale,
      reveal_color = palette.stone_warm,
      openings = {
         {
            x = portal_x,
            y = 0.0,
            width = c.portal_width,
            height = c.portal_height,
         },
         {
            x = width * 0.5 - 18.0 - 2.0,
            y = 0.0,
            width = 4.0,
            height = 8.0,
         },
         {
            x = width * 0.5 + 18.0 - 2.0,
            y = 0.0,
            width = 4.0,
            height = 8.0,
         },
      },
   }
   add(stone, south, translation(0.0, 0.0, c.z1))
   -- The central portal sits behind the retablo; two side exits keep the return
   -- route through the south hypostyle open.
   local south_segments = {
      { -28.0, -20.0 },
      { -16.0, -4.0 },
      { 4.0, 16.0 },
      { 20.0, 28.0 },
   }
   for _, segment in ipairs(south_segments) do
      local segment_width = segment[2] - segment[1]
      world:add_box {
         x = (segment[1] + segment[2]) * 0.5,
         z = c.z1,
         width = segment_width,
         depth = c.wall_thickness,
      }
   end

   -- Close the upper end of the vault above the north/south walls. Without this
   -- the view through the portal shows the empty background above the far wall.
   local upper_height = c.vault_spring + c.vault_radius - c.wall_height
   for _, z in ipairs { c.z0, c.z1 } do
      add_box(stone, {
         width = width,
         height = upper_height,
         depth = c.wall_thickness,
         color = palette.stone_pale,
      }, 0.0, c.wall_height + upper_height * 0.5, z)
   end

   local function add_grille(center_x)
      local grille_width = 6.0
      local grille_height = 4.0
      local grille_z = c.z0 + c.wall_thickness * 0.5 + 0.12
      add_box(iron, {
         width = grille_width,
         height = 0.12,
         depth = 0.16,
         color = palette.recess,
      }, center_x, grille_height, grille_z)
      add_box(iron, {
         width = grille_width,
         height = 0.12,
         depth = 0.16,
         color = palette.recess,
      }, center_x, 0.18, grille_z)
      local bars = 13
      for i = 0, bars - 1 do
         local x = center_x - grille_width * 0.5 + (i / (bars - 1)) * grille_width
         add_box(iron, {
            width = 0.07,
            height = grille_height - 0.3,
            depth = 0.10,
            color = palette.recess,
         }, x, (grille_height + 0.18) * 0.5, grille_z)
      end
      world:add_box {
         x = center_x,
         z = grille_z,
         width = grille_width,
         depth = 0.16,
      }
   end
   add_grille(-13.0)
   add_grille(13.0)

   local window_centers = { 6.0, 16.0, 26.0, 36.0 }
   local window_width = 3.2
   local window_height = 7.0
   local window_y = 8.0
   local window_openings = {}
   for _, center in ipairs(window_centers) do
      window_openings[#window_openings + 1] = {
         x = center - window_width * 0.5,
         y = window_y,
         width = window_width,
         height = window_height,
      }
   end

   local west_wall = mesh.make_wall {
      width = depth,
      height = c.wall_height,
      thickness = c.wall_thickness,
      color = palette.stone_pale,
      reveal_color = palette.stone_warm,
      openings = window_openings,
   }
   add(
      stone,
      west_wall,
      combined(translation(c.x0, 0.0, center_z), rotation_y(-math.pi * 0.5))
   )
   world:add_box {
      x = c.x0,
      z = center_z,
      width = c.wall_thickness,
      depth = depth,
   }

   local east_wall = mesh.make_wall {
      width = depth,
      height = c.wall_height,
      thickness = c.wall_thickness,
      color = palette.stone_pale,
      reveal_color = palette.stone_warm,
      openings = window_openings,
   }
   add(
      stone,
      east_wall,
      combined(translation(c.x1, 0.0, center_z), rotation_y(math.pi * 0.5))
   )
   world:add_box {
      x = c.x1,
      z = center_z,
      width = c.wall_thickness,
      depth = depth,
   }

   for _, center in ipairs(window_centers) do
      local local_offset = center - depth * 0.5
      local west_z = center_z + local_offset
      local east_z = center_z - local_offset
      local y = window_y + window_height * 0.5
      add_glass(
         glass,
         window_width - 0.2,
         window_height - 0.2,
         c.x0 + c.wall_thickness * 0.55,
         y,
         west_z,
         math.pi * 0.5
      )
      add_glass(
         glass,
         window_width - 0.2,
         window_height - 0.2,
         c.x1 - c.wall_thickness * 0.55,
         y,
         east_z,
         -math.pi * 0.5
      )
   end

   add(
      stone,
      mesh.make_barrel_vault {
         radius = c.vault_radius,
         thickness = c.vault_thickness,
         length = c.vault_length,
         segments = 24,
         color = palette.stone_pale,
      },
      translation(0.0, c.vault_spring, center_z)
   )

   -- The west side-aisle roof opens over the Villaviciosa chapel so its ribbed
   -- vault is visible from inside.
   add_slab(
      stone,
      c.x0,
      -c.vault_radius,
      c.z0,
      -24.0,
      c.vault_spring,
      0.35,
      palette.stone_warm
   )
   add_slab(
      stone,
      c.x0,
      -c.vault_radius,
      -12.0,
      c.z1,
      c.vault_spring,
      0.35,
      palette.stone_warm
   )
   add_slab(
      stone,
      c.vault_radius,
      c.x1,
      c.z0,
      c.z1,
      c.vault_spring,
      0.35,
      palette.stone_warm
   )

   for _, z in ipairs { c.z0 + 3.0, c.z0 + 11.0, c.z0 + 19.0, c.z0 + 27.0, c.z0 + 35.0 } do
      add(
         stone,
         mesh.make_round_arch {
            radius = c.vault_radius,
            thickness = 0.50,
            depth = 0.9,
            segments = 20,
            color = palette.stone_pale,
         },
         translation(0.0, c.vault_spring, z)
      )
   end

   add_box(stone, {
      width = 0.45,
      height = 0.40,
      depth = c.vault_length,
      color = palette.stone_pale,
   }, 0.0, c.vault_spring + c.vault_radius, center_z)

   for _, z in ipairs { c.z0 + 0.5, c.z1 - 0.5 } do
      add(
         stone,
         mesh.make_round_arch {
            radius = 5.0,
            thickness = 0.55,
            depth = 0.9,
            segments = 20,
            color = palette.stone_pale,
         },
         translation(0.0, 7.0, z)
      )
   end

   add_box(brick, {
      width = 12.0,
      height = 0.45,
      depth = 4.0,
      color = palette.brick,
   }, 0.0, 0.225, 8.0)
   world:add_box { x = 0.0, z = 8.0, width = 12.0, depth = 4.0 }

   add_box(stone, {
      width = 4.0,
      height = 1.3,
      depth = 1.2,
      color = palette.stone_pale,
   }, 0.0, 1.10, 8.0)

   add_box(gold, {
      width = 3.2,
      height = 0.9,
      depth = 0.06,
      color = palette.gold,
   }, 0.0, 1.35, 7.36)
   add_box(gold, {
      width = 0.16,
      height = 1.7,
      depth = 0.16,
      color = palette.gold,
   }, 0.0, 2.55, 7.58)
   add_box(gold, {
      width = 0.9,
      height = 0.16,
      depth = 0.16,
      color = palette.gold,
   }, 0.0, 2.95, 7.58)

   return stone, glass, gold, iron, brick, world
end

-- Phase 7 Christian core: nave arcade, crossing ribs, choir, Capilla Mayor
-- retablo, and the Villaviciosa chapel. The outer cathedral shell remains in
-- `build_cathedral`; this pass adds the volumes and hero furniture that make the
-- insertion legible from the route.
local function build_christian_core(config, materials)
   local stone = mesh.builder()
   local wood = mesh.builder()
   local gold = mesh.builder()
   local iron = mesh.builder()
   local stained = mesh.builder()
   local statue = mesh.builder()
   local cloth = mesh.builder()
   local world = collision.world()
   local palette = materials.palette
   local c = config.cathedral

   -- Nave arcade piers at the edge of the tall central vessel. They also carry
   -- the pointed arcade that separates the nave from the side aisles.
   local pier_zs = { -28.0, -20.0, -12.0, -4.0, 4.0, 12.0 }
   local pier_present = { [-12.0] = {}, [12.0] = {} }
   local pier_mesh = mesh.make_column {
      radius = 0.46,
      height = 8.5,
      base_height = 0.45,
      base_radius = 0.68,
      capital_height = 0.55,
      capital_radius = 0.68,
      abacus_height = 0.20,
      abacus_width = 1.15,
      segments = 16,
      color = palette.stone_warm,
      base_color = palette.stone_pale,
      capital_color = palette.stone_pale,
      abacus_color = palette.stone_pale,
   }
   for _, x in ipairs { -12.0, 12.0 } do
      for _, z in ipairs(pier_zs) do
         local in_villaviciosa = x < 0.0 and z > -24.001 and z < -12.0
         if not in_villaviciosa then
            add(stone, pier_mesh, translation(x, 0.0, z))
            world:add_circle { x = x, z = z, radius = 0.62 }
            pier_present[x][z] = true
         end
      end
   end
   for _, x in ipairs { -12.0, 12.0 } do
      for i = 1, #pier_zs - 1 do
         local z0, z1 = pier_zs[i], pier_zs[i + 1]
         if pier_present[x][z0] and pier_present[x][z1] then
            add_pointed_arch(
               stone,
               {
                  span = z1 - z0,
                  radius = 5.6,
                  thickness = 0.42,
                  depth = 0.82,
                  segments = 12,
                  color = palette.stone_pale,
               },
               x,
               8.8,
               (z0 + z1) * 0.5,
               math.pi * 0.5
            )
         end
      end
   end

   -- Transept/crossing arches. The central pair spans the nave; the side pairs
   -- open the transept arms through the lower aisles.
   for _, z in ipairs { -4.0, 4.0 } do
      add_pointed_arch(
         stone,
         {
            span = 24.0,
            radius = 15.0,
            thickness = 0.55,
            depth = 0.95,
            segments = 18,
            color = palette.stone_pale,
         },
         0.0,
         11.5,
         z
      )
      for _, x in ipairs { -20.0, 20.0 } do
         add_pointed_arch(
            stone,
            {
               span = 16.0,
               radius = 11.0,
               thickness = 0.45,
               depth = 0.80,
               segments = 14,
               color = palette.stone_pale,
            },
            x,
            8.5,
            z
         )
      end
   end

   -- Diagonal ribs and a gilded boss give the crossing its star-like focus.
   local diagonal = math.atan2(8.0, 24.0)
   for _, angle in ipairs { diagonal, -diagonal } do
      add_pointed_arch(
         stone,
         {
            span = 25.0,
            radius = 15.0,
            thickness = 0.24,
            depth = 0.42,
            segments = 18,
            color = palette.stone_pale,
         },
         0.0,
         11.5,
         0.0,
         angle
      )
   end
   add_cylinder(
      gold,
      { radius = 1.15, height = 0.18, segments = 16, color = palette.gold },
      0.0,
      25.72,
      0.0
   )
   for i = 0, 7 do
      local angle = i * math.pi * 0.25
      add_box(
         gold,
         { width = 0.10, height = 0.10, depth = 1.9, color = palette.gold },
         math.cos(angle) * 0.95,
         25.68,
         math.sin(angle) * 0.95,
         -angle
      )
   end

   -- Choir enclosure along the central vessel. The central aisle stays open.
   for _, x in ipairs { -4.35, 4.35 } do
      add_box(wood, {
         width = 1.15,
         height = 0.28,
         depth = 12.0,
         color = palette.wood,
      }, x, 0.62, -4.0)
      add_box(wood, {
         width = 0.38,
         height = 2.15,
         depth = 12.0,
         color = palette.wood_dark,
      }, x + (x < 0.0 and -0.42 or 0.42), 1.18, -4.0)
      add_box(gold, {
         width = 0.16,
         height = 0.16,
         depth = 12.0,
         color = palette.gold,
      }, x + (x < 0.0 and -0.42 or 0.42), 2.28, -4.0)
      world:add_box {
         x = x,
         z = -4.0,
         width = 1.6,
         depth = 12.0,
      }
   end

   -- Capilla Mayor retablo. The central south portal is now a backdrop behind
   -- the retable; the two Phase 7 side exits keep the loop route open.
   add_box(cloth, {
      width = 4.2,
      height = 0.10,
      depth = 1.35,
      color = palette.burgundy,
   }, 0.0, 1.80, 8.0)
   add_box(gold, {
      width = 10.0,
      height = 1.15,
      depth = 0.95,
      color = palette.gold,
   }, 0.0, 0.72, 12.75)
   add_box(wood, {
      width = 8.7,
      height = 7.8,
      depth = 0.45,
      color = palette.wood_dark,
   }, 0.0, 5.20, 12.96)
   add_box(gold, {
      width = 9.0,
      height = 0.55,
      depth = 0.80,
      color = palette.gold,
   }, 0.0, 8.35, 12.88)
   for _, x in ipairs { -3.75, -1.25, 1.25, 3.75 } do
      add_cylinder(gold, {
         radius = 0.22,
         height = 7.0,
         segments = 10,
         color = palette.gold,
      }, x, 4.62, 12.34)
   end
   add_box(wood, {
      width = 3.15,
      height = 4.75,
      depth = 0.18,
      color = palette.recess,
   }, 0.0, 5.10, 12.66)
   add_pointed_arch(
      gold,
      {
         span = 3.3,
         radius = 2.35,
         thickness = 0.18,
         depth = 0.16,
         segments = 8,
         color = palette.gold,
      },
      0.0,
      5.0,
      12.18
   )
   add_box(gold, {
      width = 3.7,
      height = 0.18,
      depth = 0.22,
      color = palette.gold,
   }, 0.0, 7.55, 12.48)
   add_cylinder(statue, {
      radius = 0.34,
      height = 1.85,
      segments = 10,
      color = palette.stone_pale,
   }, 0.0, 3.15, 12.30)
   add_box(statue, {
      width = 0.48,
      height = 0.48,
      depth = 0.48,
      color = palette.stone_pale,
   }, 0.0, 4.25, 12.30)
   add_box(gold, {
      width = 0.95,
      height = 0.95,
      depth = 0.10,
      color = palette.gold,
   }, 0.0, 4.25, 12.10)
   add_box(gold, {
      width = 6.0,
      height = 3.4,
      depth = 0.50,
      color = palette.gold,
   }, 0.0, 10.15, 12.92)
   add_box(wood, {
      width = 4.8,
      height = 2.4,
      depth = 0.18,
      color = palette.wood_dark,
   }, 0.0, 10.15, 12.62)
   add_box(gold, {
      width = 4.0,
      height = 0.28,
      depth = 0.55,
      color = palette.gold,
   }, 0.0, 12.02, 12.90)
   add_box(gold, {
      width = 0.18,
      height = 1.1,
      depth = 0.18,
      color = palette.gold,
   }, 0.0, 12.55, 12.90)
   add_box(gold, {
      width = 0.65,
      height = 0.16,
      depth = 0.18,
      color = palette.gold,
   }, 0.0, 12.82, 12.90)
   world:add_box { x = 0.0, z = 12.75, width = 10.2, depth = 1.2 }

   for _, x in ipairs { -3.0, -1.5, 1.5, 3.0 } do
      add_cylinder(gold, {
         radius = 0.055,
         height = 0.85,
         segments = 6,
         color = palette.gold,
      }, x, 1.78, 7.12)
   end

   -- Villaviciosa chapel: a ribbed side vessel opening west from the cathedral
   -- aisle. It is a small hero chapel rather than a full perimeter-chapel row.
   local chapel_x0 = -28.0
   local chapel_x1 = -12.0
   local chapel_z0 = -24.0
   local chapel_z1 = -12.0
   local chapel_z = (chapel_z0 + chapel_z1) * 0.5
   local chapel_width = chapel_x1 - chapel_x0
   local chapel_depth = chapel_z1 - chapel_z0

   local chapel_east = mesh.make_wall {
      width = chapel_depth,
      height = 15.5,
      thickness = 0.6,
      color = palette.stone_pale,
      reveal_color = palette.stone_warm,
      openings = {
         { x = 3.0, y = 0.0, width = 6.0, height = 9.0 },
      },
   }
   add(
      stone,
      chapel_east,
      combined(translation(chapel_x1, 0.0, chapel_z), rotation_y(math.pi * 0.5))
   )
   world:add_box {
      x = chapel_x1,
      z = -22.5,
      width = 0.6,
      depth = 3.0,
   }
   world:add_box {
      x = chapel_x1,
      z = -13.5,
      width = 0.6,
      depth = 3.0,
   }

   for _, z in ipairs { chapel_z0, chapel_z1 } do
      local chapel_end = mesh.make_wall {
         width = chapel_width,
         height = 15.5,
         thickness = 0.6,
         color = palette.stone_pale,
         reveal_color = palette.stone_warm,
      }
      add(stone, chapel_end, translation((chapel_x0 + chapel_x1) * 0.5, 0.0, z))
      world:add_box {
         x = (chapel_x0 + chapel_x1) * 0.5,
         z = z,
         width = chapel_width,
         depth = 0.6,
      }
   end

   add(
      stone,
      mesh.make_barrel_vault {
         radius = 5.0,
         thickness = 0.40,
         length = chapel_depth,
         segments = 16,
         color = palette.stone_pale,
      },
      translation(-20.0, 10.0, chapel_z)
   )
   for _, z in ipairs { chapel_z0, chapel_z, chapel_z1 } do
      add_pointed_arch(
         stone,
         {
            span = 10.0,
            radius = 6.5,
            thickness = 0.38,
            depth = 0.62,
            segments = 12,
            color = palette.stone_pale,
         },
         -20.0,
         10.0,
         z
      )
   end
   add_slab(stone, -28.0, -25.0, chapel_z0, chapel_z1, 10.0, 0.30, palette.stone_warm)
   add_slab(stone, -15.0, -12.0, chapel_z0, chapel_z1, 10.0, 0.30, palette.stone_warm)
   add_slab(stone, -28.0, -25.0, chapel_z0, chapel_z1, 14.0, 0.35, palette.stone_warm)
   add_slab(stone, -15.0, -12.0, chapel_z0, chapel_z1, 14.0, 0.35, palette.stone_warm)

   add_glass(
      stained,
      2.8,
      6.8,
      -27.45,
      11.5,
      -16.0,
      math.pi * 0.5
   )

   -- Chapel wall articulation: corner pilasters, a blind arcade, and a ridge
   -- rib keep the small vessel from reading as a plain box.
   for _, x in ipairs { -27.55, -12.45 } do
      for _, z in ipairs { chapel_z0 + 0.35, chapel_z1 - 0.35 } do
         add_box(stone, {
            width = 0.40,
            height = 9.2,
            depth = 0.40,
            color = palette.stone_pale,
         }, x, 4.6, z)
      end
   end
   for _, z in ipairs { chapel_z0 + 0.32, chapel_z1 - 0.32 } do
      for _, cx in ipairs { -25.5, -22.5, -21.5, -18.5, -17.5, -14.5 } do
         add_box(stone, {
            width = 0.24,
            height = 2.5,
            depth = 0.24,
            color = palette.stone_pale,
         }, cx, 1.25, z)
      end
      for _, cx in ipairs { -24.0, -20.0, -16.0 } do
         add_pointed_arch(
            stone,
            {
               span = 3.0,
               radius = 2.25,
               thickness = 0.20,
               depth = 0.28,
               segments = 8,
               color = palette.stone_pale,
            },
            cx,
            2.5,
            z
         )
      end
   end
   add_box(stone, {
      width = 0.22,
      height = 0.22,
      depth = chapel_depth - 0.6,
      color = palette.stone_pale,
   }, -20.0, 15.0, chapel_z)

   -- Stone portal frame and pointed archivolt around the chapel opening.
   for _, z in ipairs { chapel_z - 3.0, chapel_z + 3.0 } do
      add_box(stone, {
         width = 0.40,
         height = 9.0,
         depth = 0.55,
         color = palette.stone_pale,
      }, chapel_x1 + 0.12, 4.5, z)
   end
   add_pointed_arch(
      stone,
      {
         span = 6.6,
         radius = 4.5,
         thickness = 0.42,
         depth = 0.34,
         segments = 10,
         color = palette.stone_pale,
      },
      chapel_x1 + 0.12,
      5.8,
      chapel_z,
      math.pi * 0.5
   )

   add_box(stone, {
      width = 3.6,
      height = 0.45,
      depth = 4.2,
      color = palette.stone_warm,
   }, -26.1, 0.225, chapel_z)
   add_box(gold, {
      width = 0.25,
      height = 4.8,
      depth = 3.6,
      color = palette.gold,
   }, -27.35, 2.6, chapel_z)
   add_box(wood, {
      width = 0.18,
      height = 3.7,
      depth = 2.9,
      color = palette.recess,
   }, -27.20, 2.5, chapel_z)
   add_cylinder(statue, {
      radius = 0.28,
      height = 1.55,
      segments = 8,
      color = palette.stone_pale,
   }, -26.95, 1.9, chapel_z)
   add_box(stone, {
      width = 1.35,
      height = 0.90,
      depth = 3.4,
      color = palette.stone_warm,
   }, -26.55, 0.45, chapel_z)
   add_box(cloth, {
      width = 1.45,
      height = 0.08,
      depth = 3.5,
      color = palette.burgundy,
   }, -26.55, 0.94, chapel_z)
   add_box(gold, {
      width = 0.12,
      height = 0.12,
      depth = 3.8,
      color = palette.gold,
   }, -27.22, 5.15, chapel_z)
   add_pointed_arch(
      gold,
      {
         span = 2.5,
         radius = 1.7,
         thickness = 0.14,
         depth = 0.12,
         segments = 8,
         color = palette.gold,
      },
      -27.05,
      2.0,
      chapel_z,
      math.pi * 0.5
   )
   add_box(gold, {
      width = 0.08,
      height = 1.15,
      depth = 1.15,
      color = palette.gold,
   }, -27.02, 2.75, chapel_z)
   for _, z in ipairs { chapel_z - 1.25, chapel_z + 1.25 } do
      add_cylinder(gold, {
         radius = 0.16,
         height = 4.6,
         segments = 8,
         color = palette.gold,
      }, -26.95, 2.5, z)
   end
   for _, z in ipairs { chapel_z - 1.4, chapel_z - 0.6, chapel_z + 0.6, chapel_z + 1.4 } do
      add_cylinder(gold, {
         radius = 0.05,
         height = 0.65,
         segments = 6,
         color = palette.gold,
      }, -26.1, 1.30, z)
   end
   add_box(gold, {
      width = 0.10,
      height = 0.12,
      depth = 6.0,
      color = palette.gold,
   }, -11.64, 7.0, chapel_z)
   add_box(iron, {
      width = 0.10,
      height = 5.0,
      depth = 0.10,
      color = palette.recess,
   }, -11.64, 4.6, chapel_z - 2.9)
   add_box(iron, {
      width = 0.10,
      height = 5.0,
      depth = 0.10,
      color = palette.recess,
   }, -11.64, 4.6, chapel_z + 2.9)
   world:add_box { x = -26.1, z = chapel_z, width = 4.2, depth = 4.2 }

   return stone, wood, gold, iron, stained, statue, cloth, world
end

-- Phase 9 maqsura and mihrab at the south (qibla) end of the central vessel.
local function build_maqsura(config, materials)
   local stone = mesh.builder()
   local gold = mesh.builder()
   local dark = mesh.builder()
   local iron = mesh.builder()
   local world = collision.world()
   local palette = materials.palette
   local m = config.maqsura
   local center_z = (m.z0 + m.z1) * 0.5

   -- Raised maqsura platform.
   add_box(stone, {
      width = m.x1 - m.x0,
      height = 0.22,
      depth = m.z1 - m.z0 - 1.0,
      color = palette.stone_warm,
   }, 0.0, 0.11, center_z - 0.5)

   -- Two domed bays over the central axis, springing just under the hypostyle
   -- ceiling so the dome concave face reads from the floor.
   local dome_spring = 8.6
   for _, z in ipairs { m.z0 + 6.0, m.z0 + 13.0 } do
      add(stone, mesh.make_dome {
         radius = 5.6,
         height = 3.6,
         thickness = 0.4,
         segments = 20,
         rings = 8,
         color = palette.stone_pale,
      }, translation(0.0, dome_spring, z))
   end
   -- Mihrab hood behind the qibla-wall niche.
   add(stone, mesh.make_dome {
      radius = 3.0,
      height = 2.4,
      thickness = 0.35,
      segments = 18,
      rings = 7,
      color = palette.stone_pale,
   }, translation(0.0, 6.2, m.z1 - 2.2))

   -- Maqsura screen: gilded rails with a central opening onto the mihrab.
   for _, x in ipairs { -8.0, 8.0 } do
      add(iron, mesh.make_railing {
         length = 14.0,
         height = 1.05,
         color = palette.iron,
         cap_color = palette.gold,
      }, translation(x, 0.0, m.z0))
      world:add_box { x = x, z = m.z0, width = 14.0, depth = 0.24 }
   end

   -- Qibla wall mihrab: recess, horseshoe arch, flanking marble columns, and
   -- gilded decoration.
   local wall_z = m.z1
   add(dark, mesh.make_quad {
      width = 3.2,
      height = 5.2,
      color = palette.recess,
   }, combined(translation(0.0, 2.6, wall_z - 0.45), rotation_y(math.pi)))
   for _, x in ipairs { -2.0, 2.0 } do
      add_cylinder(stone, {
         radius = 0.30,
         height = 4.6,
         segments = 12,
         color = palette.stone_pale,
      }, x, 2.3, wall_z - 0.7)
      add_cylinder(gold, {
         radius = 0.34,
         height = 0.24,
         segments = 12,
         color = palette.gold,
      }, x, 4.7, wall_z - 0.7)
      world:add_circle { x = x, z = wall_z - 0.7, radius = 0.4 }
   end
   add(stone, mesh.make_horseshoe_arch {
      radius = 1.9,
      thickness = 0.36,
      depth = 0.5,
      segments = 16,
      stripe_colors = { palette.gold, palette.stone_pale },
   }, combined(translation(0.0, 3.1, wall_z - 0.55), rotation_y(math.pi)))
   add_box(gold, {
      width = 5.4,
      height = 0.30,
      depth = 0.5,
      color = palette.gold,
   }, 0.0, 4.95, wall_z - 0.55)
   add_box(gold, {
      width = 3.6,
      height = 0.22,
      depth = 0.4,
      color = palette.gold,
   }, 0.0, 5.35, wall_z - 0.5)
   -- A dim gilded panel deep in the niche so the recess reads rather than
   -- turning into a black hole.
   add_box(gold, {
      width = 2.2,
      height = 2.8,
      depth = 0.08,
      color = palette.gold,
   }, 0.0, 2.1, wall_z - 0.50)
   add_cylinder(gold, {
      radius = 0.16,
      top_radius = 0.05,
      height = 0.55,
      segments = 10,
      color = palette.gold,
   }, 0.0, 5.98, wall_z - 0.5)
   add_cylinder(gold, {
      radius = 0.10,
      height = 0.20,
      segments = 10,
      color = palette.gold,
   }, 0.0, 6.34, wall_z - 0.5)

   return stone, gold, dark, iron, world
end

-- Phase 9 perimeter chapels: a blind arcade of horseshoe arches with partition
-- walls forming shallow chapel compartments along the perimeter walls.
local function build_perimeter_chapels(config, materials)
   local stone = mesh.builder()
   local world = collision.world()
   local palette = materials.palette
   local recess_color = color.rgb(104, 92, 78)
   local e = config.envelope
   local height = 8.0
   local depth = 3.2
   local bay = 8.0

   -- West and east walls: deep chapel compartments.
   for _, sign in ipairs { -1, 1 } do
      local wall_x = sign < 0 and e.x0 or e.x1
      local inward = -sign * depth
      local front_x = wall_x + inward
      local front_rotation = sign < 0 and math.pi * 0.5 or -math.pi * 0.5
      local partitions = {}
      local z = -52.0
      while z <= 52.0 + 1e-6 do
         partitions[#partitions + 1] = z
         z = z + bay
      end
      for _, zz in ipairs(partitions) do
         add_box(stone, {
            width = depth,
            height = height,
            depth = 0.4,
            color = palette.stone,
         }, wall_x + inward * 0.5, height * 0.5, zz)
         world:add_box {
            x = wall_x + inward * 0.5,
            z = zz,
            width = depth,
            depth = 0.4,
         }
      end
      for i = 1, #partitions - 1 do
         local center = (partitions[i] + partitions[i + 1]) * 0.5
         add(stone, mesh.make_horseshoe_arch {
            radius = (bay - 0.6) * 0.5,
            thickness = 0.30,
            depth = 0.5,
            segments = 12,
            stripe_colors = { palette.brick, palette.cream },
         }, combined(translation(front_x, 4.0, center), rotation_y(front_rotation)))
         add(stone, mesh.make_quad {
            width = bay - 0.8,
            height = height - 1.2,
            color = recess_color,
         }, combined(
            translation(wall_x + inward * 0.97, (height - 1.2) * 0.5, center),
            rotation_y(front_rotation)
         ))
      end
   end

   -- North and south walls: shallow chapel arcade flanking the entrance and
   -- the maqsura, with light partitions.
   for _, side in ipairs {
      { wall_z = e.z0, inward = depth, rotation = 0.0 },
      { wall_z = e.z1, inward = -depth, rotation = math.pi },
   } do
      local front_z = side.wall_z + side.inward
      local boundaries = {}
      for x = 22.0, 54.0, bay do
         boundaries[#boundaries + 1] = x
         boundaries[#boundaries + 1] = -x
      end
      table.sort(boundaries)
      for _, xx in ipairs(boundaries) do
         add_box(stone, {
            width = 0.4,
            height = height,
            depth = depth,
            color = palette.stone,
         }, xx, height * 0.5, side.wall_z + side.inward * 0.5)
         world:add_box {
            x = xx,
            z = side.wall_z + side.inward * 0.5,
            width = 0.4,
            depth = depth,
         }
      end
      for i = 1, #boundaries - 1 do
         if math.abs(boundaries[i]) > 20.0 and math.abs(boundaries[i + 1]) > 20.0 then
            local center = (boundaries[i] + boundaries[i + 1]) * 0.5
            if math.abs(center) > 21.0 then
               add(stone, mesh.make_horseshoe_arch {
                  radius = (bay - 0.6) * 0.5,
                  thickness = 0.30,
                  depth = 0.5,
                  segments = 12,
                  stripe_colors = { palette.brick, palette.cream },
               }, combined(
                  translation(center, 4.0, front_z),
                  rotation_y(side.rotation)
               ))
               add(stone, mesh.make_quad {
                  width = bay - 0.8,
                  height = height - 1.2,
                  color = recess_color,
               }, combined(
                  translation(center, (height - 1.2) * 0.5, side.wall_z + side.inward * 0.97),
                  rotation_y(side.rotation)
               ))
            end
         end
      end
   end

   return stone, world
end

function M.build(config, materials)
   local palette = materials.palette

   local floor_mesh = build_floors(config, palette):build()
   local column_builder, arch_builder, hypostyle_world =
      build_hypostyle(config, palette)
   local ceiling_mesh = build_hypostyle_ceilings(config, materials):build()
   local boundary_stone, boundary_dark, boundary_world = build_boundary(config, materials)
   local cath_stone, cath_glass, cath_gold, cath_iron, cath_brick, cath_world =
      build_cathedral(config, materials)
   local core_stone, core_wood, core_gold, core_iron, core_stained, core_statue,
      core_cloth, core_world = build_christian_core(config, materials)
   local maq_stone, maq_gold, maq_dark, maq_iron, maq_world =
      build_maqsura(config, materials)
   local peri_stone, peri_world = build_perimeter_chapels(config, materials)
   local contents_result = contents.build(config, materials)

   local world = collision.world()
   world:add_all(hypostyle_world.shapes)
   world:add_all(boundary_world.shapes)
   world:add_all(cath_world.shapes)
   world:add_all(core_world.shapes)
   world:add_all(maq_world.shapes)
   world:add_all(peri_world.shapes)
   world:add_all(contents_result.collision.shapes)

   local function classify(x, y, z)
      local region = config.region_at(x, z)
      return region and region.id or nil
   end

   local drawables = {}
   local function emit(name, source, material, options)
      options = options or {}
      local kind = options.kind or "structure"
      if options.global then
         drawables[#drawables + 1] = {
            name = name,
            mesh = source,
            material = material,
            region = "global",
            kind = kind,
         }
         return
      end
      local buckets, order = mesh.partition(source, classify)
      for _, key in ipairs(order) do
         drawables[#drawables + 1] = {
            name = name .. "-" .. key,
            mesh = buckets[key],
            material = material,
            region = key,
            kind = kind,
         }
      end
   end

   -- The envelope shell (floor, ceilings, boundary) stays global so culling far
   -- regions can never open a hole to the background.
   emit("floor", floor_mesh, materials.floor, { global = true })
   emit("ceilings", ceiling_mesh, materials.wood, { global = true })
   emit("boundary", boundary_stone:build(), materials.plaster, { global = true })
   emit("boundary-recess", boundary_dark:build(), materials.dark, { global = true })

   emit("columns", column_builder:build(), materials.column)
   emit("arches", arch_builder:build(), materials.arches)
   emit("cathedral", cath_stone:build(), materials.cathedral)
   emit("cathedral-glass", cath_glass:build(), materials.stained_glass)
   emit("cathedral-gold", cath_gold:build(), materials.gold)
   emit("cathedral-iron", cath_iron:build(), materials.iron)
   emit("cathedral-brick", cath_brick:build(), materials.brick)
   emit("core-stone", core_stone:build(), materials.cathedral)
   emit("core-wood", core_wood:build(), materials.wood)
   emit("core-gold", core_gold:build(), materials.gold)
   emit("core-iron", core_iron:build(), materials.iron)
   emit("core-stained-glass", core_stained:build(), materials.stained_glass)
   emit("core-statue", core_statue:build(), materials.statue)
   emit("core-cloth", core_cloth:build(), materials.cloth)
   emit("maqsura-stone", maq_stone:build(), materials.cathedral)
   emit("maqsura-gold", maq_gold:build(), materials.gold)
   emit("maqsura-dark", maq_dark:build(), materials.dark)
   emit("maqsura-iron", maq_iron:build(), materials.iron)
   emit("perimeter-stone", peri_stone:build(), materials.cathedral)

   for _, drawable in ipairs(contents_result.drawables) do
      emit(drawable.name, drawable.mesh, drawable.material, { kind = "contents" })
   end

   local stats = {
      drawables = #drawables,
      regions = #config.region_list,
      vertices = 0,
      triangles = 0,
      contents_instances = contents_result.stats.instances,
   }
   for _, drawable in ipairs(drawables) do
      stats.vertices = stats.vertices + drawable.mesh.vertex_count
      stats.triangles = stats.triangles + drawable.mesh.index_count / 3
   end

   return {
      drawables = drawables,
      collision = world,
      debug_mesh = world:debug_mesh { y = 0.03, circle_segments = 16 },
      config = config,
      stats = stats,
   }
end

return M
