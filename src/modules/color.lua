local M = ... or {}
local rig = require("rig")
local ffi = require("ffi")

ffi.cdef([[
typedef struct {
   uint8_t components[4];
} rig_color_Color;
]])

local component_offsets = {
   r = 0,
   g = 1,
   b = 2,
   a = 3,
}

local function normalize_byte(value, label, default_value)
   local resolved = value
   if resolved == nil then
      resolved = default_value
   end
   if resolved == nil then
      rig.raise("missing color component '" .. label .. "'")
   end

   resolved = tonumber(resolved)
   if resolved == nil then
      rig.raise("color component '" .. label .. "' must be numeric")
   end

   if resolved < 0 then
      resolved = 0
   elseif resolved > 255 then
      resolved = 255
   end

   return math.floor(resolved + 0.5)
end

local function normalize_unit(value, label, default_value)
   local resolved = value
   if resolved == nil then
      resolved = default_value
   end
   if resolved == nil then
      rig.raise("missing color component '" .. label .. "'")
   end

   resolved = tonumber(resolved)
   if resolved == nil then
      rig.raise("color component '" .. label .. "' must be numeric")
   end

   if resolved < 0 then
      resolved = 0
   elseif resolved > 1 then
      resolved = 1
   end

   return math.floor(resolved * 255 + 0.5)
end

local function parse_hex(value)
   if type(value) ~= "string" then
      rig.raise("hex colors must be strings")
   end

   local hex = value
   if hex:sub(1, 1) == "#" then
      hex = hex:sub(2)
   end

   if #hex ~= 6 and #hex ~= 8 then
      rig.raise("hex colors must use RRGGBB or RRGGBBAA")
   end
   if not hex:match("^[%da-fA-F]+$") then
      rig.raise("hex colors must contain only hexadecimal digits")
   end

   local r = tonumber(hex:sub(1, 2), 16)
   local g = tonumber(hex:sub(3, 4), 16)
   local b = tonumber(hex:sub(5, 6), 16)
   local a = #hex == 8 and tonumber(hex:sub(7, 8), 16) or 255
   return r, g, b, a
end

local function assign_rgba8(self, r, g, b, a)
   self.components[0] = normalize_byte(r, "r")
   self.components[1] = normalize_byte(g, "g")
   self.components[2] = normalize_byte(b, "b")
   self.components[3] = normalize_byte(a, "a", 255)
end

local function assign_rgbaf(self, r, g, b, a)
   self.components[0] = normalize_unit(r, "r")
   self.components[1] = normalize_unit(g, "g")
   self.components[2] = normalize_unit(b, "b")
   self.components[3] = normalize_unit(a, "a", 1)
end

local function read_color_table(value)
   local r = value[1]
   local g = value[2]
   local b = value[3]
   local a = value[4]

   if r == nil and g == nil and b == nil and a == nil then
      r = value.r
      g = value.g
      b = value.b
      a = value.a
   end

   return r, g, b, a
end

local color_methods = {}
local Color

local function new_color_rgba8(r, g, b, a)
   local value = ffi.new("rig_color_Color")
   assign_rgba8(value, r, g, b, a)
   return value
end

local function new_color_rgbaf(r, g, b, a)
   local value = ffi.new("rig_color_Color")
   assign_rgbaf(value, r, g, b, a)
   return value
end

local function pack_components(a, b, c, d)
   return ((a * 256 + b) * 256 + c) * 256 + d
end

local function unpack_u32(value, format_name)
   local resolved = tonumber(value)
   if resolved == nil then
      rig.raise(format_name .. " colors must be numeric")
   end

   resolved = math.floor(resolved)
   if resolved < 0 then
      resolved = 0
   elseif resolved > 0xFFFFFFFF then
      resolved = 0xFFFFFFFF
   end

   local first = math.floor(resolved / 0x1000000) % 0x100
   local second = math.floor(resolved / 0x10000) % 0x100
   local third = math.floor(resolved / 0x100) % 0x100
   local fourth = resolved % 0x100
   return first, second, third, fourth
end

