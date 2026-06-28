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

local function assign_from_table(self, value)
   local r, g, b, a = read_color_table(value)

   assign_rgba8(self, r, g, b, a)
end

local color_methods = {}
local Color

local function assign_color(self, first, g, b, a)
   if ffi.istype(Color, first) then
      assign_rgba8(self, first.r, first.g, first.b, first.a)
      return
   end

   if type(first) == "table" then
      assign_from_table(self, first)
      return
   end

   if type(first) == "string" and g == nil and b == nil and a == nil then
      assign_rgba8(self, parse_hex(first))
      return
   end

   assign_rgba8(self, first, g, b, a)
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

local function from_packed(value, order)
   local first, second, third, fourth = unpack_u32(value, order)

   if order == "u32_rgba" then
      return Color(first, second, third, fourth)
   elseif order == "u32_argb" then
      return Color(second, third, fourth, first)
   elseif order == "u32_abgr" then
      return Color(fourth, third, second, first)
   elseif order == "u32_bgra" then
      return Color(third, second, first, fourth)
   end

   rig.raise("unsupported packed color format '" .. tostring(order) .. "'")
end

local function from_table_in_format(value, format_name)
   local r, g, b, a = read_color_table(value)

   if format_name == "rgb" then
      return Color(r, g, b, 255)
   elseif format_name == "rgba" then
      return Color(r, g, b, a)
   elseif format_name == "rgbf" then
      return M.rgbf(r, g, b)
   elseif format_name == "rgbaf" then
      return M.rgbaf(r, g, b, a)
   end

   rig.raise("unsupported table color format '" .. tostring(format_name) .. "'")
end

local function to_color_table(self, format_name)
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
      return self:to_hex_rgb()
   elseif format_name == "hex_rgba" or format_name == "hex" then
      return self:to_hex_rgba()
   elseif format_name == "u32_rgba" then
      return self:to_u32_rgba()
   elseif format_name == "u32_argb" then
      return self:to_u32_argb()
   elseif format_name == "u32_abgr" then
      return self:to_u32_abgr()
   elseif format_name == "u32_bgra" then
      return self:to_u32_bgra()
   end

   rig.raise("unsupported output color format '" .. tostring(format_name) .. "'")
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

function color_methods:set_mix(first, second, amount)
   local resolved = tonumber(amount)
   if resolved == nil then
      rig.raise("color:set_mix amount must be numeric")
   end

   if not ffi.istype(Color, first) or not ffi.istype(Color, second) then
      rig.raise("color:set_mix expects source colors")
   end

   if resolved < 0 then
      resolved = 0
   elseif resolved > 1 then
      resolved = 1
   end

   self:set(
      first.r + (second.r - first.r) * resolved,
      first.g + (second.g - first.g) * resolved,
      first.b + (second.b - first.b) * resolved,
      first.a + (second.a - first.a) * resolved
   )
   return self
end

function color_methods:to_rgb()
   return self.r, self.g, self.b
end

function color_methods:to_rgba()
   return self.r, self.g, self.b, self.a
end

function color_methods:unpack()
   return self:to_rgba()
end

function color_methods:unpack8()
   return self:unpack()
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

function color_methods:unpackf()
   return self:to_rgbaf()
end

function color_methods:to_rgb_table()
   return {
      self.r,
      self.g,
      self.b,
   }
end

function color_methods:to_rgba_table()
   return {
      self.r,
      self.g,
      self.b,
      self.a,
   }
end

function color_methods:to_rgbf_table()
   return {
      self.r / 255.0,
      self.g / 255.0,
      self.b / 255.0,
   }
end

function color_methods:to_rgbaf_table()
   return {
      self.r / 255.0,
      self.g / 255.0,
      self.b / 255.0,
      self.a / 255.0,
   }
end

function color_methods:to_table()
   return self:to_rgba_table()
end

function color_methods:to_float_table()
   return self:to_rgbaf_table()
end

function color_methods:to_hex_rgb()
   return string.format("#%02X%02X%02X", self.r, self.g, self.b)
end

