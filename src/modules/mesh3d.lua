local M = ... or {}
local ffi = require("ffi")
local sdl3 = require("sdl3")

local DEFAULT_FACE_COLORS = {
   { 1, 0, 0 },
   { 0, 1, 0 },
   { 0, 0, 1 },
   { 1, 1, 0 },
   { 1, 0, 1 },
   { 0, 1, 1 },
}

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

local function clone_color(color)
   return {
      tonumber(color[1]) or 0.0,
      tonumber(color[2]) or 0.0,
      tonumber(color[3]) or 0.0,
   }
end

local function resolve_face_colors(options)
   if options.colors == nil or options.colors == "face" then
      local colors = {}
      for i = 1, #DEFAULT_FACE_COLORS do
         colors[i] = clone_color(DEFAULT_FACE_COLORS[i])
      end
      return colors
   end

   if type(options.colors) ~= "table" then
      error("mesh3d.make_cube colors must be 'face' or a table", 0)
   end
   if #options.colors ~= 6 then
      error("mesh3d.make_cube colors table must contain 6 face colors", 0)
   end

   local colors = {}
   for i = 1, 6 do
      local color = options.colors[i]
      if type(color) ~= "table" then
         error("mesh3d.make_cube face colors must be tables", 0)
      end
      colors[i] = clone_color(color)
   end
   return colors
end

local function append_vertex(values, corner, scale, color)
   values[#values + 1] = corner[1] * scale
   values[#values + 1] = corner[2] * scale
   values[#values + 1] = corner[3] * scale
   values[#values + 1] = color[1]
   values[#values + 1] = color[2]
   values[#values + 1] = color[3]
end

function M.make_cube(options)
   options = options or {}
   if type(options) ~= "table" then
      error("mesh3d.make_cube expects a table if options are provided")
   end

   local size = tonumber(options.size) or 2.0
   if size <= 0.0 then
      error("mesh3d.make_cube size must be positive", 0)
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

function sdl3.build_vertex_input_state_from_mesh(mesh)
   if type(mesh) ~= "table" then
      error("sdl3.build_vertex_input_state_from_mesh expects a mesh table")
   end

   if mesh.layout == "position_color_f32" then
      return sdl3.build_vertex_input_state {
         buffers = {
            {
               slot = 0,
               pitch = mesh.vertex_stride,
               input_rate = "vertex",
               attributes = {
                  {
                     location = 0,
                     format = "float3",
                     offset = mesh.attribute_offsets.position,
                  },
                  {
                     location = 1,
                     format = "float3",
                     offset = mesh.attribute_offsets.color,
                  },
               },
            },
         },
      }
   end

   error("unsupported mesh layout '" .. tostring(mesh.layout) .. "'", 0)
end

return M
