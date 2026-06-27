local M = ... or {}
local ffi = require("ffi")
local color = require("color")
local rig = require("rig")

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

local function append_vertex(values, corner, scale, face_color)
   local r, g, b = face_color:to_rgbf()
   values[#values + 1] = corner[1] * scale
   values[#values + 1] = corner[2] * scale
   values[#values + 1] = corner[3] * scale
   values[#values + 1] = r
   values[#values + 1] = g
   values[#values + 1] = b
end

rig.register_service("mesh.vertex_input", {
   "build_vertex_input",
})

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
   local values = {}

   for face_index = 1, 6 do
      local corners = FACE_CORNERS[face_index]
      local color = colors[face_index]

      append_vertex(values, corners[1], half_extent, color)
      append_vertex(values, corners[2], half_extent, color)
      append_vertex(values, corners[3], half_extent, color)
      append_vertex(values, corners[1], half_extent, color)
      append_vertex(values, corners[3], half_extent, color)
      append_vertex(values, corners[4], half_extent, color)
   end

   local vertex_array = ffi.new("float[?]", #values)
   for i = 1, #values do
      vertex_array[i - 1] = values[i]
   end

   return {
      layout = "position_color_f32",
      vertex_stride = 24,
      vertex_count = 36,
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

function M.build_vertex_input(mesh)
   if type(mesh) ~= "table" then
      error("mesh.build_vertex_input expects a mesh table")
   end

   return rig.require_service("mesh.vertex_input").build_vertex_input(mesh)
end

return M