local function color_from_format(value, format_name)
   if format_name == "rgb"
      or format_name == "rgba"
      or format_name == "rgbf"
      or format_name == "rgbaf"
   then
      if type(value) ~= "table" then
         rig.raise("color format '" .. format_name .. "' expects a table")
      end

      local r, g, b, a = read_color_table(value)
      if format_name == "rgb" then
         return new_color_rgba8(r, g, b, 255)
      elseif format_name == "rgba" then
         return new_color_rgba8(r, g, b, a)
      elseif format_name == "rgbf" then
         return new_color_rgbaf(r, g, b, 1)
      end

      return new_color_rgbaf(r, g, b, a)
   elseif format_name == "hex"
      or format_name == "hex_rgb"
      or format_name == "hex_rgba"
   then
      return new_color_rgba8(parse_hex(value))
   elseif format_name == "u32_rgba"
      or format_name == "u32_argb"
      or format_name == "u32_abgr"
      or format_name == "u32_bgra"
   then
      local first, second, third, fourth = unpack_u32(value, format_name)
      if format_name == "u32_rgba" then
         return new_color_rgba8(first, second, third, fourth)
      elseif format_name == "u32_argb" then
         return new_color_rgba8(second, third, fourth, first)
      elseif format_name == "u32_abgr" then
         return new_color_rgba8(fourth, third, second, first)
      end

      return new_color_rgba8(third, second, first, fourth)
   end

   rig.raise("unsupported input color format '" .. tostring(format_name) .. "'")
end

local function color_to_format(self, format_name)
   if format_name == "rgb" then
      return {
         self.r,
         self.g,
         self.b,
      }
   elseif format_name == "rgba" then
      return {
         self.r,
         self.g,
         self.b,
         self.a,
      }
   elseif format_name == "rgbf" then
      return {
         self.r / 255.0,
         self.g / 255.0,
         self.b / 255.0,
      }
   elseif format_name == "rgbaf" then
      return {
         self.r / 255.0,
         self.g / 255.0,
         self.b / 255.0,
         self.a / 255.0,
      }
   elseif format_name == "hex_rgb" then
      return string.format("#%02X%02X%02X", self.r, self.g, self.b)
   elseif format_name == "hex_rgba" or format_name == "hex" then
      return string.format("#%02X%02X%02X%02X", self.r, self.g, self.b, self.a)
   elseif format_name == "u32_rgba" then
      return pack_components(self.r, self.g, self.b, self.a)
   elseif format_name == "u32_argb" then
      return pack_components(self.a, self.r, self.g, self.b)
   elseif format_name == "u32_abgr" then
      return pack_components(self.a, self.b, self.g, self.r)
   elseif format_name == "u32_bgra" then
      return pack_components(self.b, self.g, self.r, self.a)
   end

   rig.raise("unsupported output color format '" .. tostring(format_name) .. "'")
end

local function assign_color_value(self, value)
   self.components[0] = value.r
   self.components[1] = value.g
   self.components[2] = value.b
   self.components[3] = value.a
end

local function assign_color(self, first, g, b, a)
   if ffi.istype(Color, first) then
      assign_color_value(self, first)
      return
   end

   if type(first) == "table" then
      assign_color_value(self, color_from_format(first, "rgba"))
      return
   end

   if type(first) == "string" and g == nil and b == nil and a == nil then
      assign_color_value(self, color_from_format(first, "hex"))
      return
   end

   assign_color_value(self, color_from_format({
      first,
      g,
      b,
      a,
   }, "rgba"))
end

Color = ffi.metatype("rig_color_Color", {
   __new = function(ct, first, g, b, a)
      local self = ffi.new(ct)
      assign_color(self, first, g, b, a)
      return self
   end,
   __index = function(self, key)
      local offset = component_offsets[key]
      if offset ~= nil then
         return self.components[offset]
      end
      return color_methods[key]
   end,
   __newindex = function(self, key, value)
      local offset = component_offsets[key]
      if offset == nil then
         rig.raise("unknown color component '" .. tostring(key) .. "'")
      end
      self.components[offset] = normalize_byte(value, tostring(key))
   end,
   __len = function()
      return 4
   end,
   __eq = function(left, right)
      if not ffi.istype(Color, left) or not ffi.istype(Color, right) then
         return false
      end
      return left.r == right.r
         and left.g == right.g
         and left.b == right.b
         and left.a == right.a
   end,
   __tostring = function(self)
      return string.format(
         "Color(%d, %d, %d, %d)",
         self.r,
         self.g,
         self.b,
         self.a
      )
   end,
})

