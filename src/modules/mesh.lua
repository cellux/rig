local M = ... or {}
local ffi = require("ffi")
local color = require("color")
local mathx = require("mathx")
local rig = require("rig")
local runtime = require("runtime")

local DEFAULT_FACE_COLORS = {
   color.rgbf(1, 0, 0),
   color.rgbf(0, 1, 0),
   color.rgbf(0, 0, 1),
   color.rgbf(1, 1, 0),
   color.rgbf(1, 0, 1),
   color.rgbf(0, 1, 1),
}

local function resolve_face_colors(options)
   if options.colors == nil or options.colors == "face" then
      return DEFAULT_FACE_COLORS
   end

   if type(options.colors) ~= "table" then
      rig.raise("mesh.make_cube colors must be 'face' or a table of Color values")
   end
   if #options.colors ~= 6 then
      rig.raise("mesh.make_cube colors table must contain 6 face colors")
   end

   for i = 1, 6 do
      local face_color = options.colors[i]
      if not color.is(face_color) then
         rig.raise("mesh.make_cube face colors must be Color values")
      end
   end
   return options.colors
end

local FACE_CORNERS = {
   { -- front
      { -1, -1, -1 },
      {  1, -1, -1 },
      {  1,  1, -1 },
      { -1,  1, -1 },
   },
   { -- back
      { -1, -1,  1 },
      {  1, -1,  1 },
      {  1,  1,  1 },
      { -1,  1,  1 },
   },
   { -- left
      { -1, -1, -1 },
      { -1, -1,  1 },
      { -1,  1,  1 },
      { -1,  1, -1 },
   },
   { -- right
      {  1, -1, -1 },
      {  1, -1,  1 },
      {  1,  1,  1 },
      {  1,  1, -1 },
   },
   { -- top
      { -1,  1, -1 },
      { -1,  1,  1 },
      {  1,  1,  1 },
      {  1,  1, -1 },
   },
   { -- bottom
      { -1, -1, -1 },
      { -1, -1,  1 },
      {  1, -1,  1 },
      {  1, -1, -1 },
   },
}

local function unpack_color(value, label)
   if value == nil then
      return 1.0, 1.0, 1.0
   end
   if not color.is(value) then
      rig.raise(label .. " must be a Color value")
   end
   return value:to_rgbf()
end

