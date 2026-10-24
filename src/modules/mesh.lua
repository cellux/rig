local M = ... or {}
local ffi = require("ffi")
local color = require("color")
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