function color_methods:to_hex_rgba()
   return string.format("#%02X%02X%02X%02X", self.r, self.g, self.b, self.a)
end

function color_methods:hex_rgb()
   return self:to_hex_rgb()
end

function color_methods:hex_rgba()
   return self:to_hex_rgba()
end

function color_methods:to_u32_rgba()
   return pack_components(self.r, self.g, self.b, self.a)
end

function color_methods:to_u32_argb()
   return pack_components(self.a, self.r, self.g, self.b)
end

function color_methods:to_u32_abgr()
   return pack_components(self.a, self.b, self.g, self.r)
end

function color_methods:to_u32_bgra()
   return pack_components(self.b, self.g, self.r, self.a)
end

function color_methods:u32_rgba()
   return self:to_u32_rgba()
end

function color_methods:u32_argb()
   return self:to_u32_argb()
end

function color_methods:u32_abgr()
   return self:to_u32_abgr()
end

function color_methods:u32_bgra()
   return self:to_u32_bgra()
end

function color_methods:to(format_name)
   return to_color_table(self, format_name)
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
   return Color(r, g, b, 255)
end

function M.from_rgb(r, g, b)
   return M.rgb(r, g, b)
end

function M.rgba(r, g, b, a)
   return Color(r, g, b, a)
end

function M.from_rgba(r, g, b, a)
   return M.rgba(r, g, b, a)
end

function M.rgbf(r, g, b)
   return Color(
      normalize_unit(r, "r"),
      normalize_unit(g, "g"),
      normalize_unit(b, "b"),
      255
   )
end

function M.from_rgbf(r, g, b)
   return M.rgbf(r, g, b)
end

function M.rgbaf(r, g, b, a)
   return Color(
      normalize_unit(r, "r"),
      normalize_unit(g, "g"),
      normalize_unit(b, "b"),
      normalize_unit(a, "a", 1)
   )
end

function M.from_rgbaf(r, g, b, a)
   return M.rgbaf(r, g, b, a)
end

function M.hex(value)
   return Color(value)
end

function M.from_hex(value)
   return M.hex(value)
end

function M.u32_rgba(value)
   return from_packed(value, "u32_rgba")
end

function M.from_u32_rgba(value)
   return M.u32_rgba(value)
end

function M.u32_argb(value)
   return from_packed(value, "u32_argb")
end

function M.from_u32_argb(value)
   return M.u32_argb(value)
end

function M.u32_abgr(value)
   return from_packed(value, "u32_abgr")
end

function M.from_u32_abgr(value)
   return M.u32_abgr(value)
end

function M.u32_bgra(value)
   return from_packed(value, "u32_bgra")
end

function M.from_u32_bgra(value)
   return M.u32_bgra(value)
end

function M.from(value, format_name)
   if ffi.istype(Color, value) then
      return value:copy()
   end

   if format_name == nil then
      if type(value) == "string" then
         return M.from_hex(value)
      elseif type(value) == "table" then
         return from_table_in_format(value, "rgba")
      end
      rig.raise("color.from requires a format for this value")
   end

   if format_name == "rgb"
      or format_name == "rgba"
      or format_name == "rgbf"
      or format_name == "rgbaf"
   then
      if type(value) ~= "table" then
         rig.raise("color.from(..., '" .. format_name .. "') expects a table")
      end
      return from_table_in_format(value, format_name)
   elseif format_name == "hex"
      or format_name == "hex_rgb"
      or format_name == "hex_rgba"
   then
      return M.from_hex(value)
   elseif format_name == "u32_rgba" then
      return M.from_u32_rgba(value)
   elseif format_name == "u32_argb" then
      return M.from_u32_argb(value)
   elseif format_name == "u32_abgr" then
      return M.from_u32_abgr(value)
   elseif format_name == "u32_bgra" then
      return M.from_u32_bgra(value)
   end

   rig.raise("unsupported input color format '" .. tostring(format_name) .. "'")
end

M.Color = Color
M.WHITE = M.rgb(255, 255, 255)
M.BLACK = M.rgb(0, 0, 0)
M.TRANSPARENT = M.rgba(0, 0, 0, 0)

return M