-- Packs `{ x, y, z, r, g, b }` vertices into the shared `position_color_f32`
-- layout used by every generator.
local function pack_position_color(vertices, topology)
   local values = {}
   for i = 1, #vertices do
      local vertex = vertices[i]
      values[#values + 1] = vertex[1]
      values[#values + 1] = vertex[2]
      values[#values + 1] = vertex[3]
      values[#values + 1] = vertex[4]
      values[#values + 1] = vertex[5]
      values[#values + 1] = vertex[6]
   end

   local vertex_array = ffi.new("float[?]", #values)
   for i = 1, #values do
      vertex_array[i - 1] = values[i]
   end

   return {
      layout = "position_color_f32",
      topology = topology or "triangles",
      vertex_stride = 24,
      vertex_count = #vertices,
      attribute_offsets = {
         position = 0,
         color = 12,
      },
      vertex_blob = ffi.string(
         ffi.cast("const char *", vertex_array),
         ffi.sizeof(vertex_array)
      ),
   }
end

-- Packs `{ x, y, z, r, g, b, u, v }` vertices into the shared
-- `position_color_uv_f32` layout used by textured meshes.
local function pack_position_color_uv(vertices, topology)
   local values = {}
   for i = 1, #vertices do
      local vertex = vertices[i]
      for j = 1, 8 do
         values[#values + 1] = vertex[j]
      end
   end

   local vertex_array = ffi.new("float[?]", #values)
   for i = 1, #values do
      vertex_array[i - 1] = values[i]
   end

   return {
      layout = "position_color_uv_f32",
      topology = topology or "triangles",
      vertex_stride = 32,
      vertex_count = #vertices,
      attribute_offsets = {
         position = 0,
         color = 12,
         uv = 24,
      },
      vertex_blob = ffi.string(
         ffi.cast("const char *", vertex_array),
         ffi.sizeof(vertex_array)
      ),
   }
end

-- Explicit vertex layouts. Attribute locations are stable across layouts, so a
-- shader can bind one role (for example normal at location 3) even when another
-- layout omits it. Offsets are byte offsets into the interleaved float vertex.
local LAYOUTS = {
   position_color_f32 = {
      stride = 24,
      order = { "position", "color" },
      attributes = {
         position = { offset = 0, size = 3, location = 0, format = "float3" },
         color = { offset = 12, size = 3, location = 1, format = "float3" },
      },
   },
   position_color_uv_f32 = {
      stride = 32,
      order = { "position", "color", "uv" },
      attributes = {
         position = { offset = 0, size = 3, location = 0, format = "float3" },
         color = { offset = 12, size = 3, location = 1, format = "float3" },
         uv = { offset = 24, size = 2, location = 2, format = "float2" },
      },
   },
   position_normal_color_uv_f32 = {
      stride = 44,
      order = { "position", "normal", "color", "uv" },
      attributes = {
         position = { offset = 0, size = 3, location = 0, format = "float3" },
         normal = { offset = 12, size = 3, location = 3, format = "float3" },
         color = { offset = 24, size = 3, location = 1, format = "float3" },
         uv = { offset = 36, size = 2, location = 2, format = "float2" },
      },
   },
   position_normal_tangent_color_uv_f32 = {
      stride = 60,
      order = { "position", "normal", "tangent", "color", "uv" },
      attributes = {
         position = { offset = 0, size = 3, location = 0, format = "float3" },
         normal = { offset = 12, size = 3, location = 3, format = "float3" },
         tangent = { offset = 24, size = 4, location = 4, format = "float4" },
         color = { offset = 40, size = 3, location = 1, format = "float3" },
         uv = { offset = 52, size = 2, location = 2, format = "float2" },
      },
   },
}

M.layouts = LAYOUTS

local ATTRIBUTE_DEFAULTS = {
   position = { 0.0, 0.0, 0.0 },
   normal = { 0.0, 1.0, 0.0 },
   tangent = { 1.0, 0.0, 0.0, 1.0 },
   color = { 1.0, 1.0, 1.0 },
   uv = { 0.0, 0.0 },
}

-- Returns the public layout definition for `name`, raising for unknown layouts.
function M.layout(name)
   local definition = LAYOUTS[name]
   if definition == nil then
      rig.raise("unknown mesh layout '%s'", tostring(name))
   end
   return definition
end

local function pack_mesh(vertices, layout_name, topology, indices)
   local definition = M.layout(layout_name)
   local values = {}

   for i = 1, #vertices do
      local vertex = vertices[i]
      if type(vertex) ~= "table" then
         rig.raise("mesh vertex %d must be a table", i)
      end

      for _, role in ipairs(definition.order) do
         local attribute = definition.attributes[role]
         local source = vertex[role] or ATTRIBUTE_DEFAULTS[role]
         for component = 1, attribute.size do
            local value = source[component]
            if value == nil then
               value = ATTRIBUTE_DEFAULTS[role][component] or 0.0
            end
            values[#values + 1] = value
         end
      end
   end

   local vertex_array = ffi.new("float[?]", #values)
   for i = 1, #values do
      vertex_array[i - 1] = values[i]
   end

   local result = {
      layout = layout_name,
      topology = topology or "triangles",
      vertex_stride = definition.stride,
      vertex_count = #vertices,
      attribute_offsets = {},
      vertex_blob = ffi.string(
         ffi.cast("const char *", vertex_array),
         ffi.sizeof(vertex_array)
      ),
   }
   for role, attribute in pairs(definition.attributes) do
      result.attribute_offsets[role] = attribute.offset
   end

   if indices ~= nil and #indices > 0 then
      local index_array = ffi.new("uint32_t[?]", #indices)
      for i = 1, #indices do
         -- Generator index lists are Lua 1-based; GPU/GL index buffers are
         -- zero-based.
         index_array[i - 1] = indices[i] - 1
      end
      result.index_blob = ffi.string(
         ffi.cast("const char *", index_array),
         ffi.sizeof(index_array)
      )
      result.index_count = #indices
      result.index_type = "uint32"
      result.index_stride = 4
   end

   return result
end

local function resolve_components(value, label)
   if value == nil then
      return { 1.0, 1.0, 1.0 }
   end
   if not color.is(value) then
      rig.raise(label .. " must be a Color value")
   end
   local r, g, b = value:to_rgbf()
   return { r, g, b }
end

local function resolve_uv_scale(value, label)
   if value == nil then
      return 1.0, 1.0
   end
   if type(value) == "number" then
      return value, value
   end
   if type(value) ~= "table" then
      rig.raise(label .. " must be a number or a two-number table")
   end
   return tonumber(value[1]) or 1.0, tonumber(value[2]) or 1.0
end

-- Appends four vertices and two triangles. Corners must be in the winding order
-- that faces the supplied normal.
local function append_quad(vertices, indices, v0, v1, v2, v3)
   local base = #vertices + 1
   vertices[#vertices + 1] = v0
   vertices[#vertices + 1] = v1
   vertices[#vertices + 1] = v2
   vertices[#vertices + 1] = v3
   indices[#indices + 1] = base
   indices[#indices + 1] = base + 1
   indices[#indices + 1] = base + 2
   indices[#indices + 1] = base
   indices[#indices + 1] = base + 2
   indices[#indices + 1] = base + 3
end

local function make_vertex(position, normal, uv, vertex_color)
   return {
      position = position,
      normal = normal,
      uv = uv or { 0.0, 0.0 },
      color = vertex_color,
   }
end

local function normalize3(x, y, z)
   local length = math.sqrt(x * x + y * y + z * z)
   if length < 1e-12 then
      return 0.0, 1.0, 0.0
   end
   local inv = 1.0 / length
   return x * inv, y * inv, z * inv
end

local function face_normal(a, b, c)
   local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
   local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
   return normalize3(uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
end

local function generate_normals(vertices, indices)
   local sums = {}
   for i = 1, #indices, 3 do
      local i0, i1, i2 = indices[i], indices[i + 1], indices[i + 2]
      local v0, v1, v2 = vertices[i0], vertices[i1], vertices[i2]
      local nx, ny, nz = face_normal(v0.position, v1.position, v2.position)
      for _, index in ipairs { i0, i1, i2 } do
         local sum = sums[index]
         if sum == nil then
            sum = { 0.0, 0.0, 0.0 }
            sums[index] = sum
         end
         sum[1] = sum[1] + nx
         sum[2] = sum[2] + ny
         sum[3] = sum[3] + nz
      end
   end

   for i = 1, #vertices do
      local vertex = vertices[i]
      if vertex.normal == nil then
         local sum = sums[i]
         if sum ~= nil then
            local nx, ny, nz = normalize3(sum[1], sum[2], sum[3])
            vertex.normal = { nx, ny, nz }
         else
            vertex.normal = { 0.0, 1.0, 0.0 }
         end
      end
   end
end

local function generate_tangents(vertices, indices)
   local sums = {}

   for i = 1, #indices, 3 do
      local i0, i1, i2 = indices[i], indices[i + 1], indices[i + 2]
      local v0, v1, v2 = vertices[i0], vertices[i1], vertices[i2]
      local p0, p1, p2 = v0.position, v1.position, v2.position
      local uv0, uv1, uv2 = v0.uv or { 0, 0 }, v1.uv or { 0, 0 }, v2.uv or { 0, 0 }

      local e1x, e1y, e1z = p1[1] - p0[1], p1[2] - p0[2], p1[3] - p0[3]
      local e2x, e2y, e2z = p2[1] - p0[1], p2[2] - p0[2], p2[3] - p0[3]
      local du1, dv1 = uv1[1] - uv0[1], uv1[2] - uv0[2]
      local du2, dv2 = uv2[1] - uv0[1], uv2[2] - uv0[2]
      local determinant = du1 * dv2 - du2 * dv1
      if math.abs(determinant) > 1e-12 then
         local inv = 1.0 / determinant
         local tx = (e1x * dv2 - e2x * dv1) * inv
         local ty = (e1y * dv2 - e2y * dv1) * inv
         local tz = (e1z * dv2 - e2z * dv1) * inv
         for _, index in ipairs { i0, i1, i2 } do
            local sum = sums[index]
            if sum == nil then
               sum = { 0.0, 0.0, 0.0 }
               sums[index] = sum
            end
            sum[1] = sum[1] + tx
            sum[2] = sum[2] + ty
            sum[3] = sum[3] + tz
         end
      end
   end

   for i = 1, #vertices do
      local vertex = vertices[i]
      if vertex.tangent == nil then
         local sum = sums[i] or { 1.0, 0.0, 0.0 }
         local normal = vertex.normal or { 0.0, 1.0, 0.0 }
         local dot = sum[1] * normal[1] + sum[2] * normal[2] + sum[3] * normal[3]
         local tx = sum[1] - normal[1] * dot
         local ty = sum[2] - normal[2] * dot
         local tz = sum[3] - normal[3] * dot
         local nx, ny, nz = normalize3(tx, ty, tz)
         vertex.tangent = { nx, ny, nz, 1.0 }
      end
   end
end

-- Decodes a mesh into role-based vertex tables and zero-based indices.
local function decode_mesh(source)
   if type(source) ~= "table" then
      rig.raise("mesh builder add expects a mesh table")
   end

   local definition = M.layout(source.layout)
   if source.topology ~= nil and source.topology ~= "triangles" then
      rig.raise("mesh builder only accepts triangle meshes, got '%s'", source.topology)
   end
   if type(source.vertex_blob) ~= "string" then
      rig.raise("mesh builder source has no vertex_blob")
   end

   local expected_bytes = source.vertex_count * source.vertex_stride
   if #source.vertex_blob < expected_bytes then
      rig.raise("mesh builder source vertex_blob is shorter than its vertex count")
   end

   local pointer = ffi.cast(
      "const float *",
      ffi.cast("const char *", source.vertex_blob)
   )
   local float_stride = source.vertex_stride / 4
   local vertices = {}

   for i = 0, source.vertex_count - 1 do
      local base = i * float_stride
      local vertex = {}
      for role, attribute in pairs(definition.attributes) do
         local components = {}
         local first = base + attribute.offset / 4
         for component = 1, attribute.size do
            components[component] = pointer[first + component - 1]
         end
         vertex[role] = components
      end
      vertices[i + 1] = vertex
   end

   local indices = {}
   if source.index_blob ~= nil then
      local index_type = source.index_type or "uint32"
      local count = source.index_count or 0
      if index_type == "uint32" then
         local data = ffi.cast(
            "const uint32_t *",
            ffi.cast("const char *", source.index_blob)
         )
         for i = 0, count - 1 do
            indices[i + 1] = data[i]
         end
      elseif index_type == "uint16" then
         local data = ffi.cast(
            "const uint16_t *",
            ffi.cast("const char *", source.index_blob)
         )
         for i = 0, count - 1 do
            indices[i + 1] = data[i]
         end
      else
         rig.raise("mesh builder does not support index type '%s'", index_type)
      end
   else
      for i = 1, source.vertex_count do
         indices[i] = i - 1
      end
   end

   return vertices, indices, definition
end

-- A column-major affine matrix transform and its normal matrix. Non-uniform
-- scales are supported for normals through the inverse-transpose 3x3.
local function transform_point(matrix, position)
   local x, y, z = position[1], position[2], position[3]
   return {
      matrix[0] * x + matrix[4] * y + matrix[8] * z + matrix[12],
      matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13],
      matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14],
   }
end

local function transform_direction(matrix, direction)
   local x, y, z = direction[1], direction[2], direction[3]
   return {
      matrix[0] * x + matrix[4] * y + matrix[8] * z,
      matrix[1] * x + matrix[5] * y + matrix[9] * z,
      matrix[2] * x + matrix[6] * y + matrix[10] * z,
   }
end

local function determinant3(m)
   return m[0] * (m[5] * m[10] - m[9] * m[6])
      - m[4] * (m[1] * m[10] - m[9] * m[2])
      + m[8] * (m[1] * m[6] - m[5] * m[2])
end

-- Returns the row-major inverse-transpose 3x3 as { i00, i01, i02, i10, ... }.
local function normal_matrix(matrix)
   local a00, a01, a02 = matrix[0], matrix[4], matrix[8]
   local a10, a11, a12 = matrix[1], matrix[5], matrix[9]
   local a20, a21, a22 = matrix[2], matrix[6], matrix[10]
   local c00 = a11 * a22 - a12 * a21
   local c01 = a12 * a20 - a10 * a22
   local c02 = a10 * a21 - a11 * a20
   local c10 = a02 * a21 - a01 * a22
   local c11 = a00 * a22 - a02 * a20
   local c12 = a01 * a20 - a00 * a21
   local c20 = a01 * a12 - a02 * a11
   local c21 = a02 * a10 - a00 * a12
   local c22 = a00 * a11 - a01 * a10
   local determinant = a00 * c00 + a01 * c01 + a02 * c02
   if math.abs(determinant) < 1e-12 then
      rig.raise("mesh builder transform must not be singular")
   end
   local inv = 1.0 / determinant
   -- inverse = adjugate / determinant; transpose it here so callers can use a
   -- direct row dot product.
   return {
      c00 * inv, c10 * inv, c20 * inv,
      c01 * inv, c11 * inv, c21 * inv,
      c02 * inv, c12 * inv, c22 * inv,
   }
end

local function transform_normal(inverse_transpose, normal)
   local nx, ny, nz = normal[1], normal[2], normal[3]
   local x = inverse_transpose[1] * nx + inverse_transpose[4] * ny + inverse_transpose[7] * nz
   local y = inverse_transpose[2] * nx + inverse_transpose[5] * ny + inverse_transpose[8] * nz
   local z = inverse_transpose[3] * nx + inverse_transpose[6] * ny + inverse_transpose[9] * nz
   local rx, ry, rz = normalize3(x, y, z)
   return { rx, ry, rz }
end

function M.make_cube(options)
   options = options or {}
   if type(options) ~= "table" then
      error("mesh.make_cube expects a table if options are provided")
   end

   local size = tonumber(options.size) or 2.0
   if size <= 0.0 then
      rig.raise("mesh.make_cube size must be positive")
   end

   local half_extent = size * 0.5
   local colors = resolve_face_colors(options)
   local vertices = {}

   for face_index = 1, 6 do
      local corners = FACE_CORNERS[face_index]
      local face_color = colors[face_index]
      local r, g, b = face_color:to_rgbf()
      local uvs = { { 0.0, 0.0 }, { 1.0, 0.0 }, { 1.0, 1.0 }, { 0.0, 1.0 } }

      local function push(corner_index, uv_index)
         local corner = corners[corner_index]
         local uv = uvs[uv_index]
         vertices[#vertices + 1] = {
            corner[1] * half_extent,
            corner[2] * half_extent,
            corner[3] * half_extent,
            r,
            g,
            b,
            uv[1],
            uv[2],
         }
      end

      push(1, 1)
      push(2, 2)
      push(3, 3)
      push(1, 1)
      push(3, 3)
      push(4, 4)
   end

   return pack_position_color_uv(vertices, "triangles")
end

-- A centered rectangle in the XY plane facing +Z.
-- options: size? | width?/height?, color?
function M.make_quad(options)
   options = options or {}
   local size = tonumber(options.size) or 1.0
   local width = tonumber(options.width) or size
   local height = tonumber(options.height) or size
   if width <= 0.0 or height <= 0.0 then
      rig.raise("mesh.make_quad size must be positive")
   end

   local half_width = width * 0.5
   local half_height = height * 0.5
   local r, g, b = unpack_color(options.color, "mesh.make_quad color")

   local corners = {
      { -half_width, -half_height, 0.0, 0.0, 1.0 },
      { half_width, -half_height, 0.0, 1.0, 1.0 },
      { half_width, half_height, 0.0, 1.0, 0.0 },
      { -half_width, half_height, 0.0, 0.0, 0.0 },
   }

   local vertices = {}
   local function push(corner)
      vertices[#vertices + 1] = {
         corner[1],
         corner[2],
         corner[3],
         r,
         g,
         b,
         corner[4],
         corner[5],
      }
   end
   push(corners[1])
   push(corners[2])
   push(corners[3])
   push(corners[1])
   push(corners[3])
   push(corners[4])

   return pack_position_color_uv(vertices, "triangles")
end

-- A quad spanning clip space (`[-1, 1]` on X/Y) with UVs whose `(0, 0)` corner
-- is the top-left. Draw it with an identity transform as a fullscreen pass; the
-- scene's `draw_fullscreen` does exactly that.
function M.make_fullscreen_quad()
   return M.make_quad { size = 2.0 }
end

-- A centered equilateral triangle in the XY plane.
-- options: size? (circumscribed diameter), color?
function M.make_triangle(options)
   options = options or {}
   local size = tonumber(options.size) or 1.0
   if size <= 0.0 then
      rig.raise("mesh.make_triangle size must be positive")
   end

   local radius = size * 0.5
   local r, g, b = unpack_color(options.color, "mesh.make_triangle color")
   local vertices = {}
   for i = 0, 2 do
      local angle = math.pi * 0.5 + i * (2.0 * math.pi / 3.0)
      vertices[#vertices + 1] = {
         radius * math.cos(angle),
         radius * math.sin(angle),
         0.0,
         r,
         g,
         b,
      }
   end

   return pack_position_color(vertices, "triangles")
end

-- A line segment. Without `from`/`to` it is centered on the origin along +X.
-- options: length? | from?, to?, color?
function M.make_line(options)
   options = options or {}
   local r, g, b = unpack_color(options.color, "mesh.make_line color")

   local from = options.from
   local to = options.to
   if from == nil and to == nil then
      local length = tonumber(options.length) or 1.0
      local half = length * 0.5
      from = { -half, 0.0, 0.0 }
      to = { half, 0.0, 0.0 }
   elseif from == nil or to == nil then
      rig.raise("mesh.make_line requires both from and to, or neither")
   end

   local vertices = {
      { from[1], from[2], from[3], r, g, b },
      { to[1], to[2], to[3], r, g, b },
   }
   return pack_position_color(vertices, "lines")
end

-- A polyline through `points` (an array of `{ x, y, z }`).
-- options: points (required), color?
function M.make_lines(options)
   options = options or {}
   local points = options.points
   if type(points) ~= "table" or #points < 2 then
      rig.raise("mesh.make_lines requires points with at least two entries")
   end

   local r, g, b = unpack_color(options.color, "mesh.make_lines color")
   local vertices = {}
   for i = 1, #points - 1 do
      local first = points[i]
      local second = points[i + 1]
      vertices[#vertices + 1] = { first[1], first[2], first[3], r, g, b }
      vertices[#vertices + 1] = { second[1], second[2], second[3], r, g, b }
   end
   return pack_position_color(vertices, "lines")
end

-- Disjoint line segments. `points` is a flat array of `{ x, y, z }` entries in
-- pairs; unlike `make_lines`, consecutive pairs are not connected to each other.
function M.make_line_segments(options)
   options = options or {}
   local points = options.points
   if type(points) ~= "table" or #points < 2 or #points % 2 ~= 0 then
      rig.raise("mesh.make_line_segments requires an even number of points")
   end

   local r, g, b = unpack_color(options.color, "mesh.make_line_segments color")
   local vertices = {}
   for i = 1, #points, 2 do
      local first = points[i]
      local second = points[i + 1]
      vertices[#vertices + 1] = { first[1], first[2], first[3], r, g, b }
      vertices[#vertices + 1] = { second[1], second[2], second[3], r, g, b }
   end
   return pack_position_color(vertices, "lines")
end

-- A ground-plane grid on XZ, useful for architectural scenes.
-- options: size?, divisions?, color?
function M.make_grid(options)
   options = options or {}
   local size = tonumber(options.size) or 10.0
   local divisions = math.floor(tonumber(options.divisions) or 10)
   if size <= 0.0 then
      rig.raise("mesh.make_grid size must be positive")
   end
   if divisions < 1 then
      rig.raise("mesh.make_grid divisions must be at least 1")
   end

   local r, g, b = unpack_color(options.color, "mesh.make_grid color")
   local half = size * 0.5
   local step = size / divisions
   local vertices = {}

   local function line(x1, z1, x2, z2)
      vertices[#vertices + 1] = { x1, 0.0, z1, r, g, b }
      vertices[#vertices + 1] = { x2, 0.0, z2, r, g, b }
   end

   for i = 0, divisions do
      local offset = -half + i * step
      line(offset, -half, offset, half)
      line(-half, offset, half, offset)
   end

   return pack_position_color(vertices, "lines")
end

-- A box centered on `center` with per-face normals and UVs. The six face
-- winding orders match the legacy cube so existing render behaviour is unchanged.
function M.make_box(options)
   options = options or {}
   local size = tonumber(options.size)
   local width = tonumber(options.width) or size or 2.0
   local height = tonumber(options.height) or size or 2.0
   local depth = tonumber(options.depth) or size or 2.0
   if width <= 0.0 or height <= 0.0 or depth <= 0.0 then
      rig.raise("mesh.make_box dimensions must be positive")
   end

   local center = options.center or { 0.0, 0.0, 0.0 }
   if type(center) ~= "table" then
      rig.raise("mesh.make_box center must be a three-number table")
   end

   local face_colors
   if options.colors ~= nil then
      if type(options.colors) ~= "table" or #options.colors ~= 6 then
         rig.raise("mesh.make_box colors must contain six Color values")
      end
      face_colors = {}
      for i = 1, 6 do
         face_colors[i] = resolve_components(
            options.colors[i],
            "mesh.make_box face color"
         )
      end
   else
      local single = resolve_components(options.color, "mesh.make_box color")
      face_colors = { single, single, single, single, single, single }
   end

   local scale_u, scale_v = resolve_uv_scale(options.uv_scale, "mesh.make_box uv_scale")
   local half_width = width * 0.5
   local half_height = height * 0.5
   local half_depth = depth * 0.5
   local face_normals = {
      { 0.0, 0.0, -1.0 },
      { 0.0, 0.0, 1.0 },
      { -1.0, 0.0, 0.0 },
      { 1.0, 0.0, 0.0 },
      { 0.0, 1.0, 0.0 },
      { 0.0, -1.0, 0.0 },
   }
   local face_uvs = {
      { { 0.0, 0.0 }, { 1.0, 0.0 }, { 1.0, 1.0 }, { 0.0, 1.0 } },
      { { 0.0, 0.0 }, { 1.0, 0.0 }, { 1.0, 1.0 }, { 0.0, 1.0 } },
      { { 0.0, 0.0 }, { 1.0, 0.0 }, { 1.0, 1.0 }, { 0.0, 1.0 } },
      { { 0.0, 0.0 }, { 1.0, 0.0 }, { 1.0, 1.0 }, { 0.0, 1.0 } },
      { { 0.0, 0.0 }, { 1.0, 0.0 }, { 1.0, 1.0 }, { 0.0, 1.0 } },
      { { 0.0, 0.0 }, { 1.0, 0.0 }, { 1.0, 1.0 }, { 0.0, 1.0 } },
   }

   local vertices, indices = {}, {}
   for face_index = 1, 6 do
      local corners = FACE_CORNERS[face_index]
      local normal = face_normals[face_index]
      local face_color = face_colors[face_index]
      local face_uv = face_uvs[face_index]
      local quad = {}
      for i = 1, 4 do
         local corner = corners[i]
         local uv = face_uv[i]
         quad[i] = make_vertex(
            {
               center[1] + corner[1] * half_width,
               center[2] + corner[2] * half_height,
               center[3] + corner[3] * half_depth,
            },
            normal,
            { uv[1] * scale_u, uv[2] * scale_v },
            face_color
         )
      end
      append_quad(vertices, indices, quad[1], quad[2], quad[3], quad[4])
   end

   return pack_mesh(vertices, "position_normal_color_uv_f32", "triangles", indices)
end

-- A cylinder or truncated cone centered on `center`, with its axis along Y.
-- `radius` is the bottom radius; `top_radius` defaults to `radius`.
function M.make_cylinder(options)
   options = options or {}
   local radius = tonumber(options.radius) or 0.5
   local top_radius = tonumber(options.top_radius) or radius
   local height = tonumber(options.height) or 1.0
   local segments = math.floor(tonumber(options.segments) or 24)
   local caps = options.caps ~= false
   if radius <= 0.0 or top_radius < 0.0 or height <= 0.0 then
      rig.raise("mesh.make_cylinder radius and height must be positive")
   end
   if top_radius == 0.0 and radius == 0.0 then
      rig.raise("mesh.make_cylinder must have a positive radius")
   end
   if segments < 3 then
      rig.raise("mesh.make_cylinder segments must be at least 3")
   end

   local center = options.center or { 0.0, 0.0, 0.0 }
   local color_components = resolve_components(options.color, "mesh.make_cylinder color")
   local scale_u, scale_v = resolve_uv_scale(
      options.uv_scale,
      "mesh.make_cylinder uv_scale"
   )
   local half_height = height * 0.5
   local bottom_y = center[2] - half_height
   local top_y = center[2] + half_height
   local vertices, indices = {}, {}

   for i = 0, segments do
      local angle = (i / segments) * math.pi * 2.0
      local cos_angle = math.cos(angle)
      local sin_angle = math.sin(angle)
      local nx, ny, nz = normalize3(
         cos_angle * height,
         radius - top_radius,
         sin_angle * height
      )
      local u = (i / segments) * scale_u
      vertices[#vertices + 1] = make_vertex(
         { center[1] + radius * cos_angle, bottom_y, center[3] + radius * sin_angle },
         { nx, ny, nz },
         { u, 0.0 },
         color_components
      )
      vertices[#vertices + 1] = make_vertex(
         { center[1] + top_radius * cos_angle, top_y, center[3] + top_radius * sin_angle },
         { nx, ny, nz },
         { u, scale_v },
         color_components
      )
   end

   for i = 0, segments - 1 do
      local bottom = i * 2 + 1
      local top = bottom + 1
      local next_bottom = bottom + 2
      local next_top = bottom + 3
      indices[#indices + 1] = bottom
      indices[#indices + 1] = next_bottom
      indices[#indices + 1] = next_top
      indices[#indices + 1] = bottom
      indices[#indices + 1] = next_top
      indices[#indices + 1] = top
   end

   local function add_cap(y, cap_radius, normal, flip)
      if cap_radius <= 0.0 then
         return
      end
      local cap_center = #vertices + 1
      vertices[#vertices + 1] = make_vertex(
         { center[1], y, center[3] },
         normal,
         { 0.5 * scale_u, 0.5 * scale_v },
         color_components
      )
      local first = #vertices + 1
      for i = 0, segments - 1 do
         local angle = (i / segments) * math.pi * 2.0
         local cos_angle = math.cos(angle)
         local sin_angle = math.sin(angle)
         vertices[#vertices + 1] = make_vertex(
            {
               center[1] + cap_radius * cos_angle,
               y,
               center[3] + cap_radius * sin_angle,
            },
            normal,
            {
               (0.5 + 0.5 * cos_angle) * scale_u,
               (0.5 + 0.5 * sin_angle) * scale_v,
            },
            color_components
         )
      end
      for i = 0, segments - 1 do
         local current = first + i
         local next_index = first + ((i + 1) % segments)
         if flip then
            indices[#indices + 1] = cap_center
            indices[#indices + 1] = next_index
            indices[#indices + 1] = current
         else
            indices[#indices + 1] = cap_center
            indices[#indices + 1] = current
            indices[#indices + 1] = next_index
         end
      end
   end

   if caps then
      add_cap(bottom_y, radius, { 0.0, -1.0, 0.0 }, false)
      add_cap(top_y, top_radius, { 0.0, 1.0, 0.0 }, true)
   end

   return pack_mesh(vertices, "position_normal_color_uv_f32", "triangles", indices)
end

-- A flared capital with an optional square abacus, built upward from y = 0.
function M.make_capital(options)
   options = options or {}
   local radius = tonumber(options.radius) or 0.35
   local top_radius = tonumber(options.top_radius) or radius * 1.45
   local height = tonumber(options.height) or 0.4
   local abacus_height = tonumber(options.abacus_height) or 0.0
   local abacus_width = tonumber(options.abacus_width) or top_radius * 2.25
   local segments = math.floor(tonumber(options.segments) or 16)
   if radius <= 0.0 or top_radius <= 0.0 or height <= 0.0 then
      rig.raise("mesh.make_capital radii and height must be positive")
   end
   if abacus_height < 0.0 or abacus_width <= 0.0 then
      rig.raise("mesh.make_capital abacus dimensions must be positive")
   end

   local builder = M.builder { normals = true }
   local frustum = M.make_cylinder {
      radius = radius,
      top_radius = top_radius,
      height = height,
      segments = segments,
      caps = false,
      color = options.color or options.shaft_color,
   }
   local transform = mathx.mat4()
   mathx.mat4_translation(transform, 0.0, height * 0.5, 0.0)
   builder:add(frustum, { transform = transform })

   if abacus_height > 0.0 then
      local abacus = M.make_box {
         width = abacus_width,
         height = abacus_height,
         depth = abacus_width,
         color = options.abacus_color or options.color or options.shaft_color,
      }
      local abacus_transform = mathx.mat4()
      mathx.mat4_translation(
         abacus_transform,
         0.0,
         height + abacus_height * 0.5,
         0.0
      )
      builder:add(abacus, { transform = abacus_transform })
   end

   return builder:build()
end

-- A column assembled from an optional base, a shaft, and an optional capital.
-- `height` is the shaft height; the returned mesh starts at y = 0.
function M.make_column(options)
   options = options or {}
   local radius = tonumber(options.radius) or 0.35
   local height = tonumber(options.height) or 4.0
   local base_height = tonumber(options.base_height) or 0.0
   local base_radius = tonumber(options.base_radius) or radius * 1.35
   local capital_height = tonumber(options.capital_height) or 0.0
   local segments = math.floor(tonumber(options.segments) or 20)
   if radius <= 0.0 or height <= 0.0 then
      rig.raise("mesh.make_column radius and height must be positive")
   end
   if base_height < 0.0 or capital_height < 0.0 then
      rig.raise("mesh.make_column base_height and capital_height must not be negative")
   end

   local builder = M.builder { normals = true }
   local transform = mathx.mat4()

   if base_height > 0.0 then
      local base = M.make_cylinder {
         radius = base_radius,
         height = base_height,
         segments = segments,
         color = options.base_color or options.color,
      }
      mathx.mat4_translation(transform, 0.0, base_height * 0.5, 0.0)
      builder:add(base, { transform = transform })
   end

   local shaft = M.make_cylinder {
      radius = radius,
      height = height,
      segments = segments,
      color = options.color,
   }
   mathx.mat4_translation(transform, 0.0, base_height + height * 0.5, 0.0)
   builder:add(shaft, { transform = transform })

   if capital_height > 0.0 then
      local capital = M.make_capital {
         radius = radius,
         top_radius = options.capital_radius or radius * 1.45,
         height = capital_height,
         abacus_height = options.abacus_height or 0.0,
         abacus_width = options.abacus_width,
         segments = segments,
         color = options.capital_color or options.color,
         abacus_color = options.abacus_color,
      }
      mathx.mat4_translation(transform, 0.0, base_height + height, 0.0)
      builder:add(capital, { transform = transform })
   end

   return builder:build()
end

-- A curved arch band in the XY plane, extruded along Z. Angles are radians and
-- use the standard +X = 0 convention. A horseshoe opening is normally described
-- with `start_angle = -0.35, end_angle = 3.49` (below the spring line on both
-- sides); a round arch uses `0` to `pi`.
function M.make_arch_ring(options)
   options = options or {}
   local radius = tonumber(options.radius) or 1.0
   local thickness = tonumber(options.thickness) or 0.18
   local depth = tonumber(options.depth) or 0.35
   local segments = math.floor(tonumber(options.segments) or 24)
   local start_angle = tonumber(options.start_angle) or 0.0
   local end_angle = tonumber(options.end_angle) or math.pi
   if radius <= 0.0 or thickness <= 0.0 or depth <= 0.0 then
      rig.raise("mesh.make_arch_ring radius, thickness, and depth must be positive")
   end
   if thickness >= radius then
      rig.raise("mesh.make_arch_ring thickness must be smaller than radius")
   end
   if segments < 1 or end_angle <= start_angle then
      rig.raise("mesh.make_arch_ring needs a positive angle span and at least one segment")
   end

   local inner_radius = radius - thickness
   local half_depth = depth * 0.5
   local base_color = options.color
   local stripe_colors = options.stripe_colors
   local stripe_size = math.max(1, math.floor(tonumber(options.stripe_size) or 1))
   if stripe_colors ~= nil then
      if type(stripe_colors) ~= "table" or #stripe_colors == 0 then
         rig.raise("mesh.make_arch_ring stripe_colors must be a non-empty table")
      end
      for i = 1, #stripe_colors do
         if not color.is(stripe_colors[i]) then
            rig.raise("mesh.make_arch_ring stripe_colors must contain Color values")
         end
      end
   end

   local vertices, indices = {}, {}
   local span = end_angle - start_angle

   for i = 0, segments - 1 do
      local a0 = start_angle + span * (i / segments)
      local a1 = start_angle + span * ((i + 1) / segments)
      local mid = (a0 + a1) * 0.5
      local c0, s0 = math.cos(a0), math.sin(a0)
      local c1, s1 = math.cos(a1), math.sin(a1)
      local cm, sm = math.cos(mid), math.sin(mid)

      local segment_color
      if stripe_colors ~= nil then
         local stripe_index = math.floor(i / stripe_size) % #stripe_colors + 1
         segment_color = resolve_components(
            stripe_colors[stripe_index],
            "mesh.make_arch_ring stripe color"
         )
      else
         segment_color = resolve_components(base_color, "mesh.make_arch_ring color")
      end

      local of0 = make_vertex(
         { radius * c0, radius * s0, half_depth },
         { 0.0, 0.0, 1.0 },
         { 0.0, 0.0 },
         segment_color
      )
      local of1 = make_vertex(
         { radius * c1, radius * s1, half_depth },
         { 0.0, 0.0, 1.0 },
         { 1.0, 0.0 },
         segment_color
      )
      local if0 = make_vertex(
         { inner_radius * c0, inner_radius * s0, half_depth },
         { 0.0, 0.0, 1.0 },
         { 0.0, 1.0 },
         segment_color
      )
      local if1 = make_vertex(
         { inner_radius * c1, inner_radius * s1, half_depth },
         { 0.0, 0.0, 1.0 },
         { 1.0, 1.0 },
         segment_color
      )
      local ob0 = make_vertex(
         { radius * c0, radius * s0, -half_depth },
         { 0.0, 0.0, -1.0 },
         { 0.0, 0.0 },
         segment_color
      )
      local ob1 = make_vertex(
         { radius * c1, radius * s1, -half_depth },
         { 0.0, 0.0, -1.0 },
         { 1.0, 0.0 },
         segment_color
      )
      local ib0 = make_vertex(
         { inner_radius * c0, inner_radius * s0, -half_depth },
         { 0.0, 0.0, -1.0 },
         { 0.0, 1.0 },
         segment_color
      )
      local ib1 = make_vertex(
         { inner_radius * c1, inner_radius * s1, -half_depth },
         { 0.0, 0.0, -1.0 },
         { 1.0, 1.0 },
         segment_color
      )

      append_quad(vertices, indices, of0, if0, if1, of1)
      append_quad(vertices, indices, ob0, ob1, ib1, ib0)

      local outer0 = make_vertex(
         { radius * c0, radius * s0, half_depth },
         { cm, sm, 0.0 },
         { 0.0, 0.0 },
         segment_color
      )
      local outer1 = make_vertex(
         { radius * c1, radius * s1, half_depth },
         { cm, sm, 0.0 },
         { 1.0, 0.0 },
         segment_color
      )
      local outer_back0 = make_vertex(
         { radius * c0, radius * s0, -half_depth },
         { cm, sm, 0.0 },
         { 0.0, 1.0 },
         segment_color
      )
      local outer_back1 = make_vertex(
         { radius * c1, radius * s1, -half_depth },
         { cm, sm, 0.0 },
         { 1.0, 1.0 },
         segment_color
      )
      append_quad(vertices, indices, outer0, outer1, outer_back1, outer_back0)

      local inner0 = make_vertex(
         { inner_radius * c0, inner_radius * s0, half_depth },
         { -cm, -sm, 0.0 },
         { 0.0, 0.0 },
         segment_color
      )
      local inner1 = make_vertex(
         { inner_radius * c1, inner_radius * s1, half_depth },
         { -cm, -sm, 0.0 },
         { 1.0, 0.0 },
         segment_color
      )
      local inner_back0 = make_vertex(
         { inner_radius * c0, inner_radius * s0, -half_depth },
         { -cm, -sm, 0.0 },
         { 0.0, 1.0 },
         segment_color
      )
      local inner_back1 = make_vertex(
         { inner_radius * c1, inner_radius * s1, -half_depth },
         { -cm, -sm, 0.0 },
         { 1.0, 1.0 },
         segment_color
      )
      append_quad(vertices, indices, inner0, inner_back0, inner_back1, inner1)

      local start_normal = { -s0, c0, 0.0 }
      local end_normal = { s1, -c1, 0.0 }
      local of0_cap = make_vertex(
         { radius * c0, radius * s0, half_depth },
         start_normal,
         { 0.0, 0.0 },
         segment_color
      )
      local ob0_cap = make_vertex(
         { radius * c0, radius * s0, -half_depth },
         start_normal,
         { 1.0, 0.0 },
         segment_color
      )
      local ib0_cap = make_vertex(
         { inner_radius * c0, inner_radius * s0, -half_depth },
         start_normal,
         { 1.0, 1.0 },
         segment_color
      )
      local if0_cap = make_vertex(
         { inner_radius * c0, inner_radius * s0, half_depth },
         start_normal,
         { 0.0, 1.0 },
         segment_color
      )
      append_quad(vertices, indices, of0_cap, ob0_cap, ib0_cap, if0_cap)

      local of1_cap = make_vertex(
         { radius * c1, radius * s1, half_depth },
         end_normal,
         { 0.0, 0.0 },
         segment_color
      )
      local if1_cap = make_vertex(
         { inner_radius * c1, inner_radius * s1, half_depth },
         end_normal,
         { 0.0, 1.0 },
         segment_color
      )
      local ib1_cap = make_vertex(
         { inner_radius * c1, inner_radius * s1, -half_depth },
         end_normal,
         { 1.0, 1.0 },
         segment_color
      )
      local ob1_cap = make_vertex(
         { radius * c1, radius * s1, -half_depth },
         end_normal,
         { 1.0, 0.0 },
         segment_color
      )
      append_quad(vertices, indices, of1_cap, if1_cap, ib1_cap, ob1_cap)
   end

   return pack_mesh(vertices, "position_normal_color_uv_f32", "triangles", indices)
end

-- A two-centred pointed (Gothic) arch ring in the XY plane, extruded along Z.
-- The span is the clear opening width; the radius must be at least half the span.
-- A larger radius gives a taller, more sharply pointed arch.
function M.make_pointed_arch(options)
   options = options or {}
   local span = tonumber(options.span) or tonumber(options.width) or 4.0
   local radius = tonumber(options.radius) or span * 0.62
   local thickness = tonumber(options.thickness) or 0.3
   local depth = tonumber(options.depth) or 0.5
   local segments = math.floor(tonumber(options.segments) or 16)
   if span <= 0.0 or radius <= 0.0 then
      rig.raise("mesh.make_pointed_arch span and radius must be positive")
   end
   if radius < span * 0.5 then
      rig.raise("mesh.make_pointed_arch radius must be at least half the span")
   end
   if thickness <= 0.0 or thickness >= radius then
      rig.raise("mesh.make_pointed_arch thickness must be positive and smaller than radius")
   end
   if depth <= 0.0 then
      rig.raise("mesh.make_pointed_arch depth must be positive")
   end
   if segments < 1 then
      rig.raise("mesh.make_pointed_arch segments must be at least 1")
   end

   local half_span = span * 0.5
   local offset = radius - half_span
   if offset <= 0.0 then
      return M.make_round_arch(options)
   end
   local apex_angle = math.acos(offset / radius)

   local ring_options = {
      radius = radius,
      thickness = thickness,
      depth = depth,
      segments = math.max(1, math.ceil(segments * apex_angle / math.pi)),
      color = options.color,
      stripe_colors = options.stripe_colors,
      stripe_size = options.stripe_size,
   }
   local left = M.make_arch_ring {
      radius = ring_options.radius,
      thickness = ring_options.thickness,
      depth = ring_options.depth,
      segments = ring_options.segments,
      start_angle = math.pi - apex_angle,
      end_angle = math.pi,
      color = ring_options.color,
      stripe_colors = ring_options.stripe_colors,
      stripe_size = ring_options.stripe_size,
   }
   local right = M.make_arch_ring {
      radius = ring_options.radius,
      thickness = ring_options.thickness,
      depth = ring_options.depth,
      segments = ring_options.segments,
      start_angle = 0.0,
      end_angle = apex_angle,
      color = ring_options.color,
      stripe_colors = ring_options.stripe_colors,
      stripe_size = ring_options.stripe_size,
   }

   local builder = M.builder { normals = true }
   local left_transform = mathx.mat4_translation(mathx.mat4(), offset, 0.0, 0.0)
   local right_transform = mathx.mat4_translation(mathx.mat4(), -offset, 0.0, 0.0)
   builder:add(left, { transform = left_transform })
   builder:add(right, { transform = right_transform })
   return builder:build()
end

function M.make_round_arch(options)
   options = options or {}
   local copy = {}
   for key, value in pairs(options) do
      copy[key] = value
   end
   copy.start_angle = copy.start_angle or 0.0
   copy.end_angle = copy.end_angle or math.pi
   return M.make_arch_ring(copy)
end

function M.make_horseshoe_arch(options)
   options = options or {}
   local copy = {}
   for key, value in pairs(options) do
      copy[key] = value
   end
   copy.start_angle = copy.start_angle or math.rad(-20.0)
   copy.end_angle = copy.end_angle or math.rad(200.0)
   return M.make_arch_ring(copy)
end

function M.make_voussoir_band(options)
   options = options or {}
   local copy = {}
   for key, value in pairs(options) do
      copy[key] = value
   end
   copy.stripe_colors = copy.stripe_colors or {
      color.rgb(150, 48, 38),
      color.rgb(226, 207, 174),
   }
   return M.make_arch_ring(copy)
end

-- A flat ironwork grille/reja panel in the XY plane, from y = 0 to `height`,
-- centered on X and extruded through `depth` on Z. It is an outer frame plus a
-- regular field of vertical bars and a small number of horizontal rails. This is
-- the reusable primitive behind Córdoba's chapel screens; it returns a merged
-- indexed `position_normal_color_uv_f32` mesh.
function M.make_grille(options)
   options = options or {}
   local width = tonumber(options.width) or 4.0
   local height = tonumber(options.height) or 3.0
   local depth = tonumber(options.depth) or 0.08
   local frame_size = tonumber(options.frame_size) or 0.09
   local bar_size = tonumber(options.bar_size) or 0.035
   local spacing = tonumber(options.spacing) or 0.16
   local rails = options.rails
   if rails == nil then
      rails = 2
   else
      rails = math.floor(tonumber(rails) or 0)
   end
   if width <= 0.0 or height <= 0.0 or depth <= 0.0 then
      rig.raise("mesh.make_grille dimensions must be positive")
   end
   if frame_size <= 0.0 or bar_size <= 0.0 or spacing <= 0.0 then
      rig.raise("mesh.make_grille frame, bar, and spacing sizes must be positive")
   end
   if frame_size * 2.0 >= width or frame_size * 2.0 >= height then
      rig.raise("mesh.make_grille frame must be smaller than the panel")
   end

   local frame_color = options.frame_color or options.color
   local bar_color = options.bar_color or options.color
   local builder = M.builder()

   local function box(box_width, box_height, box_depth, x, y, tint)
      builder:add(M.make_box {
         width = box_width,
         height = box_height,
         depth = box_depth,
         color = tint,
      }, { transform = mathx.mat4_translation(mathx.mat4(), x, y, 0.0) })
   end

   -- Outer frame: two stiles and two rails overlapping at the corners.
   box(frame_size, height, depth, -width * 0.5 + frame_size * 0.5, height * 0.5, frame_color)
   box(frame_size, height, depth, width * 0.5 - frame_size * 0.5, height * 0.5, frame_color)
   box(width - frame_size * 2.0, frame_size, depth, 0.0, frame_size * 0.5, frame_color)
   box(
      width - frame_size * 2.0,
      frame_size,
      depth,
      0.0,
      height - frame_size * 0.5,
      frame_color
   )

   local inner_width = width - frame_size * 2.0
   local inner_height = height - frame_size * 2.0
   local bar_count = math.max(1, math.floor(inner_width / spacing + 0.5))
   local bar_step = inner_width / bar_count
   for i = 1, bar_count do
      local x = -inner_width * 0.5 + (i - 0.5) * bar_step
      box(bar_size, inner_height, depth * 0.8, x, height * 0.5, bar_color)
   end

   for r = 1, rails do
      local y = frame_size + inner_height * (r / (rails + 1))
      box(inner_width, bar_size, depth * 0.9, 0.0, y, bar_color)
   end

   return builder:build()
end

-- A balustrade/railing running along X, centered on the origin from y = 0 to
-- approximately `height`. It is a base rail, evenly spaced turned balusters
-- (cylinders), and a cap rail. Returns a merged indexed
-- `position_normal_color_uv_f32` mesh.
function M.make_railing(options)
   options = options or {}
   local length = tonumber(options.length) or 4.0
   local height = tonumber(options.height) or 1.0
   local depth = tonumber(options.depth) or 0.16
   local baluster_radius = tonumber(options.baluster_radius) or 0.055
   local spacing = tonumber(options.spacing) or 0.28
   local base_height = tonumber(options.base_height) or 0.12
   local cap_height = tonumber(options.cap_height) or 0.10
   if length <= 0.0 or height <= 0.0 or depth <= 0.0 then
      rig.raise("mesh.make_railing dimensions must be positive")
   end
   if baluster_radius <= 0.0 or spacing <= 0.0 then
      rig.raise("mesh.make_railing baluster radius and spacing must be positive")
   end
   if base_height + cap_height >= height then
      rig.raise("mesh.make_railing base and cap must fit inside the height")
   end

   local color = options.color
   local cap_color = options.cap_color or color
   local builder = M.builder()
   builder:add(M.make_box {
      width = length,
      height = base_height,
      depth = depth,
      color = color,
   }, { transform = mathx.mat4_translation(mathx.mat4(), 0.0, base_height * 0.5, 0.0) })
   builder:add(M.make_box {
      width = length,
      height = cap_height,
      depth = depth * 1.15,
      color = cap_color,
   }, { transform = mathx.mat4_translation(mathx.mat4(), 0.0, height - cap_height * 0.5, 0.0) })

   local inner_height = height - base_height - cap_height
   local count = math.max(1, math.floor(length / spacing + 0.5))
   local step = length / count
   local baluster = M.make_cylinder {
      radius = baluster_radius,
      height = inner_height,
      segments = 8,
      caps = false,
      color = color,
   }
   for i = 1, count do
      local x = -length * 0.5 + (i - 0.5) * step
      builder:add(baluster, {
         transform = mathx.mat4_translation(mathx.mat4(), x, base_height + inner_height * 0.5, 0.0),
      })
   end

   return builder:build()
end

-- A bench pew facing +Z: a seat, a backrest on the -Z side, closed end panels,
-- and an optional foot/kneeler rail. Built from y = 0 to `back_height` and
-- centered on X. Returns a merged indexed `position_normal_color_uv_f32` mesh.
function M.make_pew(options)
   options = options or {}
   local length = tonumber(options.length) or 1.9
   local seat_height = tonumber(options.seat_height) or 0.46
   local seat_depth = tonumber(options.seat_depth) or 0.42
   local seat_thickness = tonumber(options.seat_thickness) or 0.06
   local back_height = tonumber(options.back_height) or 0.98
   local back_thickness = tonumber(options.back_thickness) or 0.07
   if length <= 0.0 or seat_depth <= 0.0 then
      rig.raise("mesh.make_pew length and depth must be positive")
   end
   if seat_height <= 0.0 or back_height <= seat_height then
      rig.raise("mesh.make_pew back height must be above the seat")
   end

   local color = options.color
   local seat_color = options.seat_color or color
   local back_color = options.back_color or color
   local builder = M.builder()
   local function at(box_options, x, y, z)
      builder:add(M.make_box(box_options), {
         transform = mathx.mat4_translation(mathx.mat4(), x, y, z),
      })
   end

   at({
      width = length,
      height = seat_thickness,
      depth = seat_depth,
      color = seat_color,
   }, 0.0, seat_height - seat_thickness * 0.5, 0.0)

   local back_y = (seat_height + back_height) * 0.5
   local back_z = -seat_depth * 0.5 + back_thickness * 0.5
   at({
      width = length,
      height = back_height - seat_height,
      depth = back_thickness,
      color = back_color,
   }, 0.0, back_y, back_z)

   local panel_height = seat_height
   local panel_thickness = options.panel_thickness or 0.09
   for _, x in ipairs { -length * 0.5 + panel_thickness * 0.5, length * 0.5 - panel_thickness * 0.5 } do
      at({
         width = panel_thickness,
         height = panel_height,
         depth = seat_depth,
         color = color,
      }, x, panel_height * 0.5, 0.0)
   end

   if options.kneeler ~= false then
      at({
         width = length - panel_thickness * 2.0,
         height = 0.05,
         depth = 0.05,
         color = color,
      }, 0.0, 0.10, seat_depth * 0.5 + 0.12)
      at({
         width = length - panel_thickness * 2.0,
         height = 0.05,
         depth = 0.05,
         color = color,
      }, 0.0, 0.10, -seat_depth * 0.5 - 0.12)
   end

   return builder:build()
end

-- A rectangular wall in the XY plane from y = 0 to `height`, centered on X and
-- extruded through `thickness` on Z. `openings` are rectangular holes measured
-- from the wall's left edge and bottom: `{ x, y, width, height }`.
function M.make_wall(options)
   options = options or {}
   local width = tonumber(options.width) or 4.0
   local height = tonumber(options.height) or 3.0
   local thickness = tonumber(options.thickness) or 0.25
   if width <= 0.0 or height <= 0.0 or thickness <= 0.0 then
      rig.raise("mesh.make_wall dimensions must be positive")
   end

   local center_z = tonumber(options.center_z) or 0.0
   local half_width = width * 0.5
   local half_thickness = thickness * 0.5
   local color_components = resolve_components(options.color, "mesh.make_wall color")
   local reveal_color = resolve_components(
      options.reveal_color or options.color,
      "mesh.make_wall reveal_color"
   )
   local scale_u, scale_v = resolve_uv_scale(options.uv_scale, "mesh.make_wall uv_scale")

   local openings = {}
   for i, opening in ipairs(options.openings or {}) do
      local x = tonumber(opening.x) or 0.0
      local y = tonumber(opening.y) or 0.0
      local opening_width = tonumber(opening.width) or 0.0
      local opening_height = tonumber(opening.height) or 0.0
      if opening_width <= 0.0 or opening_height <= 0.0 then
         rig.raise("mesh.make_wall opening %d needs a positive width and height", i)
      end
      local left = -half_width + x
      local right = left + opening_width
      local bottom = y
      local top = y + opening_height
      if left < -half_width - 1e-9 or right > half_width + 1e-9
         or bottom < -1e-9 or top > height + 1e-9 then
         rig.raise("mesh.make_wall opening %d lies outside the wall", i)
      end
      openings[#openings + 1] = {
         left = left,
         right = right,
         bottom = bottom,
         top = top,
      }
   end

   local xs = { -half_width, half_width }
   local ys = { 0.0, height }
   local function add_cut(values, value)
      for i = 1, #values do
         if math.abs(values[i] - value) < 1e-7 then
            return
         end
      end
      values[#values + 1] = value
   end
   for _, opening in ipairs(openings) do
      add_cut(xs, opening.left)
      add_cut(xs, opening.right)
      add_cut(ys, opening.bottom)
      add_cut(ys, opening.top)
   end
   table.sort(xs)
   table.sort(ys)

   local vertices, indices = {}, {}
   local function wall_uv(x, y)
      return { x * scale_u, y * scale_v }
   end

   local function inside_opening(x, y)
      for _, opening in ipairs(openings) do
         if x > opening.left + 1e-7 and x < opening.right - 1e-7
            and y > opening.bottom + 1e-7 and y < opening.top - 1e-7 then
            return true
         end
      end
      return false
   end

   local front_z = center_z + half_thickness
   local back_z = center_z - half_thickness
   for xi = 1, #xs - 1 do
      local x0, x1 = xs[xi], xs[xi + 1]
      for yi = 1, #ys - 1 do
         local y0, y1 = ys[yi], ys[yi + 1]
         local cx, cy = (x0 + x1) * 0.5, (y0 + y1) * 0.5
         if not inside_opening(cx, cy) then
            append_quad(
               vertices,
               indices,
               make_vertex({ x0, y0, front_z }, { 0, 0, 1 }, wall_uv(x0, y0), color_components),
               make_vertex({ x1, y0, front_z }, { 0, 0, 1 }, wall_uv(x1, y0), color_components),
               make_vertex({ x1, y1, front_z }, { 0, 0, 1 }, wall_uv(x1, y1), color_components),
               make_vertex({ x0, y1, front_z }, { 0, 0, 1 }, wall_uv(x0, y1), color_components)
            )
            append_quad(
               vertices,
               indices,
               make_vertex({ x0, y0, back_z }, { 0, 0, -1 }, wall_uv(x0, y0), color_components),
               make_vertex({ x0, y1, back_z }, { 0, 0, -1 }, wall_uv(x0, y1), color_components),
               make_vertex({ x1, y1, back_z }, { 0, 0, -1 }, wall_uv(x1, y1), color_components),
               make_vertex({ x1, y0, back_z }, { 0, 0, -1 }, wall_uv(x1, y0), color_components)
            )
         end
      end
   end

   local function side_quad(a, b, c, d, normal)
      append_quad(
         vertices,
         indices,
         make_vertex(a, normal, { a[3] * scale_u, a[2] * scale_v }, color_components),
         make_vertex(b, normal, { b[3] * scale_u, b[2] * scale_v }, color_components),
         make_vertex(c, normal, { c[3] * scale_u, c[2] * scale_v }, color_components),
         make_vertex(d, normal, { d[3] * scale_u, d[2] * scale_v }, color_components)
      )
   end

   side_quad(
      { -half_width, 0.0, back_z },
      { -half_width, 0.0, front_z },
      { -half_width, height, front_z },
      { -half_width, height, back_z },
      { -1, 0, 0 }
   )
   side_quad(
      { half_width, 0.0, front_z },
      { half_width, 0.0, back_z },
      { half_width, height, back_z },
      { half_width, height, front_z },
      { 1, 0, 0 }
   )
   side_quad(
      { -half_width, height, back_z },
      { half_width, height, back_z },
      { half_width, height, front_z },
      { -half_width, height, front_z },
      { 0, 1, 0 }
   )
   side_quad(
      { -half_width, 0.0, front_z },
      { half_width, 0.0, front_z },
      { half_width, 0.0, back_z },
      { -half_width, 0.0, back_z },
      { 0, -1, 0 }
   )

   for _, opening in ipairs(openings) do
      local left, right = opening.left, opening.right
      local bottom, top = opening.bottom, opening.top
      append_quad(
         vertices,
         indices,
         make_vertex({ left, bottom, back_z }, { 1, 0, 0 }, { 0, 0 }, reveal_color),
         make_vertex({ left, bottom, front_z }, { 1, 0, 0 }, { 1, 0 }, reveal_color),
         make_vertex({ left, top, front_z }, { 1, 0, 0 }, { 1, 1 }, reveal_color),
         make_vertex({ left, top, back_z }, { 1, 0, 0 }, { 0, 1 }, reveal_color)
      )
      append_quad(
         vertices,
         indices,
         make_vertex({ right, bottom, front_z }, { -1, 0, 0 }, { 0, 0 }, reveal_color),
         make_vertex({ right, bottom, back_z }, { -1, 0, 0 }, { 1, 0 }, reveal_color),
         make_vertex({ right, top, back_z }, { -1, 0, 0 }, { 1, 1 }, reveal_color),
         make_vertex({ right, top, front_z }, { -1, 0, 0 }, { 0, 1 }, reveal_color)
      )
      append_quad(
         vertices,
         indices,
         make_vertex({ left, bottom, front_z }, { 0, 1, 0 }, { 0, 0 }, reveal_color),
         make_vertex({ right, bottom, front_z }, { 0, 1, 0 }, { 1, 0 }, reveal_color),
         make_vertex({ right, bottom, back_z }, { 0, 1, 0 }, { 1, 1 }, reveal_color),
         make_vertex({ left, bottom, back_z }, { 0, 1, 0 }, { 0, 1 }, reveal_color)
      )
      append_quad(
         vertices,
         indices,
         make_vertex({ left, top, back_z }, { 0, -1, 0 }, { 0, 0 }, reveal_color),
         make_vertex({ right, top, back_z }, { 0, -1, 0 }, { 1, 0 }, reveal_color),
         make_vertex({ right, top, front_z }, { 0, -1, 0 }, { 1, 1 }, reveal_color),
         make_vertex({ left, top, front_z }, { 0, -1, 0 }, { 0, 1 }, reveal_color)
      )
   end

   return pack_mesh(vertices, "position_normal_color_uv_f32", "triangles", indices)
end

-- A tiled floor plane on XZ, centered on the origin at y = 0.
function M.make_floor_bay(options)
   options = options or {}
   local width = tonumber(options.width) or 4.0
   local depth = tonumber(options.depth) or 4.0
   local segments_x = math.floor(
      tonumber(options.segments_x) or tonumber(options.segments) or 1
   )
   local segments_z = math.floor(
      tonumber(options.segments_z) or tonumber(options.segments) or 1
   )
   if width <= 0.0 or depth <= 0.0 then
      rig.raise("mesh.make_floor_bay dimensions must be positive")
   end
   if segments_x < 1 or segments_z < 1 then
      rig.raise("mesh.make_floor_bay segments must be at least 1")
   end

   local color_components = resolve_components(
      options.color,
      "mesh.make_floor_bay color"
   )
   local scale_u, scale_v = resolve_uv_scale(
      options.uv_scale,
      "mesh.make_floor_bay uv_scale"
   )
   local half_width = width * 0.5
   local half_depth = depth * 0.5
   local vertices, indices = {}, {}

   for zi = 0, segments_z do
      local z = -half_depth + depth * (zi / segments_z)
      for xi = 0, segments_x do
         local x = -half_width + width * (xi / segments_x)
         vertices[#vertices + 1] = make_vertex(
            { x, 0.0, z },
            { 0.0, 1.0, 0.0 },
            { (x + half_width) * scale_u, (z + half_depth) * scale_v },
            color_components
         )
      end
   end

   local row = segments_x + 1
   for zi = 0, segments_z - 1 do
      for xi = 0, segments_x - 1 do
         local a = zi * row + xi + 1
         local b = a + 1
         local c = a + row + 1
         local d = a + row
         indices[#indices + 1] = a
         indices[#indices + 1] = c
         indices[#indices + 1] = b
         indices[#indices + 1] = a
         indices[#indices + 1] = d
         indices[#indices + 1] = c
      end
   end

   return pack_mesh(vertices, "position_normal_color_uv_f32", "triangles", indices)
end

M.make_floor = M.make_floor_bay

-- A hollow barrel-vault section with its axis along Z, spanning `start_angle` to
-- `end_angle` in the XY cross-section. The default is a round upper half-vault.
function M.make_barrel_vault(options)
   options = options or {}
   local radius = tonumber(options.radius) or 2.0
   local thickness = tonumber(options.thickness) or 0.2
   local length = tonumber(options.length) or 3.0
   local segments = math.floor(tonumber(options.segments) or 20)
   local start_angle = tonumber(options.start_angle) or 0.0
   local end_angle = tonumber(options.end_angle) or math.pi
   if radius <= 0.0 or thickness <= 0.0 or length <= 0.0 then
      rig.raise("mesh.make_barrel_vault radius, thickness, and length must be positive")
   end
   if thickness >= radius then
      rig.raise("mesh.make_barrel_vault thickness must be smaller than radius")
   end
   if segments < 1 or end_angle <= start_angle then
      rig.raise("mesh.make_barrel_vault needs a positive angle span and at least one segment")
   end

   local inner_radius = radius - thickness
   local half_length = length * 0.5
   local color_components = resolve_components(
      options.color,
      "mesh.make_barrel_vault color"
   )
   local scale_u, scale_v = resolve_uv_scale(
      options.uv_scale,
      "mesh.make_barrel_vault uv_scale"
   )
   local vertices, indices = {}, {}
   local span = end_angle - start_angle

   local function point(radius_value, angle, z)
      return { radius_value * math.cos(angle), radius_value * math.sin(angle), z }
   end

   local function vertex(position, normal, uv)
      return make_vertex(position, normal, uv, color_components)
   end

   for i = 0, segments - 1 do
      local a0 = start_angle + span * (i / segments)
      local a1 = start_angle + span * ((i + 1) / segments)
      local mid = (a0 + a1) * 0.5
      local outer_normal = { math.cos(mid), math.sin(mid), 0.0 }
      local inner_normal = { -math.cos(mid), -math.sin(mid), 0.0 }
      local u0 = (i / segments) * scale_u
      local u1 = ((i + 1) / segments) * scale_u

      append_quad(
         vertices,
         indices,
         vertex(point(radius, a0, -half_length), outer_normal, { u0, 0.0 }),
         vertex(point(radius, a1, -half_length), outer_normal, { u1, 0.0 }),
         vertex(point(radius, a1, half_length), outer_normal, { u1, scale_v }),
         vertex(point(radius, a0, half_length), outer_normal, { u0, scale_v })
      )
      append_quad(
         vertices,
         indices,
         vertex(point(inner_radius, a0, -half_length), inner_normal, { u0, 0.0 }),
         vertex(point(inner_radius, a1, -half_length), inner_normal, { u1, 0.0 }),
         vertex(point(inner_radius, a1, half_length), inner_normal, { u1, scale_v }),
         vertex(point(inner_radius, a0, half_length), inner_normal, { u0, scale_v })
      )
      append_quad(
         vertices,
         indices,
         vertex(point(radius, a0, -half_length), { 0, 0, -1 }, { u0, 0.0 }),
         vertex(point(inner_radius, a0, -half_length), { 0, 0, -1 }, { u0, 1.0 }),
         vertex(point(inner_radius, a1, -half_length), { 0, 0, -1 }, { u1, 1.0 }),
         vertex(point(radius, a1, -half_length), { 0, 0, -1 }, { u1, 0.0 })
      )
      append_quad(
         vertices,
         indices,
         vertex(point(radius, a0, half_length), { 0, 0, 1 }, { u0, 0.0 }),
         vertex(point(radius, a1, half_length), { 0, 0, 1 }, { u1, 0.0 }),
         vertex(point(inner_radius, a1, half_length), { 0, 0, 1 }, { u1, 1.0 }),
         vertex(point(inner_radius, a0, half_length), { 0, 0, 1 }, { u0, 1.0 })
      )
   end

   local function add_angle_cap(angle, sign)
      local normal = { -math.sin(angle) * sign, math.cos(angle) * sign, 0.0 }
      append_quad(
         vertices,
         indices,
         vertex(point(radius, angle, -half_length), normal, { 0.0, 0.0 }),
         vertex(point(radius, angle, half_length), normal, { 1.0, 0.0 }),
         vertex(point(inner_radius, angle, half_length), normal, { 1.0, 1.0 }),
         vertex(point(inner_radius, angle, -half_length), normal, { 0.0, 1.0 })
      )
   end
   add_angle_cap(start_angle, 1.0)
   add_angle_cap(end_angle, -1.0)

   return pack_mesh(vertices, "position_normal_color_uv_f32", "triangles", indices)
end

-- A hollow dome (half-ellipsoid) of revolution around Y, springing at y = 0 and
-- opening downward, so the concave inner surface is seen from inside. Emits
-- indexed `position_normal_color_uv_f32` triangles with outer, inner, and base
-- rim surfaces.
function M.make_dome(options)
   options = options or {}
   local radius = tonumber(options.radius) or 2.0
   local height = tonumber(options.height) or radius
   local thickness = tonumber(options.thickness) or radius * 0.06
   local segments = math.floor(tonumber(options.segments) or 24)
   local rings = math.floor(tonumber(options.rings) or 10)
   if radius <= 0.0 or height <= 0.0 or thickness <= 0.0 then
      rig.raise("mesh.make_dome radius, height, and thickness must be positive")
   end
   if thickness >= radius or thickness >= height then
      rig.raise("mesh.make_dome thickness must be smaller than radius and height")
   end
   if segments < 3 or rings < 1 then
      rig.raise("mesh.make_dome needs at least three segments and one ring")
   end

   local inner_radius = radius - thickness
   local inner_height = height - thickness
   local color_components = resolve_components(options.color, "mesh.make_dome color")
   local scale_u, scale_v = resolve_uv_scale(options.uv_scale, "mesh.make_dome uv_scale")
   local vertices, indices = {}, {}
   local half_pi = math.pi * 0.5

   local function point(r, h, theta, phi)
      local ring_radius = r * math.cos(phi)
      return {
         ring_radius * math.cos(theta),
         h * math.sin(phi),
         ring_radius * math.sin(theta),
      }
   end

   local function normal(position, flip)
      local nx = position[1] / (radius * radius)
      local ny = position[2] / (height * height)
      local nz = position[3] / (radius * radius)
      local length = math.sqrt(nx * nx + ny * ny + nz * nz)
      if length == 0.0 then
         nx, ny, nz = 0.0, 1.0, 0.0
      else
         nx, ny, nz = nx / length, ny / length, nz / length
      end
      if flip then
         nx, ny, nz = -nx, -ny, -nz
      end
      return { nx, ny, nz }
   end

   local function vertex(position, position_normal, u, v)
      return make_vertex(position, position_normal, { u, v }, color_components)
   end

   for i = 0, segments - 1 do
      local t0 = (i / segments) * math.pi * 2.0
      local t1 = ((i + 1) / segments) * math.pi * 2.0
      local u0 = (i / segments) * scale_u
      local u1 = ((i + 1) / segments) * scale_u
      for j = 0, rings - 1 do
         local p0 = (j / rings) * half_pi
         local p1 = ((j + 1) / rings) * half_pi
         local v0 = (j / rings) * scale_v
         local v1 = ((j + 1) / rings) * scale_v

         local o00 = point(radius, height, t0, p0)
         local o01 = point(radius, height, t0, p1)
         local o11 = point(radius, height, t1, p1)
         local o10 = point(radius, height, t1, p0)
         append_quad(
            vertices,
            indices,
            vertex(o00, normal(o00, false), u0, v0),
            vertex(o01, normal(o01, false), u0, v1),
            vertex(o11, normal(o11, false), u1, v1),
            vertex(o10, normal(o10, false), u1, v0)
         )

         local i00 = point(inner_radius, inner_height, t0, p0)
         local i01 = point(inner_radius, inner_height, t0, p1)
         local i11 = point(inner_radius, inner_height, t1, p1)
         local i10 = point(inner_radius, inner_height, t1, p0)
         append_quad(
            vertices,
            indices,
            vertex(i00, normal(i00, true), u0, v0),
            vertex(i10, normal(i10, true), u1, v0),
            vertex(i11, normal(i11, true), u1, v1),
            vertex(i01, normal(i01, true), u0, v1)
         )
      end
      -- Base rim: the downward-facing edge at the springing line.
      local o0 = point(radius, height, t0, 0.0)
      local o1 = point(radius, height, t1, 0.0)
      local r0 = point(inner_radius, inner_height, t0, 0.0)
      local r1 = point(inner_radius, inner_height, t1, 0.0)
      append_quad(
         vertices,
         indices,
         vertex(o0, { 0.0, -1.0, 0.0 }, u0, 0.0),
         vertex(o1, { 0.0, -1.0, 0.0 }, u1, 0.0),
         vertex(r1, { 0.0, -1.0, 0.0 }, u1, 1.0),
         vertex(r0, { 0.0, -1.0, 0.0 }, u0, 1.0)
      )
   end

   return pack_mesh(vertices, "position_normal_color_uv_f32", "triangles", indices)
end

-- Splits an indexed triangle mesh into per-key submeshes by classifying each
-- triangle with `classify(centroid_x, centroid_y, centroid_z)`. Triangles whose
-- key is nil are dropped. Vertex sharing is preserved within each bucket, and
-- the source layout/topology is kept. Returns `buckets` (key -> mesh) and the
-- `order` list of keys in first-seen order.
--
-- This operates directly on the vertex/index bytes, so partitioning a merged
-- building-scale mesh does not materialise Lua tables for every vertex.
function M.partition(source, classify, options)
   if type(classify) ~= "function" then
      rig.raise("mesh.partition classify must be a function")
   end
   options = options or {}
   local definition = M.layout(source.layout)
   local stride = source.vertex_stride
   local float_stride = stride / 4
   local vertex_count = source.vertex_count
   local blob = source.vertex_blob
   if type(blob) ~= "string" then
      rig.raise("mesh.partition source has no vertex_blob")
   end
   local positions = ffi.cast("const float *", ffi.cast("const char *", blob))

   local index_count
   local index_pointer
   local index_function
   if source.index_blob ~= nil then
      index_count = source.index_count or 0
      local index_type = source.index_type or "uint32"
      if index_type == "uint32" then
         index_pointer = ffi.cast(
            "const uint32_t *",
            ffi.cast("const char *", source.index_blob)
         )
         index_function = function(i)
            return index_pointer[i]
         end
      elseif index_type == "uint16" then
         index_pointer = ffi.cast(
            "const uint16_t *",
            ffi.cast("const char *", source.index_blob)
         )
         index_function = function(i)
            return index_pointer[i]
         end
      else
         rig.raise("mesh.partition does not support index type '%s'", index_type)
      end
   else
      index_count = vertex_count
      index_function = function(i)
         return i
      end
   end

   local buckets = {}
   local order = {}
   for t = 0, index_count - 1, 3 do
      local i0 = index_function(t)
      local i1 = index_function(t + 1)
      local i2 = index_function(t + 2)
      local b0 = i0 * float_stride
      local b1 = i1 * float_stride
      local b2 = i2 * float_stride
      local cx = (positions[b0] + positions[b1] + positions[b2]) / 3.0
      local cy = (positions[b0 + 1] + positions[b1 + 1] + positions[b2 + 1]) / 3.0
      local cz = (positions[b0 + 2] + positions[b1 + 2] + positions[b2 + 2]) / 3.0
      local key = classify(cx, cy, cz)
      if key ~= nil then
         local bucket = buckets[key]
         if bucket == nil then
            bucket = { map = {}, remap = {}, indices = {} }
            buckets[key] = bucket
            order[#order + 1] = key
         end
         local indices = bucket.indices
         local map = bucket.map
         local remap = bucket.remap
         local mapped0 = map[i0]
         if mapped0 == nil then
            remap[#remap + 1] = i0
            mapped0 = #remap
            map[i0] = mapped0
         end
         local mapped1 = map[i1]
         if mapped1 == nil then
            remap[#remap + 1] = i1
            mapped1 = #remap
            map[i1] = mapped1
         end
         local mapped2 = map[i2]
         if mapped2 == nil then
            remap[#remap + 1] = i2
            mapped2 = #remap
            map[i2] = mapped2
         end
         indices[#indices + 1] = mapped0
         indices[#indices + 1] = mapped1
         indices[#indices + 1] = mapped2
      end
   end

   local result = {}
   local source_bytes = ffi.cast("const char *", blob)
   for _, key in ipairs(order) do
      local bucket = buckets[key]
      local count = #bucket.remap
      local buffer = ffi.new("char[?]", count * stride)
      local destination = ffi.cast("char *", buffer)
      for local_index = 1, count do
         local global = bucket.remap[local_index]
         ffi.copy(
            destination + (local_index - 1) * stride,
            source_bytes + global * stride,
            stride
         )
      end
      local mesh = {
         layout = source.layout,
         topology = "triangles",
         vertex_stride = stride,
         vertex_count = count,
         attribute_offsets = {},
         vertex_blob = ffi.string(buffer, count * stride),
      }
      for role, attribute in pairs(definition.attributes) do
         mesh.attribute_offsets[role] = attribute.offset
      end
      local index_buffer = ffi.new("uint32_t[?]", #bucket.indices)
      for i = 1, #bucket.indices do
         index_buffer[i - 1] = bucket.indices[i] - 1
      end
      mesh.index_blob = ffi.string(
         ffi.cast("const char *", index_buffer),
         #bucket.indices * 4
      )
      mesh.index_count = #bucket.indices
      mesh.index_type = "uint32"
      mesh.index_stride = 4
      result[key] = mesh
   end
   return result, order
end

local function parse_number(token, label)
   local value = tonumber(token)
   if value == nil then
      rig.raise("mesh.parse_obj: invalid %s value '%s'", label, token)
   end
   return value
end

local function resolve_obj_index(raw, count, label)
   if raw == nil or raw == "" then
      return nil
   end
   local index = tonumber(raw)
   if index == nil then
      rig.raise("mesh.parse_obj: invalid %s index '%s'", label, raw)
   end
   index = math.floor(index)
   if index < 0 then
      index = count + index + 1
   end
   if index < 1 or index > count then
      rig.raise("mesh.parse_obj: %s index %s is out of range", label, raw)
   end
   return index
end

-- Parses Wavefront OBJ text into a `position_color_uv_f32` triangle mesh.
-- Positions and texture coordinates are read; normals and materials are ignored
-- because the built-in materials are unlit. Faces are triangulated as fans, and
-- a single `options.color` (default white) tints the whole mesh so a bound
-- texture is sampled unchanged.
function M.parse_obj(text, options)
   options = options or {}
   if type(text) ~= "string" then
      rig.raise("mesh.parse_obj expects OBJ source text")
   end

   local r, g, b = unpack_color(options.color, "mesh.parse_obj color")
   local positions = {}
   local uvs = {}
   local vertices = {}

   local function add_vertex(position_index, uv_index)
      local position = positions[position_index]
      if position == nil then
         rig.raise("mesh.parse_obj: face references an unknown position")
      end

      local u, v = 0.0, 0.0
      if uv_index ~= nil then
         local uv = uvs[uv_index]
         if uv == nil then
            rig.raise("mesh.parse_obj: face references an unknown texture coordinate")
         end
         u, v = uv[1], uv[2]
      end

      vertices[#vertices + 1] = {
         position[1],
         position[2],
         position[3],
         r,
         g,
         b,
         u,
         v,
      }
   end

   for line in text:gmatch("[^\r\n]+") do
      local keyword, rest = line:match("^%s*(%S+)%s*(.*)$")
      if keyword == "v" then
         local x, y, z = rest:match("^%s*(%S+)%s+(%S+)%s+(%S+)")
         if x == nil then
            rig.raise("mesh.parse_obj: malformed vertex position")
         end
         positions[#positions + 1] = {
            parse_number(x, "position"),
            parse_number(y, "position"),
            parse_number(z, "position"),
         }
      elseif keyword == "vt" then
         local u, v = rest:match("^%s*(%S+)%s+(%S+)")
         if u == nil then
            rig.raise("mesh.parse_obj: malformed texture coordinate")
         end
         uvs[#uvs + 1] = {
            parse_number(u, "texture coordinate"),
            parse_number(v, "texture coordinate"),
         }
      elseif keyword == "f" then
         local face = {}
         for token in rest:gmatch("%S+") do
            local position_raw = token:match("^(%-?%d+)")
            local uv_raw = token:match("^%-?%d+/(%-?%d+)")
            local position_index =
               resolve_obj_index(position_raw, #positions, "position")
            local uv_index = resolve_obj_index(uv_raw, #uvs, "texture coordinate")
            face[#face + 1] = { position_index, uv_index }
         end

         if #face < 3 then
            rig.raise("mesh.parse_obj: a face needs at least three vertices")
         end

         for i = 2, #face - 1 do
            add_vertex(face[1][1], face[1][2])
            add_vertex(face[i][1], face[i][2])
            add_vertex(face[i + 1][1], face[i + 1][2])
         end
      end
   end

   if #vertices == 0 then
      rig.raise("mesh.parse_obj: no faces were found in the OBJ source")
   end

   return pack_position_color_uv(vertices, "triangles")
end

local Builder = {}
M.Builder = Builder

-- A mesh merge builder. Every `add` becomes one material range with a
-- zero-based index offset/count; the builder outputs indexed uint32 triangles.
--
-- options.layout selects an explicit target layout. Otherwise `normals = false`
-- selects `position_color_uv_f32`, `tangents = true` selects
-- `position_normal_tangent_color_uv_f32`, and the default is
-- `position_normal_color_uv_f32`.
function M.builder(options)
   options = options or {}
   if type(options) ~= "table" then
      rig.raise("mesh.builder expects an options table")
   end

   local target_layout_name
   if options.layout ~= nil then
      target_layout_name = options.layout
   elseif options.tangents then
      target_layout_name = "position_normal_tangent_color_uv_f32"
   elseif options.normals == false then
      target_layout_name = "position_color_uv_f32"
   else
      target_layout_name = "position_normal_color_uv_f32"
   end
   local target_layout = M.layout(target_layout_name)

   return setmetatable({
      _options = options,
      _target_layout = target_layout,
      _target_layout_name = target_layout_name,
      _vertices = {},
      _indices = {},
      _sections = {},
   }, { __index = Builder })
end

function Builder:add(source, options)
   options = options or {}
   local source_vertices, source_indices = decode_mesh(source)
   local transform = options.transform
   local inverse_transpose = nil
   local mirrored = false
   if transform ~= nil then
      if type(transform) ~= "cdata" then
         rig.raise("mesh builder transform must be a float[16] matrix")
      end
      inverse_transpose = normal_matrix(transform)
      mirrored = determinant3(transform) < 0.0
   end

   local color_override = nil
   if options.color ~= nil then
      color_override = resolve_components(options.color, "mesh builder color")
   end
   local scale_u, scale_v = resolve_uv_scale(
      options.uv_scale,
      "mesh builder uv_scale"
   )
   local offset_u = tonumber(options.uv_offset_u) or 0.0
   local offset_v = tonumber(options.uv_offset_v) or 0.0
   local vertex_offset = #self._vertices
   local index_offset = #self._indices
   local first_vertex = vertex_offset + 1

   for i = 1, #source_vertices do
      local source_vertex = source_vertices[i]
      local vertex = {
         position = source_vertex.position,
         normal = source_vertex.normal,
         tangent = source_vertex.tangent,
         color = color_override or source_vertex.color,
         uv = source_vertex.uv,
      }

      if transform ~= nil then
         vertex.position = transform_point(transform, vertex.position)
         if vertex.normal ~= nil then
            vertex.normal = transform_normal(inverse_transpose, vertex.normal)
         end
         if vertex.tangent ~= nil then
            local tangent = transform_direction(transform, vertex.tangent)
            local nx, ny, nz = normalize3(tangent[1], tangent[2], tangent[3])
            local handedness = vertex.tangent[4] or 1.0
            if mirrored then
               handedness = -handedness
            end
            vertex.tangent = { nx, ny, nz, handedness }
         end
      end

      if vertex.uv ~= nil then
         vertex.uv = {
            vertex.uv[1] * scale_u + offset_u,
            vertex.uv[2] * scale_v + offset_v,
         }
      end
      self._vertices[#self._vertices + 1] = vertex
   end

   for i = 1, #source_indices, 3 do
      local a = source_indices[i] + first_vertex
      local b = source_indices[i + 1] + first_vertex
      local c = source_indices[i + 2] + first_vertex
      if mirrored then
         b, c = c, b
      end
      self._indices[#self._indices + 1] = a
      self._indices[#self._indices + 1] = b
      self._indices[#self._indices + 1] = c
   end

   self._sections[#self._sections + 1] = {
      name = options.name,
      material = options.material,
      index_offset = index_offset,
      index_count = #self._indices - index_offset,
      vertex_offset = vertex_offset,
      vertex_count = #self._vertices - vertex_offset,
   }
   return self
end

function Builder:add_mesh(source, options)
   return self:add(source, options)
end

function Builder:build()
   if #self._vertices == 0 or #self._indices == 0 then
      rig.raise("mesh builder has no geometry")
   end

   local has_normal = self._target_layout.attributes.normal ~= nil
   local has_tangent = self._target_layout.attributes.tangent ~= nil
   if has_normal and self._options.generate_normals ~= false then
      generate_normals(self._vertices, self._indices)
   end
   if has_tangent and self._options.generate_tangents ~= false then
      generate_tangents(self._vertices, self._indices)
   end

   local result = pack_mesh(
      self._vertices,
      self._target_layout_name,
      "triangles",
      self._indices
   )

   local ranges = {}
   for i = 1, #self._sections do
      local section = self._sections[i]
      ranges[i] = {
         name = section.name,
         material = section.material,
         index_offset = section.index_offset,
         index_count = section.index_count,
         vertex_offset = section.vertex_offset,
         vertex_count = section.vertex_count,
      }
   end
   result.material_ranges = ranges
   result.sections = ranges
   return result
end

-- Convenience: `mesh.merge({ { mesh = a, material = mat }, ... }, options)`.
function M.merge(parts, options)
   local builder = M.builder(options)
   for i = 1, #parts do
      local part = parts[i]
      if type(part) ~= "table" or part.mesh == nil then
         rig.raise("mesh.merge parts[%d] must contain a mesh", i)
      end
      builder:add(part.mesh, part)
   end
   return builder:build()
end

function M.build_vertex_input(mesh, provider)
   if type(mesh) ~= "table" then
      error("mesh.build_vertex_input expects a mesh table")
   end

   provider = provider or rig.raise(
      "mesh.build_vertex_input requires a mesh.vertex_input provider"
   )
   return provider.build_vertex_input(mesh)
end

function M.bind(provider)
   if type(provider) ~= "table" then
      rig.raise("mesh.bind expects a mesh.vertex_input provider")
   end

   return {
      build_vertex_input = function(_, mesh)
         return M.build_vertex_input(mesh, provider)
      end,
   }
end

function M.plugin(spec)
   spec = spec or {}
   return runtime.plugin {
      id = spec.id or "mesh",
      capabilities = {
         ["mesh.vertex_input"] = {},
      },
   }
end

function M.component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      requires = {
         { capability = "mesh.vertex_input" },
      },
      create = function(context)
         return M.bind(context:capability("mesh.vertex_input"))
      end,
   })
end

return M