function color_methods:set(first, g, b, a)
   assign_color(self, first, g, b, a)
   return self
end

function color_methods:setf(r, g, b, a)
   assign_rgbaf(self, r, g, b, a)
   return self
end

function color_methods:copy()
   return Color(self)
end

function color_methods:with_alpha(a)
   return Color(self.r, self.g, self.b, a)
end

local function mixed_components(first, second, amount, label)
   local resolved = tonumber(amount)
   if resolved == nil then
      rig.raise(label .. " amount must be numeric")
   end

   if not ffi.istype(Color, first) or not ffi.istype(Color, second) then
      rig.raise(label .. " expects source colors")
   end

   if resolved < 0 then
      resolved = 0
   elseif resolved > 1 then
      resolved = 1
   end

   return first.r + (second.r - first.r) * resolved,
      first.g + (second.g - first.g) * resolved,
      first.b + (second.b - first.b) * resolved,
      first.a + (second.a - first.a) * resolved
end

function color_methods:set_mix(first, second, amount)
   self:set(
      mixed_components(first, second, amount, "color:set_mix")
   )
   return self
end

function color_methods:mix(second, amount)
   return Color(
      mixed_components(self, second, amount, "color:mix")
   )
end

function color_methods:to_rgb()
   return self.r, self.g, self.b
end

function color_methods:to_rgba()
   return self.r, self.g, self.b, self.a
end

function color_methods:to_rgbf()
   return self.r / 255.0,
      self.g / 255.0,
      self.b / 255.0
end

function color_methods:to_rgbaf()
   return self.r / 255.0,
      self.g / 255.0,
      self.b / 255.0,
      self.a / 255.0
end

function color_methods:to(format_name)
   return color_to_format(self, format_name)
end

function color_methods:write_rgba8(buffer, offset)
   if buffer == nil then
      rig.raise("color:write_rgba8 requires a buffer")
   end

   local index = tonumber(offset or 0)
   if index == nil then
      rig.raise("color:write_rgba8 offset must be numeric")
   end
   index = math.floor(index)

   buffer[index] = self.r
   buffer[index + 1] = self.g
   buffer[index + 2] = self.b
   buffer[index + 3] = self.a
   return buffer
end

function color_methods:is_opaque()
   return self.a == 255
end

function M.is(value)
   return ffi.istype(Color, value)
end

function M.rgb(r, g, b)
   return color_from_format({
      r,
      g,
      b,
   }, "rgb")
end

function M.rgba(r, g, b, a)
   return color_from_format({
      r,
      g,
      b,
      a,
   }, "rgba")
end

function M.rgbf(r, g, b)
   return color_from_format({
      r,
      g,
      b,
   }, "rgbf")
end

function M.rgbaf(r, g, b, a)
   return color_from_format({
      r,
      g,
      b,
      a,
   }, "rgbaf")
end

function M.hex(value)
   return color_from_format(value, "hex")
end

function M.u32_rgba(value)
   return color_from_format(value, "u32_rgba")
end

function M.u32_argb(value)
   return color_from_format(value, "u32_argb")
end

function M.u32_abgr(value)
   return color_from_format(value, "u32_abgr")
end

function M.u32_bgra(value)
   return color_from_format(value, "u32_bgra")
end

function M.from(value, format_name)
   if ffi.istype(Color, value) then
      return value:copy()
   end

   if format_name == nil then
      if type(value) == "string" then
         return color_from_format(value, "hex")
      elseif type(value) == "table" then
         return color_from_format(value, "rgba")
      end
      rig.raise("color.from requires a format for this value")
   end

   return color_from_format(value, format_name)
end

M.Color = Color

M.WHITE = M.rgb(255, 255, 255)
M.BLACK = M.rgb(0, 0, 0)
M.TRANSPARENT = M.rgba(0, 0, 0, 0)

return M
