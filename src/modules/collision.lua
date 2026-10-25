local M = ... or {}

local color = require("color")
local rig = require("rig")

-- Backend-agnostic 2D static collision for ground-constrained walking. Shapes
-- live on the XZ plane; a player capsule reduces to a circle on that plane.
local EPS = 1e-9
local SKIN = 1e-4
local DEFAULT_RADIUS = 0.3

local function number(value, label)
   local resolved = tonumber(value)
   if resolved == nil then
      rig.raise("collision %s must be a number", label)
   end
   return resolved
end

local function positive(value, label)
   local resolved = number(value, label)
   if resolved <= 0.0 then
      rig.raise("collision %s must be positive", label)
   end
   return resolved
end

local function non_negative(value, label)
   local resolved = number(value, label)
   if resolved < 0.0 then
      rig.raise("collision %s must not be negative", label)
   end
   return resolved
end

local function vec2(value, label)
   if type(value) ~= "table" then
      rig.raise("collision %s must be a two-number table", label)
   end
   local x = tonumber(value[1]) or tonumber(value.x)
   local z = tonumber(value[2]) or tonumber(value.z)
   if x == nil or z == nil then
      rig.raise("collision %s must have x/z or [1]/[2] components", label)
   end
   return x, z
end

local function normalize(x, z, fallback_x, fallback_z)
   local length = math.sqrt(x * x + z * z)
   if length < EPS then
      return fallback_x or 1.0, fallback_z or 0.0
   end
   local inv = 1.0 / length
   return x * inv, z * inv
end

local function point_box(x, z, min_x, min_z, max_x, max_z)
   return x >= min_x and x <= max_x and z >= min_z and z <= max_z
end

local function point_segment_distance(x, z, x1, z1, x2, z2)
   local ex = x2 - x1
   local ez = z2 - z1
   local length_sq = ex * ex + ez * ez
   local t = 0.0
   if length_sq > EPS then
      t = ((x - x1) * ex + (z - z1) * ez) / length_sq
      if t < 0.0 then
         t = 0.0
      elseif t > 1.0 then
         t = 1.0
      end
   end
   local cx = x1 + ex * t
   local cz = z1 + ez * t
   local dx = x - cx
   local dz = z - cz
   return math.sqrt(dx * dx + dz * dz), cx, cz
end

local function point_in_polygon(x, z, points)
   local inside = false
   local count = #points
   local j = count
   for i = 1, count do
      local xi, zi = points[i][1], points[i][2]
      local xj, zj = points[j][1], points[j][2]
      if ((zi > z) ~= (zj > z))
         and (x < (xj - xi) * (z - zi) / (zj - zi) + xi) then
         inside = not inside
      end
      j = i
   end
   return inside
end

function M.circle(options)
   options = options or {}
   local x = number(options.x, "circle x")
   local z = number(options.z, "circle z")
   local radius = positive(options.radius, "circle radius")
   return {
      type = "circle",
      x = x,
      z = z,
      radius = radius,
      min_x = x - radius,
      max_x = x + radius,
      min_z = z - radius,
      max_z = z + radius,
   }
end

function M.box(options)
   options = options or {}
   local x = number(options.x, "box x")
   local z = number(options.z, "box z")
   local width = positive(options.width, "box width")
   local depth = positive(options.depth, "box depth")
   local angle = tonumber(options.angle) or 0.0
   local cos_angle = math.cos(angle)
   local sin_angle = math.sin(angle)
   local half_width = width * 0.5
   local half_depth = depth * 0.5

   local min_x, max_x = math.huge, -math.huge
   local min_z, max_z = math.huge, -math.huge
   for _, corner in ipairs {
      { -half_width, -half_depth },
      { half_width, -half_depth },
      { half_width, half_depth },
      { -half_width, half_depth },
   } do
      local wx = x + corner[1] * cos_angle + corner[2] * sin_angle
      local wz = z - corner[1] * sin_angle + corner[2] * cos_angle
      min_x = math.min(min_x, wx)
      max_x = math.max(max_x, wx)
      min_z = math.min(min_z, wz)
      max_z = math.max(max_z, wz)
   end

   return {
      type = "box",
      x = x,
      z = z,
      half_width = half_width,
      half_depth = half_depth,
      cos_angle = cos_angle,
      sin_angle = sin_angle,
      min_x = min_x,
      max_x = max_x,
      min_z = min_z,
      max_z = max_z,
   }
end

