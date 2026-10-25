local M = {}

-- Metre-scale interior for the present-day Córdoba Mosque-Cathedral. Phase 9
-- expands the earlier bounded MVP to the full published prayer-hall envelope:
-- 125 m east-west (X) by 118 m north-south (Z), centred on the origin.
M.envelope = {
   x0 = -62.5,
   x1 = 62.5,
   z0 = -59.0,
   z1 = 59.0,
}

M.cathedral = {
   x0 = -28.0,
   x1 = 28.0,
   z0 = -32.0,
   z1 = 14.0,
   wall_height = 18.0,
   wall_thickness = 0.8,
   portal_width = 8.0,
   portal_height = 12.0,
   vault_spring = 14.0,
   vault_radius = 12.0,
   vault_length = 46.0,
   vault_thickness = 0.5,
}

-- Maqsura and mihrab occupy the south (qibla) end of the central vessel.
M.maqsura = {
   x0 = -18.0,
   x1 = 18.0,
   z0 = 38.0,
   z1 = 59.0,
   dome_radius = 7.0,
   dome_height = 4.2,
   bay_span = 12.0,
}

M.hypostyle = {
   lower_spring = 4.2,
   upper_spring = 6.8,
   ceiling_side = 10.2,
   ceiling_center = 12.2,
   lower_thickness = 0.34,
   upper_thickness = 0.30,
   arch_depth = 0.52,
   column = {
      radius = 0.28,
      base_radius = 0.42,
      base_height = 0.30,
      shaft_height = 3.40,
      capital_radius = 0.42,
      capital_height = 0.35,
      abacus_height = 0.15,
      abacus_width = 0.95,
      segments = 18,
      collision_radius = 0.44,
   },
}

-- 19 aisles across the 125 m width: a 10 m central nave between the X = ±5 m
-- columns, then nine side aisles per side at ~6.39 m. N-S bays are 6 m from
-- Z = -54 to +54, giving the published 118 m interior depth.
M.grid = {
   central_half_width = 5.0,
   side_spacing = (62.5 - 5.0) / 9.0,
   side_lines = 9,
   z0 = -54.0,
   z1 = 54.0,
   z_spacing = 6.0,
   xs = {},
   zs = {},
}

do
   local grid = M.grid
   for k = 0, grid.side_lines - 1 do
      local x = grid.central_half_width + k * grid.side_spacing
      grid.xs[#grid.xs + 1] = x
      grid.xs[#grid.xs + 1] = -x
   end
   table.sort(grid.xs)
   local z = grid.z0
   while z <= grid.z1 + 1e-6 do
      grid.zs[#grid.zs + 1] = z
      z = z + grid.z_spacing
   end
end

M.start = {
   position = { 0.0, 0.0, -51.0 },
   yaw = 0.0,
   pitch = 0.02,
   eye_height = 1.65,
   radius = 0.30,
   speed = 10.0,
}

-- Ordered from specific to broad. Cathedral subzones are tested before the
-- generic cathedral aisle zone. `lod` is the quality/detail contract; the
-- runtime uses it for culling, reflection range, and content prioritisation.
M.lod = {
   hero = { detail = 1.0, reflection = true, local_lights = 4 },
   detail = { detail = 0.75, reflection = true, local_lights = 2 },
   shell = { detail = 0.35, reflection = false, local_lights = 0 },
}

M.zones = {
   {
      id = "maqsura",
      name = "Maqsura / mihrab",
      x0 = -18,
      x1 = 18,
      z0 = 38,
      z1 = 59,
      lod = "hero",
   },
   {
      id = "villaviciosa",
      name = "Villaviciosa chapel",
      x0 = -28,
      x1 = -12,
      z0 = -24,
      z1 = -12,
      lod = "hero",
   },
   {
      id = "capilla_mayor",
      name = "Capilla Mayor",
      x0 = -12,
      x1 = 12,
      z0 = 4,
      z1 = 14,
      lod = "hero",
   },
   {
      id = "crossing",
      name = "Crossing / transept",
      x0 = -28,
      x1 = 28,
      z0 = -4,
      z1 = 4,
      lod = "hero",
   },
   {
      id = "cathedral_nave",
      name = "Cathedral nave",
      x0 = -12,
      x1 = 12,
      z0 = -32,
      z1 = -4,
      lod = "detail",
   },
   {
      id = "cathedral_aisles",
      name = "Cathedral aisles",
      x0 = -28,
      x1 = 28,
      z0 = -32,
      z1 = 14,
      lod = "detail",
   },
   {
      id = "north_threshold",
      name = "North threshold",
      x0 = -62.5,
      x1 = 62.5,
      z0 = -59,
      z1 = -45,
      lod = "shell",
   },
   {
      id = "north_hypostyle",
      name = "North hypostyle",
      x0 = -62.5,
      x1 = 62.5,
      z0 = -45,
      z1 = -32,
      lod = "detail",
   },
   {
      id = "west_hypostyle",
      name = "West hypostyle",
      x0 = -62.5,
      x1 = -32,
      z0 = -32,
      z1 = 38,
      lod = "detail",
   },
   {
      id = "east_hypostyle",
      name = "East / Al-Mansur field",
      x0 = 32,
      x1 = 62.5,
      z0 = -32,
      z1 = 38,
      lod = "detail",
   },
   {
      id = "south_hypostyle",
      name = "South hypostyle",
      x0 = -62.5,
      x1 = 62.5,
      z0 = 14,
      z1 = 59,
      lod = "detail",
   },
}

function M.inside_cathedral(x, z)
   local c = M.cathedral
   return x > c.x0 and x < c.x1 and z > c.z0 and z < c.z1
end

function M.inside_cathedral_inclusive(x, z)
   local c = M.cathedral
   return x >= c.x0 and x <= c.x1 and z >= c.z0 and z <= c.z1
end

function M.has_column(x, z)
   return not M.inside_cathedral_inclusive(x, z)
end

function M.zone_info_at(x, z)
   for i = 1, #M.zones do
      local zone = M.zones[i]
      if x >= zone.x0 and x <= zone.x1 and z >= zone.z0 and z <= zone.z1 then
         return zone
      end
   end
   return nil
end

function M.zone_at(x, z)
   local zone = M.zone_info_at(x, z)
   return zone and zone.name or "Perimeter aisle"
end

-- ---------------------------------------------------------------------------
-- Culling regions
--
-- The scene is partitioned into a 4 x 4 spatial grid. Each drawable is tagged
-- with the region id containing its triangle centroids so the runtime can skip
-- whole regions that are outside the camera's bubble or fully behind it.
-- ---------------------------------------------------------------------------

local region_x_cuts = { M.envelope.x0, -31.0, 0.0, 31.0, M.envelope.x1 }
local region_z_cuts = { M.envelope.z0, -30.0, 0.0, 30.0, M.envelope.z1 }

M.regions = {}
M.region_list = {}

for i = 1, #region_x_cuts - 1 do
   for j = 1, #region_z_cuts - 1 do
      local x0, x1 = region_x_cuts[i], region_x_cuts[i + 1]
      local z0, z1 = region_z_cuts[j], region_z_cuts[j + 1]
      local region = {
         id = ("r%d%d"):format(i, j),
         x0 = x0,
         x1 = x1,
         z0 = z0,
         z1 = z1,
         cx = (x0 + x1) * 0.5,
         cz = (z0 + z1) * 0.5,
      }
      local half_width = (x1 - x0) * 0.5
      local half_depth = (z1 - z0) * 0.5
      region.radius = math.sqrt(half_width * half_width + half_depth * half_depth)
      local central_x = i == 2 or i == 3
      local central_z = j == 2 or j == 3
      if central_x and central_z then
         region.lod = "hero"
      elseif central_x or central_z then
         region.lod = "detail"
      else
         region.lod = "shell"
      end
      M.regions[region.id] = region
      M.region_list[#M.region_list + 1] = region
   end
end

-- Region ids covering the detailed MVP route (central north-south band).
M.mvp_region_ids = {
   r21 = true,
   r31 = true,
   r22 = true,
   r32 = true,
   r23 = true,
   r33 = true,
}

function M.region_at(x, z)
   local i = 1
   while i < #region_x_cuts - 1 and x >= region_x_cuts[i + 1] do
      i = i + 1
   end
   local j = 1
   while j < #region_z_cuts - 1 and z >= region_z_cuts[j + 1] do
      j = j + 1
   end
   return M.regions[("r%d%d"):format(i, j)]
end

-- Returns a set of visible region ids and the count. `forward` is the camera's
-- normalized XZ heading. A region is visible when its angular extent overlaps the
-- forward view cone (so long open sightlines down a nave are never culled) and it
-- is within `options.max_distance` if set. The camera's own region is always
-- included.
--
-- This is deliberately a cone test rather than a distance bubble: the interior is
-- a large open hypostyle, and a radius bubble would punch a void at the far end of
-- a long view.
function M.visible_regions(eye, forward, options)
   options = options or {}
   local half_angle = options.half_angle or math.rad(55.0)
   local max_distance = options.max_distance
   local ex, ez = eye[1], eye[3]
   local fx, fz = forward[1], forward[3]
   if fx == 0.0 and fz == 0.0 then
      fx, fz = 0.0, 1.0
   end
   local cos_half = math.cos(half_angle)

   local visible = {}
   local count = 0
   for _, region in ipairs(M.region_list) do
      local dx = region.cx - ex
      local dz = region.cz - ez
      local dist = math.sqrt(dx * dx + dz * dz)
      local include
      if dist <= region.radius then
         include = true
      else
         local dot = (dx * fx + dz * fz) / dist
         local angular_radius = math.asin(math.min(1.0, region.radius / dist))
         local limit = math.min(math.pi, half_angle + angular_radius)
         include = dot >= math.cos(limit)
      end
      if include and max_distance ~= nil then
         include = dist - region.radius <= max_distance
      end
      if include then
         if not visible[region.id] then
            visible[region.id] = true
            count = count + 1
         end
      end
   end

   local current = M.region_at(ex, ez)
   if current ~= nil and not visible[current.id] then
      visible[current.id] = true
      count = count + 1
   end
   return visible, count
end

return M