function M.segment(options)
   options = options or {}
   local x1, z1 = vec2(options.from, "segment from")
   local x2, z2 = vec2(options.to, "segment to")
   local radius
   if options.thickness ~= nil then
      radius = non_negative(options.thickness, "segment thickness") * 0.5
   else
      radius = non_negative(options.radius or 0.0, "segment radius")
   end
   if math.abs(x1 - x2) < EPS and math.abs(z1 - z2) < EPS then
      rig.raise("collision segment endpoints must differ")
   end

   return {
      type = "segment",
      x1 = x1,
      z1 = z1,
      x2 = x2,
      z2 = z2,
      radius = radius,
      min_x = math.min(x1, x2) - radius,
      max_x = math.max(x1, x2) + radius,
      min_z = math.min(z1, z2) - radius,
      max_z = math.max(z1, z2) + radius,
   }
end

function M.polygon(options)
   options = options or {}
   local source = options.points
   if type(source) ~= "table" or #source < 3 then
      rig.raise("collision polygon needs at least three points")
   end

   local points = {}
   local min_x, max_x = math.huge, -math.huge
   local min_z, max_z = math.huge, -math.huge
   for i = 1, #source do
      local x, z = vec2(source[i], "polygon point")
      points[i] = { x, z }
      min_x = math.min(min_x, x)
      max_x = math.max(max_x, x)
      min_z = math.min(min_z, z)
      max_z = math.max(max_z, z)
   end

   local area = 0.0
   for i = 1, #points do
      local next_index = i % #points + 1
      area = area
         + points[i][1] * points[next_index][2]
         - points[next_index][1] * points[i][2]
   end
   if math.abs(area) < EPS then
      rig.raise("collision polygon points must enclose a non-zero area")
   end

   local ccw = area > 0.0
   local edges = {}
   for i = 1, #points do
      local a = points[i]
      local b = points[i % #points + 1]
      local ex = b[1] - a[1]
      local ez = b[2] - a[2]
      local length = math.sqrt(ex * ex + ez * ez)
      if length < EPS then
         rig.raise("collision polygon edges must have non-zero length")
      end
      local nx, nz
      if ccw then
         nx, nz = ez / length, -ex / length
      else
         nx, nz = -ez / length, ex / length
      end
      edges[i] = {
         x1 = a[1],
         z1 = a[2],
         x2 = b[1],
         z2 = b[2],
         nx = nx,
         nz = nz,
      }
   end

   return {
      type = "polygon",
      points = points,
      edges = edges,
      ccw = ccw,
      min_x = min_x,
      max_x = max_x,
      min_z = min_z,
      max_z = max_z,
   }
end

local function circle_distance(shape, x, z, radius)
   local dx = x - shape.x
   local dz = z - shape.z
   local nx, nz = normalize(dx, dz)
   return math.sqrt(dx * dx + dz * dz) - shape.radius - radius, nx, nz
end

local function segment_distance(shape, x, z, radius)
   local distance, cx, cz = point_segment_distance(
      x,
      z,
      shape.x1,
      shape.z1,
      shape.x2,
      shape.z2
   )
   local dx = x - cx
   local dz = z - cz
   local nx, nz
   if distance < EPS then
      local ex = shape.x2 - shape.x1
      local ez = shape.z2 - shape.z1
      nx, nz = normalize(-ez, ex)
   else
      nx, nz = normalize(dx, dz)
   end
   return distance - shape.radius - radius, nx, nz
end

local function box_distance(shape, x, z, radius)
   local dx = x - shape.x
   local dz = z - shape.z
   local local_x = dx * shape.cos_angle - dz * shape.sin_angle
   local local_z = dx * shape.sin_angle + dz * shape.cos_angle
   local closest_x = math.max(-shape.half_width, math.min(shape.half_width, local_x))
   local closest_z = math.max(-shape.half_depth, math.min(shape.half_depth, local_z))
   local outside_x = local_x - closest_x
   local outside_z = local_z - closest_z
   local outside_sq = outside_x * outside_x + outside_z * outside_z

   if outside_sq > EPS then
      local distance = math.sqrt(outside_sq)
      local local_nx = outside_x / distance
      local local_nz = outside_z / distance
      local nx = local_nx * shape.cos_angle + local_nz * shape.sin_angle
      local nz = -local_nx * shape.sin_angle + local_nz * shape.cos_angle
      return distance - radius, nx, nz
   end

   local face_x = shape.half_width - math.abs(local_x)
   local face_z = shape.half_depth - math.abs(local_z)
   local local_nx, local_nz
   local face_distance
   if face_x < face_z then
      face_distance = face_x
      local_nx = local_x >= 0.0 and 1.0 or -1.0
      local_nz = 0.0
   else
      face_distance = face_z
      local_nx = 0.0
      local_nz = local_z >= 0.0 and 1.0 or -1.0
   end
   local nx = local_nx * shape.cos_angle + local_nz * shape.sin_angle
   local nz = -local_nx * shape.sin_angle + local_nz * shape.cos_angle
   return -(face_distance + radius), nx, nz
end

local function polygon_distance(shape, x, z, radius)
   local nearest_distance = math.huge
   local nearest_edge = nil
   local closest_x, closest_z = nil, nil
   local closest_distance = math.huge

   for i = 1, #shape.edges do
      local edge = shape.edges[i]
      local distance, cx, cz = point_segment_distance(
         x,
         z,
         edge.x1,
         edge.z1,
         edge.x2,
         edge.z2
      )
      if distance < nearest_distance then
         nearest_distance = distance
         nearest_edge = edge
      end
      if distance < closest_distance then
         closest_distance = distance
         closest_x, closest_z = cx, cz
      end
   end

   if point_in_polygon(x, z, shape.points) then
      return -(nearest_distance + radius), nearest_edge.nx, nearest_edge.nz
   end

   local dx = x - closest_x
   local dz = z - closest_z
   if closest_distance < EPS then
      return -radius, nearest_edge.nx, nearest_edge.nz
   end
   local nx, nz = normalize(dx, dz)
   return closest_distance - radius, nx, nz
end

local function shape_distance(shape, x, z, radius)
   if shape.type == "circle" then
      return circle_distance(shape, x, z, radius)
   elseif shape.type == "box" then
      return box_distance(shape, x, z, radius)
   elseif shape.type == "segment" then
      return segment_distance(shape, x, z, radius)
   elseif shape.type == "polygon" then
      return polygon_distance(shape, x, z, radius)
   end
   rig.raise("unknown collision shape type '%s'", tostring(shape.type))
end

local World = {}
M.World = World

function World:init()
   self.shapes = {}
end

function M.world()
   return setmetatable({ shapes = {} }, { __index = World })
end

function World:clear()
   self.shapes = {}
   return self
end

function World:count()
   return #self.shapes
end

function World:add(shape)
   if type(shape) ~= "table" or shape.type == nil then
      rig.raise("collision.world:add expects a collision shape")
   end
   self.shapes[#self.shapes + 1] = shape
   return shape
end

function World:add_circle(options)
   return self:add(M.circle(options))
end

function World:add_box(options)
   return self:add(M.box(options))
end

function World:add_segment(options)
   return self:add(M.segment(options))
end

function World:add_polygon(options)
   return self:add(M.polygon(options))
end

function World:add_all(shapes)
   for i = 1, #(shapes or {}) do
      self:add(shapes[i])
   end
   return self
end

function World:_deepest_penetration(x, z, radius)
   local best_distance = nil
   local best_nx, best_nz = 1.0, 0.0
   local best_shape = nil

   for i = 1, #self.shapes do
      local shape = self.shapes[i]
      if point_box(
         x,
         z,
         shape.min_x - radius,
         shape.min_z - radius,
         shape.max_x + radius,
         shape.max_z + radius
      ) then
         local distance, nx, nz = shape_distance(shape, x, z, radius)
         if distance < -SKIN
            and (best_distance == nil or distance < best_distance) then
            best_distance = distance
            best_nx = nx
            best_nz = nz
            best_shape = shape
         end
      end
   end

   return best_distance, best_nx, best_nz, best_shape
end

-- Pushes a circle out of any overlapping static shapes. Returns the new center
-- and whether anything was resolved.
function World:resolve_circle(x, z, radius, iterations)
   x = number(x, "circle x")
   z = number(z, "circle z")
   radius = radius == nil and DEFAULT_RADIUS or non_negative(radius, "circle radius")
   iterations = math.floor(iterations or 4)
   local resolved = false

   for _ = 1, iterations do
      local distance, nx, nz = self:_deepest_penetration(x, z, radius)
      if distance == nil then
         break
      end
      local push = -distance + SKIN
      x = x + nx * push
      z = z + nz * push
      resolved = true
   end

   return x, z, resolved
end

-- Moves a circle through static geometry with adaptive substepping and
-- depenetration. The substep size is tied to the player radius, so a fast move
-- cannot tunnel through a wall. Returns the resulting center and whether any
-- contact was resolved.
function World:sweep_circle(x, z, dx, dz, radius, options)
   options = options or {}
   x = number(x, "circle x")
   z = number(z, "circle z")
   dx = number(dx, "delta x")
   dz = number(dz, "delta z")
   radius = radius == nil and DEFAULT_RADIUS or non_negative(radius, "circle radius")

   if #self.shapes == 0 then
      return x + dx, z + dz, false
   end

   local length = math.sqrt(dx * dx + dz * dz)
   local max_step = tonumber(options.max_step)
      or math.max(radius * 0.5, 0.05)
   if max_step <= 0.0 then
      rig.raise("collision max_step must be positive")
   end
   local steps = math.max(1, math.ceil(length / max_step))
   local step_x = dx / steps
   local step_z = dz / steps
   local resolved_any = false

   for _ = 1, steps do
      local nx, nz, resolved = self:resolve_circle(
         x + step_x,
         z + step_z,
         radius,
         options.iterations or 4
      )
      x, z = nx, nz
      resolved_any = resolved_any or resolved
   end

   local final_x, final_z, final_resolved = self:resolve_circle(
      x,
      z,
      radius,
      options.final_iterations or 8
   )
   return final_x, final_z, resolved_any or final_resolved
end

local function position_components(position)
   if type(position) ~= "table" then
      rig.raise("collision move expects a position table")
   end
   local x = tonumber(position[1]) or tonumber(position.x)
   local z = tonumber(position[3]) or tonumber(position.z)
   if x == nil or z == nil then
      rig.raise("collision move expects position[1]/position[3] or position.x/position.z")
   end
   return x, z, position[1] ~= nil or position.x == nil
end

function World:move(position, dx, dz, options)
   options = options or {}
   local x, z, array_style = position_components(position)
   local radius = tonumber(options.radius)
      or (options.capsule and tonumber(options.capsule.radius))
      or DEFAULT_RADIUS
   local nx, nz, resolved = self:sweep_circle(x, z, dx, dz, radius, options)

   if array_style then
      position[1] = nx
      position[3] = nz
   else
      position.x = nx
      position.z = nz
   end
   return position, resolved
end

-- A capsule is vertical in this ground-constrained walk layer, so its XZ
-- projection is the same circle. `options.capsule.radius` is used when present.
function World:move_capsule(position, dx, dz, options)
   return self:move(position, dx, dz, options)
end

local function add_debug_segment(points, x1, z1, x2, z2)
   points[#points + 1] = { x1, 0.0, z1 }
   points[#points + 1] = { x2, 0.0, z2 }
end

-- Returns a `position_color_f32` line mesh for the static shapes, or nil when
-- the world is empty. Debug lines sit on the XZ plane at `y` (default 0.02).
function World:debug_mesh(options)
   options = options or {}
   local points = {}
   local y = tonumber(options.y) or 0.02
   local circle_segments = math.max(4, math.floor(tonumber(options.circle_segments) or 20))

   local function add_point(x, z)
      points[#points + 1] = { x, y, z }
   end

   local function add_edge(x1, z1, x2, z2)
      add_point(x1, z1)
      add_point(x2, z2)
   end

   for i = 1, #self.shapes do
      local shape = self.shapes[i]
      if shape.type == "circle" then
         local previous_x = shape.x + shape.radius
         local previous_z = shape.z
         for segment = 1, circle_segments do
            local angle = (segment / circle_segments) * math.pi * 2.0
            local x = shape.x + math.cos(angle) * shape.radius
            local z = shape.z + math.sin(angle) * shape.radius
            add_edge(previous_x, previous_z, x, z)
            previous_x, previous_z = x, z
         end
      elseif shape.type == "box" then
         local corners = {}
         for corner_index = 1, 4 do
            local lx = ((corner_index == 2 or corner_index == 3)
               and shape.half_width
               or -shape.half_width)
            local lz = (corner_index >= 3 and shape.half_depth or -shape.half_depth)
            corners[corner_index] = {
               shape.x + lx * shape.cos_angle + lz * shape.sin_angle,
               shape.z - lx * shape.sin_angle + lz * shape.cos_angle,
            }
         end
         for corner_index = 1, 4 do
            local next_index = corner_index % 4 + 1
            add_edge(
               corners[corner_index][1],
               corners[corner_index][2],
               corners[next_index][1],
               corners[next_index][2]
            )
         end
      elseif shape.type == "segment" then
         add_edge(shape.x1, shape.z1, shape.x2, shape.z2)
      elseif shape.type == "polygon" then
         for edge_index = 1, #shape.edges do
            local edge = shape.edges[edge_index]
            add_edge(edge.x1, edge.z1, edge.x2, edge.z2)
         end
      end
   end

   if #points == 0 then
      return nil
   end

   return require("mesh").make_line_segments {
      points = points,
      color = options.color or color.rgb(255, 214, 80),
   }
end

return M
