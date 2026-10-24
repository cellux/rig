local M = ... or {}
local app = require("app")
local bit = bit
local color = require("color")
local font = require("font")
local ffi = require("ffi")
local glx = require("glx")
local graphics = require("graphics")
local rig = require("rig")
local runtime = require("runtime")
local scene = require("scene")
local schema = require("schema")
local sdl3 = require("sdl3")
require("gl")
local mesh = require("mesh")
local render = require("render")
local shader = require("shader")
require("time")

--[ error handling ]--

function M.get_error(fallback)
   local err = sdl3.GetError()
   if err == nil or err == ffi.NULL or err[0] == 0 then
      return fallback or "unknown SDL error"
   end
   return ffi.string(err)
end

--[ utilities ]--

function M.free(ptr)
   if ptr ~= nil and ptr ~= ffi.NULL then
      sdl3.free(ffi.cast("void *", ptr))
   end
end

--[ Properties ]--

local Properties = rig.Class()

local properties_id_schema = schema.optional(
   schema.one_of({
      schema.number(),
      schema.cdata("SDL_PropertiesID"),
      schema.instance_of(Properties, "sdl3x.Properties"):extract("id"),
   }, "a number, cdata SDL_PropertiesID, or sdl3x.Properties"),
   0
)

function M.normalize_properties_id(props)
   return properties_id_schema(props, "props")
end

local function ensure_properties(properties)
   if not Properties:is_instance(properties) then
      rig.raise("sdl3x.Properties operation expects an sdl3x.Properties instance")
   end
   if properties._released then
      rig.raise("sdl3x.Properties has been released")
   end
end

local function set_property_value(properties, name, value)
   if type(name) ~= "string" or name == "" then
      rig.raise("sdl3x.Properties expects property names to be non-empty strings")
   end

   if value == nil then
      if not sdl3.ClearProperty(properties.id, name) then
         rig.raise(("failed to clear property '%s': %s"):format(
            name,
            M.get_error()
         ))
      end
      properties._values[name] = nil
      return properties
   end

   local ok = nil
   local value_type = type(value)
   if value_type == "boolean" then
      ok = sdl3.SetBooleanProperty(properties.id, name, value)
   elseif value_type == "number" then
      if value == math.floor(value) then
         ok = sdl3.SetNumberProperty(properties.id, name, value)
      else
         ok = sdl3.SetFloatProperty(properties.id, name, value)
      end
   elseif value_type == "string" then
      ok = sdl3.SetStringProperty(properties.id, name, value)
   elseif value_type == "cdata" then
      ok = sdl3.SetPointerProperty(properties.id, name, ffi.cast("void *", value))
   else
      rig.raise(
         ("unsupported SDL property value type for '%s': %s"):format(
            name,
            value_type
         )
      )
   end

   if not ok then
      rig.raise(("failed to set property '%s': %s"):format(
         name,
         M.get_error()
      ))
   end

   properties._values[name] = value
   return properties
end

M.Properties = Properties

function Properties:init(values)
   if values ~= nil and type(values) ~= "table" then
      rig.raise("sdl3x.Properties expects a table if initialized with values")
   end

   self.id = sdl3.CreateProperties()
   if self.id == 0 then
      rig.raise("failed to create SDL properties: " .. M.get_error())
   end

   self._released = false
   self._values = {}

   local initial_values = values
   if Properties:is_instance(values) then
      initial_values = values._values
   end

   local ok, err = pcall(function()
      if initial_values ~= nil then
         self:merge(initial_values)
      end
   end)
   if not ok then
      self:release()
      rig.raise(err)
   end
end

function Properties:set(name, value)
   ensure_properties(self)
   return set_property_value(self, name, value)
end

function Properties:clear(name)
   return self:set(name, nil)
end

function Properties:merge(values)
   ensure_properties(self)

   local source = values
   if Properties:is_instance(values) then
      source = values._values
   elseif type(values) ~= "table" then
      rig.raise("sdl3x.Properties:merge expects a table or sdl3x.Properties")
   end

   for key, value in pairs(source) do
      set_property_value(self, key, value)
   end
   return self
end

function Properties:get(name, default)
   ensure_properties(self)
   local value = self._values[name]
   if value == nil then
      return default
   end
   return value
end

function Properties:has(name)
   ensure_properties(self)
   return self._values[name] ~= nil
end

function Properties:to_table()
   ensure_properties(self)
   return rig.shallow_copy(self._values)
end

function Properties:clone()
   ensure_properties(self)
   return Properties(self._values)
end

function Properties:release()
   if self._released then
      return
   end

   if self.id ~= nil and self.id ~= 0 then
      sdl3.DestroyProperties(self.id)
   end

   self.id = 0
   self._values = {}
   self._released = true
end

--[ Window ]--

local Window = rig.Class()

local function ensure_window(window)
   if not Window:is_instance(window) then
      rig.raise("sdl3x.Window operation expects an sdl3x.Window instance")
   end
   if window._released then
      rig.raise("sdl3x.Window has been released")
   end
end

M.Window = Window

local DEFAULT_WINDOW_WIDTH = 640
local DEFAULT_WINDOW_HEIGHT = 360

local default_window_props = {
   [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "rig",
}

local function resolve_default_window_size()
   local default_width = DEFAULT_WINDOW_WIDTH
   local default_height = DEFAULT_WINDOW_HEIGHT
   local primary_display = sdl3.GetPrimaryDisplay()

   if primary_display ~= nil and primary_display ~= 0 then
      local usable_bounds = ffi.new("SDL_Rect[1]")
      if sdl3.GetDisplayUsableBounds(primary_display, usable_bounds) then
         default_width = math.max(
            1,
            math.floor((tonumber(usable_bounds[0].w) or default_width) * 0.75)
         )
         default_height = math.max(
            1,
            math.floor((tonumber(usable_bounds[0].h) or default_height) * 0.75)
         )
      end
   end

   return default_width, default_height
end

local function build_window_properties(options)
   local props = Properties(default_window_props)
   local ok, result_or_err = pcall(function()
      local window_props = options.window_props
      if window_props ~= nil then
         props:merge(window_props)
      end

      local width_key = sdl3.PROP_WINDOW_CREATE_WIDTH_NUMBER
      local height_key = sdl3.PROP_WINDOW_CREATE_HEIGHT_NUMBER
      if not props:has(width_key) or not props:has(height_key) then
         local default_width, default_height = resolve_default_window_size()
         if not props:has(width_key) then
            props:set(width_key, default_width)
         end
         if not props:has(height_key) then
            props:set(height_key, default_height)
         end
      end
   end)

   if not ok then
      props:release()
      return nil, result_or_err
   end

   return props
end

function Window:init(options)
   if options ~= nil and type(options) ~= "table" then
      rig.raise("sdl3x.Window expects a table if initialized with options")
   end

   local props, props_err = build_window_properties(options or {})
   if props == nil then
      rig.raise(props_err)
   end

   local window_ptr = sdl3.CreateWindowWithProperties(props.id)
   props:release()

   if window_ptr == nil then
      rig.raise("failed to create SDL window: " .. M.get_error())
   end

   self.ptr = window_ptr
   self._released = false
end

function Window:get_size()
   ensure_window(self)

   local width_out = ffi.new("int[1]")
   local height_out = ffi.new("int[1]")
   if not sdl3.GetWindowSize(self.ptr, width_out, height_out) then
      rig.raise("failed to query window size: " .. M.get_error())
   end

   return tonumber(width_out[0]) or 0,
      tonumber(height_out[0]) or 0
end

function Window:get_size_in_pixels()
   ensure_window(self)

   local width_out = ffi.new("int[1]")
   local height_out = ffi.new("int[1]")
   if not sdl3.GetWindowSizeInPixels(self.ptr, width_out, height_out) then
      rig.raise("failed to query window size in pixels: " .. M.get_error())
   end

   return tonumber(width_out[0]) or 0,
      tonumber(height_out[0]) or 0
end

function Window:set_fullscreen(enabled)
   ensure_window(self)
   if type(enabled) ~= "boolean" then
      rig.raise("sdl3x.Window:set_fullscreen expects enabled to be a boolean")
   end

   if not sdl3.SetWindowFullscreen(self.ptr, enabled) then
      rig.raise("failed to set window fullscreen: " .. M.get_error())
   end

   return enabled
end

function Window:sync()
   ensure_window(self)

   if not sdl3.SyncWindow(self.ptr) then
      rig.raise("failed to synchronize window state: " .. M.get_error())
   end
end

function Window:release()
   if self._released then
      return
   end

   if self.ptr ~= nil and self.ptr ~= ffi.NULL then
      sdl3.DestroyWindow(self.ptr)
   end

   self.ptr = nil
   self._released = true
end

--[ GPUShader ]--

local GPUShader = rig.Class()
M.GPUShader = GPUShader

local function ensure_gpu_shader(shader)
   if not GPUShader:is_instance(shader) then
      rig.raise("sdl3x.GPUShader operation expects an sdl3x.GPUShader instance")
   end
end

local function ensure_gpu_shader_live(shader)
   ensure_gpu_shader(shader)
   if shader._released then
      rig.raise("sdl3x.GPUShader has been released")
   end
end

M.GPUVertexInputRate = schema.named_value(
   {
      vertex = sdl3.GPU_VERTEXINPUTRATE_VERTEX,
      instance = sdl3.GPU_VERTEXINPUTRATE_INSTANCE,
   },
   "vertex input rate"
)

M.GPUVertexElementFormat = schema.named_value(
   {
      INVALID = sdl3.GPU_VERTEXELEMENTFORMAT_INVALID,
      INT = sdl3.GPU_VERTEXELEMENTFORMAT_INT,
      INT2 = sdl3.GPU_VERTEXELEMENTFORMAT_INT2,
      INT3 = sdl3.GPU_VERTEXELEMENTFORMAT_INT3,
      INT4 = sdl3.GPU_VERTEXELEMENTFORMAT_INT4,
      UINT = sdl3.GPU_VERTEXELEMENTFORMAT_UINT,
      UINT2 = sdl3.GPU_VERTEXELEMENTFORMAT_UINT2,
      UINT3 = sdl3.GPU_VERTEXELEMENTFORMAT_UINT3,
      UINT4 = sdl3.GPU_VERTEXELEMENTFORMAT_UINT4,
      FLOAT = sdl3.GPU_VERTEXELEMENTFORMAT_FLOAT,
      FLOAT2 = sdl3.GPU_VERTEXELEMENTFORMAT_FLOAT2,
      FLOAT3 = sdl3.GPU_VERTEXELEMENTFORMAT_FLOAT3,
      FLOAT4 = sdl3.GPU_VERTEXELEMENTFORMAT_FLOAT4,
      BYTE2 = sdl3.GPU_VERTEXELEMENTFORMAT_BYTE2,
      BYTE4 = sdl3.GPU_VERTEXELEMENTFORMAT_BYTE4,
      UBYTE2 = sdl3.GPU_VERTEXELEMENTFORMAT_UBYTE2,
      UBYTE4 = sdl3.GPU_VERTEXELEMENTFORMAT_UBYTE4,
      BYTE2_NORM = sdl3.GPU_VERTEXELEMENTFORMAT_BYTE2_NORM,
      BYTE4_NORM = sdl3.GPU_VERTEXELEMENTFORMAT_BYTE4_NORM,
      UBYTE2_NORM = sdl3.GPU_VERTEXELEMENTFORMAT_UBYTE2_NORM,
      UBYTE4_NORM = sdl3.GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM,
      SHORT2 = sdl3.GPU_VERTEXELEMENTFORMAT_SHORT2,
      SHORT4 = sdl3.GPU_VERTEXELEMENTFORMAT_SHORT4,
      USHORT2 = sdl3.GPU_VERTEXELEMENTFORMAT_USHORT2,
      USHORT4 = sdl3.GPU_VERTEXELEMENTFORMAT_USHORT4,
      SHORT2_NORM = sdl3.GPU_VERTEXELEMENTFORMAT_SHORT2_NORM,
      SHORT4_NORM = sdl3.GPU_VERTEXELEMENTFORMAT_SHORT4_NORM,
      USHORT2_NORM = sdl3.GPU_VERTEXELEMENTFORMAT_USHORT2_NORM,
      USHORT4_NORM = sdl3.GPU_VERTEXELEMENTFORMAT_USHORT4_NORM,
      HALF2 = sdl3.GPU_VERTEXELEMENTFORMAT_HALF2,
      HALF4 = sdl3.GPU_VERTEXELEMENTFORMAT_HALF4,
   },
   "vertex element format"
)

M.GPUShaderFormat = schema.named_value(
   {
      INVALID = sdl3.GPU_SHADERFORMAT_INVALID,
      PRIVATE = sdl3.GPU_SHADERFORMAT_PRIVATE,
      SPIRV = sdl3.GPU_SHADERFORMAT_SPIRV,
      DXBC = sdl3.GPU_SHADERFORMAT_DXBC,
      DXIL = sdl3.GPU_SHADERFORMAT_DXIL,
      MSL = sdl3.GPU_SHADERFORMAT_MSL,
      METALLIB = sdl3.GPU_SHADERFORMAT_METALLIB,
   },
   "GPU shader format"
)

M.GPUShaderStage = schema.named_value(
   {
      VERTEX = sdl3.GPU_SHADERSTAGE_VERTEX,
      FRAGMENT = sdl3.GPU_SHADERSTAGE_FRAGMENT,
   },
   "GPU shader stage"
)

M.GPUPrimitiveType = schema.named_value(
   {
      TRIANGLELIST = sdl3.GPU_PRIMITIVETYPE_TRIANGLELIST,
      TRIANGLESTRIP = sdl3.GPU_PRIMITIVETYPE_TRIANGLESTRIP,
      LINELIST = sdl3.GPU_PRIMITIVETYPE_LINELIST,
      LINESTRIP = sdl3.GPU_PRIMITIVETYPE_LINESTRIP,
      POINTLIST = sdl3.GPU_PRIMITIVETYPE_POINTLIST,
   },
   "GPU primitive type"
)

M.GPUSampleCount = schema.named_value(
   {
      ["1"] = sdl3.GPU_SAMPLECOUNT_1,
      ["2"] = sdl3.GPU_SAMPLECOUNT_2,
      ["4"] = sdl3.GPU_SAMPLECOUNT_4,
      ["8"] = sdl3.GPU_SAMPLECOUNT_8,
   },
   "GPU sample count"
)

M.GPUFillMode = schema.named_value(
   {
      FILL = sdl3.GPU_FILLMODE_FILL,
      LINE = sdl3.GPU_FILLMODE_LINE,
   },
   "GPU fill mode"
)

M.GPUCullMode = schema.named_value(
   {
      NONE = sdl3.GPU_CULLMODE_NONE,
      FRONT = sdl3.GPU_CULLMODE_FRONT,
      BACK = sdl3.GPU_CULLMODE_BACK,
   },
   "GPU cull mode"
)

M.GPUFrontFace = schema.named_value(
   {
      COUNTER_CLOCKWISE = sdl3.GPU_FRONTFACE_COUNTER_CLOCKWISE,
      CLOCKWISE = sdl3.GPU_FRONTFACE_CLOCKWISE,
   },
   "GPU front face"
)

M.GPUCompareOp = schema.named_value(
   {
      INVALID = sdl3.GPU_COMPAREOP_INVALID,
      NEVER = sdl3.GPU_COMPAREOP_NEVER,
      LESS = sdl3.GPU_COMPAREOP_LESS,
      EQUAL = sdl3.GPU_COMPAREOP_EQUAL,
      LESS_OR_EQUAL = sdl3.GPU_COMPAREOP_LESS_OR_EQUAL,
      GREATER = sdl3.GPU_COMPAREOP_GREATER,
      NOT_EQUAL = sdl3.GPU_COMPAREOP_NOT_EQUAL,
      GREATER_OR_EQUAL = sdl3.GPU_COMPAREOP_GREATER_OR_EQUAL,
      ALWAYS = sdl3.GPU_COMPAREOP_ALWAYS,
   },
   "GPU compare op"
)

M.GPUStencilOp = schema.named_value(
   {
      INVALID = sdl3.GPU_STENCILOP_INVALID,
      KEEP = sdl3.GPU_STENCILOP_KEEP,
      ZERO = sdl3.GPU_STENCILOP_ZERO,
      REPLACE = sdl3.GPU_STENCILOP_REPLACE,
      INCREMENT_AND_CLAMP = sdl3.GPU_STENCILOP_INCREMENT_AND_CLAMP,
      DECREMENT_AND_CLAMP = sdl3.GPU_STENCILOP_DECREMENT_AND_CLAMP,
      INVERT = sdl3.GPU_STENCILOP_INVERT,
      INCREMENT_AND_WRAP = sdl3.GPU_STENCILOP_INCREMENT_AND_WRAP,
      DECREMENT_AND_WRAP = sdl3.GPU_STENCILOP_DECREMENT_AND_WRAP,
   },
   "GPU stencil op"
)

M.GPUBlendOp = schema.named_value(
   {
      INVALID = sdl3.GPU_BLENDOP_INVALID,
      ADD = sdl3.GPU_BLENDOP_ADD,
      SUBTRACT = sdl3.GPU_BLENDOP_SUBTRACT,
      REVERSE_SUBTRACT = sdl3.GPU_BLENDOP_REVERSE_SUBTRACT,
      MIN = sdl3.GPU_BLENDOP_MIN,
      MAX = sdl3.GPU_BLENDOP_MAX,
   },
   "GPU blend op"
)

M.GPUBlendFactor = schema.named_value(
   {
      INVALID = sdl3.GPU_BLENDFACTOR_INVALID,
      ZERO = sdl3.GPU_BLENDFACTOR_ZERO,
      ONE = sdl3.GPU_BLENDFACTOR_ONE,
      SRC_COLOR = sdl3.GPU_BLENDFACTOR_SRC_COLOR,
      ONE_MINUS_SRC_COLOR = sdl3.GPU_BLENDFACTOR_ONE_MINUS_SRC_COLOR,
      DST_COLOR = sdl3.GPU_BLENDFACTOR_DST_COLOR,
      ONE_MINUS_DST_COLOR = sdl3.GPU_BLENDFACTOR_ONE_MINUS_DST_COLOR,
      SRC_ALPHA = sdl3.GPU_BLENDFACTOR_SRC_ALPHA,
      ONE_MINUS_SRC_ALPHA = sdl3.GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
      DST_ALPHA = sdl3.GPU_BLENDFACTOR_DST_ALPHA,
      ONE_MINUS_DST_ALPHA = sdl3.GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
      CONSTANT_COLOR = sdl3.GPU_BLENDFACTOR_CONSTANT_COLOR,
      ONE_MINUS_CONSTANT_COLOR = sdl3.GPU_BLENDFACTOR_ONE_MINUS_CONSTANT_COLOR,
      SRC_ALPHA_SATURATE = sdl3.GPU_BLENDFACTOR_SRC_ALPHA_SATURATE,
   },
   "GPU blend factor"
)

local GPU_COLOR_COMPONENT_MASK = bit.bor(
   sdl3.GPU_COLORCOMPONENT_R,
   sdl3.GPU_COLORCOMPONENT_G,
   sdl3.GPU_COLORCOMPONENT_B,
   sdl3.GPU_COLORCOMPONENT_A
)

M.GPUColorComponentFlags = schema.integer():non_negative():where(
   "GPU color component flags",
   function(value)
      return bit.band(value, GPU_COLOR_COMPONENT_MASK) == value
   end
)

local GPU_BUFFER_USAGE_MASK = bit.bor(
   sdl3.GPU_BUFFERUSAGE_VERTEX,
   sdl3.GPU_BUFFERUSAGE_INDEX,
   sdl3.GPU_BUFFERUSAGE_INDIRECT,
   sdl3.GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
   sdl3.GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ,
   sdl3.GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE
)

M.GPUBufferUsageFlags = schema.integer():positive():where(
   "GPU buffer usage flags",
   function(value)
      return bit.band(value, GPU_BUFFER_USAGE_MASK) == value
   end
)

M.GPUTextureFormat = schema.named_value({
   A8_UNORM = sdl3.GPU_TEXTUREFORMAT_A8_UNORM,
   ASTC_10x10_FLOAT = sdl3.GPU_TEXTUREFORMAT_ASTC_10x10_FLOAT,
   ASTC_10x10_UNORM = sdl3.GPU_TEXTUREFORMAT_ASTC_10x10_UNORM,
   ASTC_10x10_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_ASTC_10x10_UNORM_SRGB,
   ASTC_10x5_FLOAT = sdl3.GPU_TEXTUREFORMAT_ASTC_10x5_FLOAT,
   ASTC_10x5_UNORM = sdl3.GPU_TEXTUREFORMAT_ASTC_10x5_UNORM,
   ASTC_10x5_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_ASTC_10x5_UNORM_SRGB,
   ASTC_10x6_FLOAT = sdl3.GPU_TEXTUREFORMAT_ASTC_10x6_FLOAT,
   ASTC_10x6_UNORM = sdl3.GPU_TEXTUREFORMAT_ASTC_10x6_UNORM,
   ASTC_10x6_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_ASTC_10x6_UNORM_SRGB,
   ASTC_10x8_FLOAT = sdl3.GPU_TEXTUREFORMAT_ASTC_10x8_FLOAT,
   ASTC_10x8_UNORM = sdl3.GPU_TEXTUREFORMAT_ASTC_10x8_UNORM,
   ASTC_10x8_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_ASTC_10x8_UNORM_SRGB,
   ASTC_12x10_FLOAT = sdl3.GPU_TEXTUREFORMAT_ASTC_12x10_FLOAT,
   ASTC_12x10_UNORM = sdl3.GPU_TEXTUREFORMAT_ASTC_12x10_UNORM,
   ASTC_12x10_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_ASTC_12x10_UNORM_SRGB,
   ASTC_12x12_FLOAT = sdl3.GPU_TEXTUREFORMAT_ASTC_12x12_FLOAT,
   ASTC_12x12_UNORM = sdl3.GPU_TEXTUREFORMAT_ASTC_12x12_UNORM,
   ASTC_12x12_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_ASTC_12x12_UNORM_SRGB,
   ASTC_4x4_FLOAT = sdl3.GPU_TEXTUREFORMAT_ASTC_4x4_FLOAT,
   ASTC_4x4_UNORM = sdl3.GPU_TEXTUREFORMAT_ASTC_4x4_UNORM,
   ASTC_4x4_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_ASTC_4x4_UNORM_SRGB,
   ASTC_5x4_FLOAT = sdl3.GPU_TEXTUREFORMAT_ASTC_5x4_FLOAT,
   ASTC_5x4_UNORM = sdl3.GPU_TEXTUREFORMAT_ASTC_5x4_UNORM,
   ASTC_5x4_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_ASTC_5x4_UNORM_SRGB,
   ASTC_5x5_FLOAT = sdl3.GPU_TEXTUREFORMAT_ASTC_5x5_FLOAT,
   ASTC_5x5_UNORM = sdl3.GPU_TEXTUREFORMAT_ASTC_5x5_UNORM,
   ASTC_5x5_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_ASTC_5x5_UNORM_SRGB,
   ASTC_6x5_FLOAT = sdl3.GPU_TEXTUREFORMAT_ASTC_6x5_FLOAT,
   ASTC_6x5_UNORM = sdl3.GPU_TEXTUREFORMAT_ASTC_6x5_UNORM,
   ASTC_6x5_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_ASTC_6x5_UNORM_SRGB,
   ASTC_6x6_FLOAT = sdl3.GPU_TEXTUREFORMAT_ASTC_6x6_FLOAT,
   ASTC_6x6_UNORM = sdl3.GPU_TEXTUREFORMAT_ASTC_6x6_UNORM,
   ASTC_6x6_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_ASTC_6x6_UNORM_SRGB,
   ASTC_8x5_FLOAT = sdl3.GPU_TEXTUREFORMAT_ASTC_8x5_FLOAT,
   ASTC_8x5_UNORM = sdl3.GPU_TEXTUREFORMAT_ASTC_8x5_UNORM,
   ASTC_8x5_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_ASTC_8x5_UNORM_SRGB,
   ASTC_8x6_FLOAT = sdl3.GPU_TEXTUREFORMAT_ASTC_8x6_FLOAT,
   ASTC_8x6_UNORM = sdl3.GPU_TEXTUREFORMAT_ASTC_8x6_UNORM,
   ASTC_8x6_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_ASTC_8x6_UNORM_SRGB,
   ASTC_8x8_FLOAT = sdl3.GPU_TEXTUREFORMAT_ASTC_8x8_FLOAT,
   ASTC_8x8_UNORM = sdl3.GPU_TEXTUREFORMAT_ASTC_8x8_UNORM,
   ASTC_8x8_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_ASTC_8x8_UNORM_SRGB,
   B4G4R4A4_UNORM = sdl3.GPU_TEXTUREFORMAT_B4G4R4A4_UNORM,
   B5G5R5A1_UNORM = sdl3.GPU_TEXTUREFORMAT_B5G5R5A1_UNORM,
   B5G6R5_UNORM = sdl3.GPU_TEXTUREFORMAT_B5G6R5_UNORM,
   B8G8R8A8_UNORM = sdl3.GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
   B8G8R8A8_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_B8G8R8A8_UNORM_SRGB,
   BC1_RGBA_UNORM = sdl3.GPU_TEXTUREFORMAT_BC1_RGBA_UNORM,
   BC1_RGBA_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_BC1_RGBA_UNORM_SRGB,
   BC2_RGBA_UNORM = sdl3.GPU_TEXTUREFORMAT_BC2_RGBA_UNORM,
   BC2_RGBA_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_BC2_RGBA_UNORM_SRGB,
   BC3_RGBA_UNORM = sdl3.GPU_TEXTUREFORMAT_BC3_RGBA_UNORM,
   BC3_RGBA_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_BC3_RGBA_UNORM_SRGB,
   BC4_R_UNORM = sdl3.GPU_TEXTUREFORMAT_BC4_R_UNORM,
   BC5_RG_UNORM = sdl3.GPU_TEXTUREFORMAT_BC5_RG_UNORM,
   BC6H_RGB_FLOAT = sdl3.GPU_TEXTUREFORMAT_BC6H_RGB_FLOAT,
   BC6H_RGB_UFLOAT = sdl3.GPU_TEXTUREFORMAT_BC6H_RGB_UFLOAT,
   BC7_RGBA_UNORM = sdl3.GPU_TEXTUREFORMAT_BC7_RGBA_UNORM,
   BC7_RGBA_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_BC7_RGBA_UNORM_SRGB,
   D16_UNORM = sdl3.GPU_TEXTUREFORMAT_D16_UNORM,
   D24_UNORM = sdl3.GPU_TEXTUREFORMAT_D24_UNORM,
   D24_UNORM_S8_UINT = sdl3.GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT,
   D32_FLOAT = sdl3.GPU_TEXTUREFORMAT_D32_FLOAT,
   D32_FLOAT_S8_UINT = sdl3.GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT,
   INVALID = sdl3.GPU_TEXTUREFORMAT_INVALID,
   R10G10B10A2_UNORM = sdl3.GPU_TEXTUREFORMAT_R10G10B10A2_UNORM,
   R11G11B10_UFLOAT = sdl3.GPU_TEXTUREFORMAT_R11G11B10_UFLOAT,
   R16_FLOAT = sdl3.GPU_TEXTUREFORMAT_R16_FLOAT,
   R16_INT = sdl3.GPU_TEXTUREFORMAT_R16_INT,
   R16_SNORM = sdl3.GPU_TEXTUREFORMAT_R16_SNORM,
   R16_UINT = sdl3.GPU_TEXTUREFORMAT_R16_UINT,
   R16_UNORM = sdl3.GPU_TEXTUREFORMAT_R16_UNORM,
   R16G16_FLOAT = sdl3.GPU_TEXTUREFORMAT_R16G16_FLOAT,
   R16G16_INT = sdl3.GPU_TEXTUREFORMAT_R16G16_INT,
   R16G16_SNORM = sdl3.GPU_TEXTUREFORMAT_R16G16_SNORM,
   R16G16_UINT = sdl3.GPU_TEXTUREFORMAT_R16G16_UINT,
   R16G16_UNORM = sdl3.GPU_TEXTUREFORMAT_R16G16_UNORM,
   R16G16B16A16_FLOAT = sdl3.GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT,
   R16G16B16A16_INT = sdl3.GPU_TEXTUREFORMAT_R16G16B16A16_INT,
   R16G16B16A16_SNORM = sdl3.GPU_TEXTUREFORMAT_R16G16B16A16_SNORM,
   R16G16B16A16_UINT = sdl3.GPU_TEXTUREFORMAT_R16G16B16A16_UINT,
   R16G16B16A16_UNORM = sdl3.GPU_TEXTUREFORMAT_R16G16B16A16_UNORM,
   R32_FLOAT = sdl3.GPU_TEXTUREFORMAT_R32_FLOAT,
   R32_INT = sdl3.GPU_TEXTUREFORMAT_R32_INT,
   R32_UINT = sdl3.GPU_TEXTUREFORMAT_R32_UINT,
   R32G32_FLOAT = sdl3.GPU_TEXTUREFORMAT_R32G32_FLOAT,
   R32G32_INT = sdl3.GPU_TEXTUREFORMAT_R32G32_INT,
   R32G32_UINT = sdl3.GPU_TEXTUREFORMAT_R32G32_UINT,
   R32G32B32A32_FLOAT = sdl3.GPU_TEXTUREFORMAT_R32G32B32A32_FLOAT,
   R32G32B32A32_INT = sdl3.GPU_TEXTUREFORMAT_R32G32B32A32_INT,
   R32G32B32A32_UINT = sdl3.GPU_TEXTUREFORMAT_R32G32B32A32_UINT,
   R8_INT = sdl3.GPU_TEXTUREFORMAT_R8_INT,
   R8_SNORM = sdl3.GPU_TEXTUREFORMAT_R8_SNORM,
   R8_UINT = sdl3.GPU_TEXTUREFORMAT_R8_UINT,
   R8_UNORM = sdl3.GPU_TEXTUREFORMAT_R8_UNORM,
   R8G8_INT = sdl3.GPU_TEXTUREFORMAT_R8G8_INT,
   R8G8_SNORM = sdl3.GPU_TEXTUREFORMAT_R8G8_SNORM,
   R8G8_UINT = sdl3.GPU_TEXTUREFORMAT_R8G8_UINT,
   R8G8_UNORM = sdl3.GPU_TEXTUREFORMAT_R8G8_UNORM,
   R8G8B8A8_INT = sdl3.GPU_TEXTUREFORMAT_R8G8B8A8_INT,
   R8G8B8A8_SNORM = sdl3.GPU_TEXTUREFORMAT_R8G8B8A8_SNORM,
   R8G8B8A8_UINT = sdl3.GPU_TEXTUREFORMAT_R8G8B8A8_UINT,
   R8G8B8A8_UNORM = sdl3.GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
   R8G8B8A8_UNORM_SRGB = sdl3.GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB,
}, "GPU texture format")

local Uint8Value = schema.integer():non_negative():max(255)

local GPUVertexBufferDescription = schema.ffi.struct(
   "SDL_GPUVertexBufferDescription",
   {
      slot = schema.integer():non_negative(),
      pitch = schema.integer():non_negative(),
      input_rate = M.GPUVertexInputRate:optional(
         sdl3.GPU_VERTEXINPUTRATE_VERTEX
      ),
      instance_step_rate = schema.integer():non_negative():optional(0),
   }
)

local GPUVertexAttributeSource = schema.record({
   location = schema.integer():non_negative(),
   buffer_slot = schema.integer():non_negative():optional(),
   slot = schema.integer():non_negative():optional(),
   format = M.GPUVertexElementFormat,
   offset = schema.integer():non_negative(),
}):transform(function(value)
   value.buffer_slot = value.buffer_slot or value.slot or 0
   value.slot = nil
   return value
end)

local GPUVertexAttribute = schema.ffi.struct("SDL_GPUVertexAttribute", {
   location = schema.integer():non_negative(),
   buffer_slot = schema.integer():non_negative():optional(0),
   format = M.GPUVertexElementFormat,
   offset = schema.integer():non_negative(),
})

local GPUColorTargetBlendState = schema.ffi.struct(
   "SDL_GPUColorTargetBlendState",
   {
      src_color_blendfactor = M.GPUBlendFactor:optional(),
      dst_color_blendfactor = M.GPUBlendFactor:optional(),
      color_blend_op = M.GPUBlendOp:optional(),
      src_alpha_blendfactor = M.GPUBlendFactor:optional(),
      dst_alpha_blendfactor = M.GPUBlendFactor:optional(),
      alpha_blend_op = M.GPUBlendOp:optional(),
      color_write_mask = M.GPUColorComponentFlags:optional(),
      enable_blend = schema.boolean():optional(),
      enable_color_write_mask = schema.boolean():optional(),
   }
)

local GPUColorTargetDescription = schema.ffi.struct(
   "SDL_GPUColorTargetDescription",
   {
      format = M.GPUTextureFormat,
      blend_state = GPUColorTargetBlendState:optional(),
   }
)

local GPUVertexBufferDescriptions = schema.ffi.array(
   "SDL_GPUVertexBufferDescription",
   GPUVertexBufferDescription
)

local GPUVertexAttributes = schema.ffi.array(
   "SDL_GPUVertexAttribute",
   GPUVertexAttribute
)

local GPUColorTargetDescriptions = schema.ffi.array(
   "SDL_GPUColorTargetDescription",
   GPUColorTargetDescription
)

local GPUVertexInputState = schema.ffi.struct(
   "SDL_GPUVertexInputState",
   {
      vertex_buffer_descriptions = {
         schema = GPUVertexBufferDescriptions,
         count_field = "num_vertex_buffers",
      },
      vertex_attributes = {
         schema = GPUVertexAttributes,
         count_field = "num_vertex_attributes",
      },
   }
)

local GPUBufferCreateInfo = schema.ffi.struct(
   "SDL_GPUBufferCreateInfo",
   {
      usage = M.GPUBufferUsageFlags,
      size = schema.integer():non_negative(),
      props = properties_id_schema,
   }
)

local GPUShaderResourceInfo = schema.record({
   num_samplers = schema.integer():non_negative():optional(0),
   num_storage_textures = schema.integer():non_negative():optional(0),
   num_storage_buffers = schema.integer():non_negative():optional(0),
   num_uniform_buffers = schema.integer():non_negative():optional(0),
})

local GPUShaderCreateInfo = schema.ffi.struct(
   "SDL_GPUShaderCreateInfo",
   {
      code = {
         schema = schema.string(),
         assign = function(dst, value, bundle)
            local buffer = ffi.new("Uint8[?]", #value)
            ffi.copy(buffer, value, #value)
            dst.code = buffer
            dst.code_size = #value
            bundle:retain(buffer)
         end,
      },
      entrypoint = schema.string():optional("main"),
      format = M.GPUShaderFormat,
      stage = M.GPUShaderStage,
      num_samplers = schema.integer():non_negative():optional(0),
      num_storage_textures = schema.integer():non_negative():optional(0),
      num_storage_buffers = schema.integer():non_negative():optional(0),
      num_uniform_buffers = schema.integer():non_negative():optional(0),
      props = properties_id_schema,
   }
)

local GPURasterizerState = schema.ffi.struct(
   "SDL_GPURasterizerState",
   {
      fill_mode = M.GPUFillMode:optional(),
      cull_mode = M.GPUCullMode:optional(),
      front_face = M.GPUFrontFace:optional(),
      depth_bias_constant_factor = schema.number():optional(),
      depth_bias_clamp = schema.number():optional(),
      depth_bias_slope_factor = schema.number():optional(),
      enable_depth_bias = schema.boolean():optional(),
      enable_depth_clip = schema.boolean():optional(),
   }
)

local GPUMultisampleState = schema.ffi.struct(
   "SDL_GPUMultisampleState",
   {
      sample_count = M.GPUSampleCount:optional(),
      sample_mask = schema.integer():non_negative():optional(),
      enable_mask = schema.boolean():optional(),
      enable_alpha_to_coverage = schema.boolean():optional(),
   }
)

local GPUStencilOpState = schema.ffi.struct(
   "SDL_GPUStencilOpState",
   {
      fail_op = M.GPUStencilOp:optional(),
      pass_op = M.GPUStencilOp:optional(),
      depth_fail_op = M.GPUStencilOp:optional(),
      compare_op = M.GPUCompareOp:optional(),
   }
)

local GPUDepthStencilState = schema.ffi.struct(
   "SDL_GPUDepthStencilState",
   {
      compare_op = M.GPUCompareOp:optional(),
      back_stencil_state = GPUStencilOpState:optional(),
      front_stencil_state = GPUStencilOpState:optional(),
      enable_depth_test = schema.boolean():optional(),
      enable_depth_write = schema.boolean():optional(),
      enable_stencil_test = schema.boolean():optional(),
      compare_mask = Uint8Value:optional(),
      write_mask = Uint8Value:optional(),
   }
)

local GPUGraphicsPipelineTargetInfo = schema.ffi.struct(
   "SDL_GPUGraphicsPipelineTargetInfo",
   {
      color_target_descriptions = {
         schema = GPUColorTargetDescriptions:optional(),
         count_field = "num_color_targets",
      },
      depth_stencil_format = M.GPUTextureFormat:optional(),
      has_depth_stencil_target = schema.boolean():optional(),
   }
)

local GPUGraphicsPipelineCreateInfo = schema.ffi.struct(
   "SDL_GPUGraphicsPipelineCreateInfo",
   {
      vertex_shader = {
         schema = schema.any():optional(),
         assign = function(dst, value, bundle)
            if GPUShader:is_instance(value) then
               ensure_gpu_shader_live(value)
               dst.vertex_shader = value.ptr
               bundle:retain(value)
               return
            end
            dst.vertex_shader = value
         end,
      },
      fragment_shader = {
         schema = schema.any():optional(),
         assign = function(dst, value, bundle)
            if GPUShader:is_instance(value) then
               ensure_gpu_shader_live(value)
               dst.fragment_shader = value.ptr
               bundle:retain(value)
               return
            end
            dst.fragment_shader = value
         end,
      },
      primitive_type = M.GPUPrimitiveType,
      vertex_input = {
         schema = schema.any():optional(),
         assign = function(dst, value, bundle)
            if type(value) == "table" and value.cdata ~= nil and value.value ~= nil then
               dst.vertex_input_state = value.value
               bundle:retain(value)
               return
            end
            dst.vertex_input_state = value
         end,
      },
      rasterizer_state = GPURasterizerState:optional(),
      multisample_state = GPUMultisampleState:optional(),
      depth_stencil_state = GPUDepthStencilState:optional(),
      target_info = GPUGraphicsPipelineTargetInfo:optional(),
      props = properties_id_schema,
   }
)

local VertexInputLayoutBuffer = schema.record({
   slot = schema.integer():non_negative():optional(),
   pitch = schema.integer():non_negative(),
   input_rate = M.GPUVertexInputRate:optional(
      sdl3.GPU_VERTEXINPUTRATE_VERTEX
   ),
   instance_step_rate = schema.integer():non_negative():optional(0),
   attributes = schema.array(GPUVertexAttributeSource),
})

local VertexInputLayout = schema.record({
   buffers = schema.array(VertexInputLayoutBuffer),
})

function M.build_vertex_buffer_descriptions(buffers)
   local raw_buffers = schema.assert(
      schema.array(schema.table()),
      buffers,
      "sdl3x.build_vertex_buffer_descriptions buffers"
   )
   local normalized = {}

   for i = 1, #raw_buffers do
      local spec = rig.shallow_copy(raw_buffers[i])
      if spec.slot == nil then
         spec.slot = i - 1
      end
      normalized[i] = spec
   end

   return GPUVertexBufferDescriptions(
      normalized,
      "sdl3x.build_vertex_buffer_descriptions buffers"
   ).cdata
end

function M.build_vertex_attributes(attributes)
   local normalized = schema.assert(
      schema.array(GPUVertexAttributeSource),
      attributes,
      "sdl3x.build_vertex_attributes attributes"
   )

   return GPUVertexAttributes(
      normalized,
      "sdl3x.build_vertex_attributes attributes"
   ).cdata
end

function M.build_vertex_input_state(layout)
   local decoded = VertexInputLayout(
      layout,
      "sdl3x.build_vertex_input_state layout"
   )

   local attribute_specs = {}
   local buffer_specs = {}
   for i = 1, #decoded.buffers do
      local buffer = rig.shallow_copy(decoded.buffers[i])
      local buffer_slot = buffer.slot
      if buffer_slot == nil then
         buffer_slot = i - 1
         buffer.slot = buffer_slot
      end
      buffer.attributes = nil
      buffer_specs[i] = buffer

      for j = 1, #decoded.buffers[i].attributes do
         local spec = rig.shallow_copy(decoded.buffers[i].attributes[j])
         spec.buffer_slot = buffer_slot
         attribute_specs[#attribute_specs + 1] = spec
      end
   end

   local vertex_input_state = GPUVertexInputState(
      {
         vertex_buffer_descriptions = buffer_specs,
         vertex_attributes = attribute_specs,
      },
      "sdl3x.build_vertex_input_state state"
   )
   vertex_input_state.vertex_buffer_descriptions = vertex_input_state.cdata[0].vertex_buffer_descriptions
   vertex_input_state.vertex_attributes = vertex_input_state.cdata[0].vertex_attributes
   return vertex_input_state
end

function M.build_color_target_descriptions(specs)
   return GPUColorTargetDescriptions(
      specs,
      "sdl3x.build_color_target_descriptions specs"
   ).cdata
end

function M.build_gpu_buffer_create_info(spec)
   return GPUBufferCreateInfo(
      spec,
      "sdl3x.build_gpu_buffer_create_info spec"
   ).cdata
end

function M.build_graphics_pipeline_create_info(spec)
   local bundle = GPUGraphicsPipelineCreateInfo(
      spec,
      "sdl3x.build_graphics_pipeline_create_info spec"
   )
   bundle.create_info = bundle.cdata
   return bundle
end

local STAGE_TO_SDL = {
   vertex = sdl3.GPU_SHADERSTAGE_VERTEX,
   fragment = sdl3.GPU_SHADERSTAGE_FRAGMENT,
}

local GRAPHICS_SPIRV_EXPECTED_SETS = {
   vertex = {
      sampled_images = 0,
      separate_samplers = 0,
      separate_images = 0,
      storage_images = 0,
      storage_buffers = 0,
      uniform_buffers = 1,
   },
   fragment = {
      sampled_images = 2,
      separate_samplers = 2,
      separate_images = 2,
      storage_images = 2,
      storage_buffers = 2,
      uniform_buffers = 3,
   },
}

local function normalize_gpu_shader_format(compiled)
   local format = compiled.format
   if format == nil or format == "spirv" then
      return sdl3.GPU_SHADERFORMAT_SPIRV
   end

   local numeric = tonumber(format)
   if numeric == nil then
      error(("compiled shader format '%s' is not supported by SDL GPU"):format(
         format
      ))
   end

   return numeric
end

local function validate_graphics_spirv_layout(compiled)
   if normalize_gpu_shader_format(compiled) ~= sdl3.GPU_SHADERFORMAT_SPIRV then
      return true
   end

   local expected_sets = GRAPHICS_SPIRV_EXPECTED_SETS[compiled.stage]
   if expected_sets == nil then
      return true
   end

   local resources = compiled.reflection and compiled.reflection.resources
   if type(resources) ~= "table" then
      return nil, "compiled shader is missing reflection.resources"
   end

   for kind, expected_set in pairs(expected_sets) do
      local list = resources[kind]
      if type(list) == "table" then
         for _, item in ipairs(list) do
            if item.set ~= expected_set then
               return nil, (
                  "SPIR-V %s shader %s resource '%s' is in descriptor set %s, expected %d for SDL_GPU"
               ):format(
                  compiled.stage,
                  kind,
                  item.name or "<unnamed>",
                  item.set,
                  expected_set
               )
            end
         end
      end
   end

   return true
end

function M.create_gpu_shader(device, compiled, props)
   return GPUShader(device, compiled, props)
end

function GPUShader:init(device, compiled, props)
   if device == nil then
      rig.raise("sdl3x.GPUShader requires an SDL_GPUDevice*")
   end
   if type(compiled) ~= "table" then
      error("sdl3x.GPUShader requires a compiled shader table")
   end

   local shader_stage = STAGE_TO_SDL[compiled.stage]
   if shader_stage == nil then
      error(("shader stage '%s' is not a graphics shader stage"):format(
         compiled.stage
      ))
   end

   local valid_layout, layout_err = validate_graphics_spirv_layout(compiled)
   if not valid_layout then
      rig.raise(layout_err or "shader layout validation failed")
   end

   local reflection = compiled.reflection
   if type(reflection) ~= "table" or type(reflection.resource_info) ~= "table" then
      rig.raise("compiled shader is missing reflection.resource_info")
   end

   local resource_info = GPUShaderResourceInfo(
      reflection.resource_info,
      "compiled shader reflection.resource_info"
   )

   local create_info = GPUShaderCreateInfo(
      {
         code = compiled.bytecode,
         entrypoint = compiled.entrypoint,
         format = normalize_gpu_shader_format(compiled),
         stage = shader_stage,
         num_samplers = resource_info.num_samplers,
         num_storage_textures = resource_info.num_storage_textures,
         num_storage_buffers = resource_info.num_storage_buffers,
         num_uniform_buffers = resource_info.num_uniform_buffers,
         props = props,
      },
      "sdl3x.create_gpu_shader create_info"
   )

   local shader_handle = sdl3.CreateGPUShader(device, create_info.cdata)
   if shader_handle == nil then
      rig.raise(M.get_error())
   end

   self.device = device
   self.ptr = shader_handle
   self.stage = compiled.stage
   self.format = normalize_gpu_shader_format(compiled)
   self.entrypoint = compiled.entrypoint or "main"
   self._released = false
end

function GPUShader:release()
   ensure_gpu_shader(self)
   if self._released then
      return
   end

   if self.ptr ~= nil and self.ptr ~= ffi.NULL then
      sdl3.ReleaseGPUShader(self.device, self.ptr)
   end

   self.ptr = nil
   self._released = true
end

--[ ResourceScope ]--

local ResourceScope = rig.Class(rig.ResourceScope)
M.ResourceScope = ResourceScope

function ResourceScope:init(context, label)
   self:super().init(self, context, label or "sdl3x resource scope")
end

function ResourceScope:create_gpu_shader(compiled, props)
   local shader_handle = M.create_gpu_shader(self.context, compiled, props)
   return self:adopt(shader_handle, function(_, resource)
      resource:release()
   end)
end

function ResourceScope:create_gpu_buffer(create_info)
   local normalized = create_info
   if type(create_info) == "table" then
      normalized = M.build_gpu_buffer_create_info(create_info)
   end

   local buffer = sdl3.CreateGPUBuffer(self.context, normalized)
   if buffer == nil then
      rig.raise("failed to create GPU buffer: " .. M.get_error())
   end

   return self:adopt(buffer, function(device, resource)
      sdl3.ReleaseGPUBuffer(device, resource)
   end)
end

function ResourceScope:create_graphics_pipeline(create_info)
   local normalized = create_info
   if type(create_info) == "table" then
      local bundle = M.build_graphics_pipeline_create_info(create_info)
      normalized = bundle.create_info
   end

   local pipeline = sdl3.CreateGPUGraphicsPipeline(self.context, normalized)
   if pipeline == nil then
      rig.raise("failed to create GPU graphics pipeline: " .. M.get_error())
   end

   return self:adopt(pipeline, function(device, resource)
      sdl3.ReleaseGPUGraphicsPipeline(device, resource)
   end)
end

function ResourceScope:create_depth_texture(width, height, format)
   local texture, chosen_format =
      M.create_depth_texture(self.context, width, height, format)
   self:adopt(texture, function(device, resource)
      sdl3.ReleaseGPUTexture(device, resource)
   end)
   return texture, chosen_format
end

--[ Runtime configuration ]--

local function default_create_renderer(window)
   local renderer_ptr = sdl3.CreateRenderer(window.ptr, nil)
   if renderer_ptr == nil then
      return nil, M.get_error()
   end

   if not sdl3.SetRenderVSync(renderer_ptr, 1) then
      sdl3.DestroyRenderer(renderer_ptr)
      return nil, M.get_error()
   end

   return renderer_ptr
end

local function get_error_string()
   return M.get_error()
end

local function has_all_bits(value, mask)
   local v = tonumber(value) or 0
   local m = tonumber(mask) or 0
   return bit.band(v, m) == bit.tobit(m)
end

local function has_any_bits(value, mask)
   local v = tonumber(value) or 0
   local m = tonumber(mask) or 0
   return bit.band(v, m) ~= 0
end

local function format_gpu_shader_formats(flags)
   local names = {}
   local value = tonumber(flags) or 0

   if value == 0 then
      return "INVALID"
   end

   local mapping = {
      { sdl3.GPU_SHADERFORMAT_PRIVATE, "PRIVATE" },
      { sdl3.GPU_SHADERFORMAT_SPIRV, "SPIRV" },
      { sdl3.GPU_SHADERFORMAT_DXBC, "DXBC" },
      { sdl3.GPU_SHADERFORMAT_DXIL, "DXIL" },
      { sdl3.GPU_SHADERFORMAT_MSL, "MSL" },
      { sdl3.GPU_SHADERFORMAT_METALLIB, "METALLIB" },
   }

   for _, entry in ipairs(mapping) do
      if has_any_bits(value, entry[1]) then
         table.insert(names, entry[2])
      end
   end

   if #names == 0 then
      return tostring(value)
   end
   return table.concat(names, "|")
end

function M.get_gpu_driver_names()
   local count = tonumber(sdl3.GetNumGPUDrivers()) or 0
   local names = {}

   for i = 0, count - 1 do
      local ptr = sdl3.GetGPUDriver(i)
      if ptr ~= nil and ptr ~= ffi.NULL and ptr[0] ~= 0 then
         table.insert(names, ffi.string(ptr))
      end
   end

   return names
end

local function build_gpu_support_error(format_flags, backend_name, detail)
   local lines = {}
   table.insert(lines, "no supported SDL_GPU backend is available")
   table.insert(
      lines,
      "requested shader formats: " .. format_gpu_shader_formats(format_flags)
   )

   if backend_name ~= nil then
      table.insert(lines, "requested backend: " .. tostring(backend_name))
   else
      table.insert(lines, "requested backend: automatic")
   end

   local driver_names = M.get_gpu_driver_names()
   if #driver_names > 0 then
      table.insert(
         lines,
         "SDL compiled GPU drivers: " .. table.concat(driver_names, ", ")
      )
   else
      table.insert(lines, "SDL compiled GPU drivers: none reported")
   end

   if detail ~= nil and detail ~= "" then
      table.insert(lines, "SDL error: " .. tostring(detail))
   end

   if has_any_bits(format_flags, sdl3.GPU_SHADERFORMAT_SPIRV) then
      table.insert(lines, "SPIR-V requires a Vulkan-capable SDL_GPU backend.")
      table.insert(
         lines,
         "Check that a Vulkan ICD is installed and that the GPU exposes enough Vulkan support."
      )
      table.insert(
         lines,
         "Older Intel Haswell GPUs often expose only incomplete Vulkan support through Mesa hasvk and may still be rejected by SDL_GPU."
      )
   end

   return table.concat(lines, "\n")
end

local function format_factory_error(factory_name, detail, fallback)
   if detail == nil then
      return ("%s failed: %s"):format(factory_name, fallback)
   end
   return ("%s failed: %s"):format(factory_name, detail)
end

local function normalize_init_flags(flags_number)
   if type(flags_number) ~= "number" then
      rig.raise("sdl3 init_flags must be a number")
   end

   local flags_integer = math.floor(flags_number)
   if flags_number < 0.0 or flags_number ~= flags_integer then
      error("sdl3 init_flags must be a non-negative integer")
   end
   if flags_number > 4294967295.0 then
      error("sdl3 init_flags exceeds Uint32 range")
   end

   return ffi.cast("Uint32", flags_integer)
end

local destroy_gl_font_backend_state
local gl_font_quad_vertices = ffi.new("float[24]")
local gl_font_backend_state = nil

--[ Runtime accessors ]--

function M.get_gl_proc_address(name)
   if type(name) ~= "string" or name == "" then
      rig.raise("sdl3x.get_gl_proc_address expects a non-empty string")
   end

   local ptr = sdl3.GL_GetProcAddress(name)
   if ptr == nil or ptr == ffi.NULL then
      return nil, get_error_string()
   end

   return ptr
end

--[ OpenGL runtime setup ]--

local GL_PROFILE_VALUES = {
   core = sdl3.GL_CONTEXT_PROFILE_CORE,
   compatibility = sdl3.GL_CONTEXT_PROFILE_COMPATIBILITY,
   es = sdl3.GL_CONTEXT_PROFILE_ES,
}

local GL_ATTRIBUTE_VALUES = {
   red_size = "GL_ATTR_RED_SIZE",
   green_size = "GL_ATTR_GREEN_SIZE",
   blue_size = "GL_ATTR_BLUE_SIZE",
   alpha_size = "GL_ATTR_ALPHA_SIZE",
   buffer_size = "GL_ATTR_BUFFER_SIZE",
   doublebuffer = "GL_ATTR_DOUBLEBUFFER",
   depth_size = "GL_ATTR_DEPTH_SIZE",
   stencil_size = "GL_ATTR_STENCIL_SIZE",
   multisamplebuffers = "GL_ATTR_MULTISAMPLEBUFFERS",
   multisamplesamples = "GL_ATTR_MULTISAMPLESAMPLES",
   accelerated_visual = "GL_ATTR_ACCELERATED_VISUAL",
   context_major_version = "GL_ATTR_CONTEXT_MAJOR_VERSION",
   context_minor_version = "GL_ATTR_CONTEXT_MINOR_VERSION",
   context_flags = "GL_ATTR_CONTEXT_FLAGS",
   context_profile = "GL_ATTR_CONTEXT_PROFILE_MASK",
   share_with_current_context = "GL_ATTR_SHARE_WITH_CURRENT_CONTEXT",
   framebuffer_srgb_capable = "GL_ATTR_FRAMEBUFFER_SRGB_CAPABLE",
}

local function gl_attribute_int(value)
   if type(value) == "boolean" then
      return value and 1 or 0
   end
   if type(value) ~= "number" then
      rig.raise("OpenGL attribute values must be booleans or numbers")
   end
   return value
end

--[ OpenGL schemas ]--

local GLAttributeValue = schema.one_of({
   schema.boolean(),
   schema.number(),
}, "a boolean or number"):transform(function(value)
   return gl_attribute_int(value)
end)

local GLContextProfile = schema.one_of({
   schema.string_lookup(GL_PROFILE_VALUES, "OpenGL context profile"),
   GLAttributeValue,
}, "a supported OpenGL context profile or boolean/number")

local GLAttributes = schema.record({
   red_size = GLAttributeValue:optional(),
   green_size = GLAttributeValue:optional(),
   blue_size = GLAttributeValue:optional(),
   alpha_size = GLAttributeValue:optional(),
   buffer_size = GLAttributeValue:optional(),
   doublebuffer = GLAttributeValue:optional(),
   depth_size = GLAttributeValue:optional(),
   stencil_size = GLAttributeValue:optional(),
   multisamplebuffers = GLAttributeValue:optional(),
   multisamplesamples = GLAttributeValue:optional(),
   accelerated_visual = GLAttributeValue:optional(),
   context_major_version = GLAttributeValue:optional(),
   context_minor_version = GLAttributeValue:optional(),
   context_flags = GLAttributeValue:optional(),
   context_profile = GLContextProfile:optional(),
   share_with_current_context = GLAttributeValue:optional(),
   framebuffer_srgb_capable = GLAttributeValue:optional(),
})

local default_gl_attributes = {
   context_major_version = 3,
   context_minor_version = 3,
   context_profile = "core",
   doublebuffer = true,
   depth_size = 24,
}

local function apply_gl_attributes(attributes)
   sdl3.GL_ResetAttributes()

   local requested = GLAttributes(
      attributes or default_gl_attributes,
      "sdl3_gl gl_attributes"
   )

   for key, value in pairs(requested) do
      local field = GL_ATTRIBUTE_VALUES[key]

      if not sdl3.GL_SetAttribute(sdl3[field], value) then
         error(
            ("failed to set OpenGL attribute '%s': %s"):format(
               key,
               get_error_string()
            ))
      end
   end
end

--[ OpenGL font backend ]--

local gl_font_vertex_source = [[
#version 330 core

layout(location = 0) in vec2 in_position;
layout(location = 1) in vec2 in_uv;

out vec2 out_uv;

uniform vec2 u_view_size;

void main()
{
   vec2 normalized = vec2(
      (in_position.x / u_view_size.x) * 2.0 - 1.0,
      1.0 - (in_position.y / u_view_size.y) * 2.0
   );
   gl_Position = vec4(normalized, 0.0, 1.0);
   out_uv = in_uv;
}
]]

local gl_font_fragment_source = [[
#version 330 core

in vec2 out_uv;
out vec4 frag_color;

uniform sampler2D u_atlas;
uniform vec4 u_color;

void main()
{
   vec4 sample = texture(u_atlas, out_uv);
   frag_color = vec4(u_color.rgb, u_color.a * sample.a);
}
]]

destroy_gl_font_backend_state = function()
   local state = gl_font_backend_state
   if state == nil then
      return
   end

   if state.vbo ~= nil then
      state.vbo:release()
   end
   if state.vao ~= nil then
      state.vao:release()
   end
   if state.program ~= nil then
      state.program:release()
   end

   gl_font_backend_state = nil
end

local function ensure_gl_font_backend_state()
   if gl_font_backend_state ~= nil then
      return gl_font_backend_state
   end

   local gl = require("gl")
   local glx = require("glx")
   local program = glx.Program {
      vertex_source = gl_font_vertex_source,
      fragment_source = gl_font_fragment_source,
   }
   local vao = glx.VertexArray()
   local vbo = glx.Buffer {
      target = gl.ARRAY_BUFFER,
   }
   if vbo.id == 0 then
      vao:release()
      program:release()
      rig.raise("failed to create OpenGL font vertex objects")
   end

   vao:bind()
   vbo:set_data(nil, gl.DYNAMIC_DRAW, ffi.sizeof(gl_font_quad_vertices))
   vao:attribute(0, 2, gl.FLOAT, gl.FALSE, 16, 0)
   vao:attribute(1, 2, gl.FLOAT, gl.FALSE, 16, 8)

   local atlas_location = program:uniform_location("u_atlas")
   local view_size_location = program:uniform_location("u_view_size")
   local color_location = program:uniform_location("u_color")
   if atlas_location < 0 or view_size_location < 0 or color_location < 0 then
      vbo:release()
      vao:release()
      program:release()
      rig.raise("failed to locate OpenGL font shader uniforms")
   end

   program:use()
   program:set_uniform1i("u_atlas", 0)

   gl_font_backend_state = {
      gl = gl,
      program = program,
      vao = vao,
      vbo = vbo,
   }

   return gl_font_backend_state
end

local function upload_gl_font_page_texture(texture, page, rgba)
   local gl = require("gl")
   local texture_2d = texture
   if texture_2d == nil then
      texture_2d = require("glx").Texture2D()
   end

   texture_2d:bind(0)
   texture_2d:parameter(gl.TEXTURE_MIN_FILTER, gl.LINEAR)
   texture_2d:parameter(gl.TEXTURE_MAG_FILTER, gl.LINEAR)
   texture_2d:parameter(gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
   texture_2d:parameter(gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
   texture_2d:image(
      0,
      gl.RGBA,
      page.width,
      page.height,
      gl.RGBA,
      gl.UNSIGNED_BYTE,
      rgba,
      0
   )

   return texture_2d
end

local function write_gl_font_quad_vertices(packed, x, y, scale)
   local x0 = x
   local y0 = y
   local x1 = x + packed.width * scale
   local y1 = y + packed.height * scale

   gl_font_quad_vertices[0] = x0
   gl_font_quad_vertices[1] = y0
   gl_font_quad_vertices[2] = packed.u0
   gl_font_quad_vertices[3] = packed.v0

   gl_font_quad_vertices[4] = x1
   gl_font_quad_vertices[5] = y0
   gl_font_quad_vertices[6] = packed.u1
   gl_font_quad_vertices[7] = packed.v0

   gl_font_quad_vertices[8] = x1
   gl_font_quad_vertices[9] = y1
   gl_font_quad_vertices[10] = packed.u1
   gl_font_quad_vertices[11] = packed.v1

   gl_font_quad_vertices[12] = x0
   gl_font_quad_vertices[13] = y0
   gl_font_quad_vertices[14] = packed.u0
   gl_font_quad_vertices[15] = packed.v0

   gl_font_quad_vertices[16] = x1
   gl_font_quad_vertices[17] = y1
   gl_font_quad_vertices[18] = packed.u1
   gl_font_quad_vertices[19] = packed.v1

   gl_font_quad_vertices[20] = x0
   gl_font_quad_vertices[21] = y1
   gl_font_quad_vertices[22] = packed.u0
   gl_font_quad_vertices[23] = packed.v1
end

--[ SDL font backend ]--

local font_src_rect = ffi.new("SDL_FRect[1]")
local font_dst_rect = ffi.new("SDL_FRect[1]")

local function upload_font_page_texture(renderer, texture, page, rgba)
   local page_texture = texture
   if page_texture == nil or page_texture == ffi.NULL then
      page_texture = sdl3.CreateTexture(
         renderer,
         sdl3.PIXELFORMAT_RGBA32,
         sdl3.TEXTUREACCESS_STATIC,
         page.width,
         page.height
      )
      if page_texture == nil or page_texture == ffi.NULL then
         rig.raise("failed to create SDL texture: " .. get_error_string())
      end

      if not sdl3.SetTextureBlendMode(page_texture, sdl3.BLENDMODE_BLEND) then
         sdl3.DestroyTexture(page_texture)
         rig.raise("failed to set SDL texture blend mode: " .. get_error_string())
      end
   end

   if not sdl3.UpdateTexture(page_texture, nil, rgba, page.width * 4) then
      if texture == nil or texture == ffi.NULL then
         sdl3.DestroyTexture(page_texture)
      end
      rig.raise("failed to upload SDL texture: " .. get_error_string())
   end

   return page_texture
end

local function make_sdl3_font_provider(context)
   local renderer = context:capability("graphics.context").renderer

   local function upload_page_texture(text_renderer, texture, page, rgba)
      return upload_font_page_texture(renderer, texture, page, rgba)
   end

   local function destroy_page_texture(text_renderer, texture)
      if texture ~= nil and texture ~= ffi.NULL then
         sdl3.DestroyTexture(texture)
      end
   end

   local function draw_packed_glyph(text_renderer, texture, packed, x, y, draw_color, scale)
      if packed.width <= 0 or packed.height <= 0 then
         return
      end

      if not sdl3.SetTextureColorMod(texture, draw_color.r, draw_color.g, draw_color.b) then
         rig.raise("failed to set texture color modulation: " .. get_error_string())
      end
      if not sdl3.SetTextureAlphaMod(texture, draw_color.a) then
         rig.raise("failed to set texture alpha modulation: " .. get_error_string())
      end

      font_src_rect[0].x = packed.x
      font_src_rect[0].y = packed.y
      font_src_rect[0].w = packed.width
      font_src_rect[0].h = packed.height

      font_dst_rect[0].x = x
      font_dst_rect[0].y = y
      font_dst_rect[0].w = packed.width * scale
      font_dst_rect[0].h = packed.height * scale

      if not sdl3.RenderTexture(renderer, texture, font_src_rect, font_dst_rect) then
         rig.raise("failed to render SDL texture: " .. get_error_string())
      end
   end

   return {
      upload_page_texture = upload_page_texture,
      destroy_page_texture = destroy_page_texture,
      draw_packed_glyph = draw_packed_glyph,
   }
end

local function make_sdl3_gl_font_provider(context)
   local window = context:capability("graphics.context").window

   local function upload_page_texture(text_renderer, texture, page, rgba)
      return upload_gl_font_page_texture(texture, page, rgba)
   end

   local function destroy_page_texture(text_renderer, texture)
      if texture ~= nil then
         texture:release()
      end
   end

   local function draw_packed_glyph(text_renderer, texture, packed, x, y, draw_color, scale)
      if packed.width <= 0 or packed.height <= 0 then
         return
      end

      local backend_state = ensure_gl_font_backend_state()
      local gl = backend_state.gl
      local window_width, window_height = window:get_size_in_pixels()
      if window_width <= 0 or window_height <= 0 then
         return
      end

      write_gl_font_quad_vertices(packed, x, y, scale)

      gl.Enable(gl.BLEND)
      gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
      backend_state.program:use()
      backend_state.program:set_uniform2f("u_view_size", window_width, window_height)
      backend_state.program:set_uniform4f(
         "u_color",
         draw_color.r / 255.0,
         draw_color.g / 255.0,
         draw_color.b / 255.0,
         draw_color.a / 255.0
      )
      texture:bind(0)
      backend_state.vao:bind()
      backend_state.vbo:set_data(gl_font_quad_vertices, gl.DYNAMIC_DRAW)
      gl.DrawArrays(gl.TRIANGLES, 0, 6)
   end

   return {
      upload_page_texture = upload_page_texture,
      destroy_page_texture = destroy_page_texture,
      draw_packed_glyph = draw_packed_glyph,
   }
end

--[ GPU and rendering utilities ]--

function M.upload_to_gpu_buffer(device, buffer, data)
   if device == nil then
      rig.raise("sdl3x.upload_to_gpu_buffer requires an SDL_GPUDevice*")
   end
   if buffer == nil then
      rig.raise("sdl3x.upload_to_gpu_buffer requires an SDL_GPUBuffer*")
   end
   if type(data) ~= "string" then
      rig.raise("sdl3x.upload_to_gpu_buffer requires data to be a string")
   end

   local transfer_info = ffi.new("SDL_GPUTransferBufferCreateInfo[1]")
   transfer_info[0].usage = sdl3.GPU_TRANSFERBUFFERUSAGE_UPLOAD
   transfer_info[0].size = #data
   transfer_info[0].props = 0

   local transfer_buffer = sdl3.CreateGPUTransferBuffer(device, transfer_info)
   if transfer_buffer == nil then
      rig.raise("failed to create GPU transfer buffer: " .. get_error_string())
   end

   local mapped = sdl3.MapGPUTransferBuffer(device, transfer_buffer, false)
   if mapped == nil then
      sdl3.ReleaseGPUTransferBuffer(device, transfer_buffer)
      rig.raise("failed to map GPU transfer buffer: " .. get_error_string())
   end
   ffi.copy(mapped, data, #data)
   sdl3.UnmapGPUTransferBuffer(device, transfer_buffer)

   local command_buffer = sdl3.AcquireGPUCommandBuffer(device)
   if command_buffer == nil then
      sdl3.ReleaseGPUTransferBuffer(device, transfer_buffer)
      rig.raise("failed to acquire GPU command buffer: " .. get_error_string())
   end

   local copy_pass = sdl3.BeginGPUCopyPass(command_buffer)
   local source = ffi.new("SDL_GPUTransferBufferLocation[1]")
   source[0].transfer_buffer = transfer_buffer
   source[0].offset = 0

   local destination = ffi.new("SDL_GPUBufferRegion[1]")
   destination[0].buffer = buffer
   destination[0].offset = 0
   destination[0].size = #data

   sdl3.UploadToGPUBuffer(copy_pass, source, destination, false)
   sdl3.EndGPUCopyPass(copy_pass)

   if not sdl3.SubmitGPUCommandBuffer(command_buffer) then
      sdl3.ReleaseGPUTransferBuffer(device, transfer_buffer)
      rig.raise("failed to submit GPU upload command buffer: " .. get_error_string())
   end

   sdl3.ReleaseGPUTransferBuffer(device, transfer_buffer)
end

-- Uploads tightly packed RGBA8 pixels to a 2D SDL_GPU texture.
function M.upload_to_gpu_texture(device, texture, data, width, height)
   if device == nil then
      rig.raise("sdl3x.upload_to_gpu_texture requires an SDL_GPUDevice*")
   end
   if texture == nil then
      rig.raise("sdl3x.upload_to_gpu_texture requires an SDL_GPUTexture*")
   end
   if type(data) ~= "string" then
      rig.raise("sdl3x.upload_to_gpu_texture requires data to be a string")
   end

   local transfer_info = ffi.new("SDL_GPUTransferBufferCreateInfo[1]")
   transfer_info[0].usage = sdl3.GPU_TRANSFERBUFFERUSAGE_UPLOAD
   transfer_info[0].size = #data
   transfer_info[0].props = 0

   local transfer_buffer = sdl3.CreateGPUTransferBuffer(device, transfer_info)
   if transfer_buffer == nil then
      rig.raise("failed to create GPU texture transfer buffer: " .. get_error_string())
   end

   local mapped = sdl3.MapGPUTransferBuffer(device, transfer_buffer, false)
   if mapped == nil then
      sdl3.ReleaseGPUTransferBuffer(device, transfer_buffer)
      rig.raise("failed to map GPU texture transfer buffer: " .. get_error_string())
   end
   ffi.copy(mapped, data, #data)
   sdl3.UnmapGPUTransferBuffer(device, transfer_buffer)

   local command_buffer = sdl3.AcquireGPUCommandBuffer(device)
   if command_buffer == nil then
      sdl3.ReleaseGPUTransferBuffer(device, transfer_buffer)
      rig.raise("failed to acquire GPU command buffer: " .. get_error_string())
   end

   local copy_pass = sdl3.BeginGPUCopyPass(command_buffer)
   local source = ffi.new("SDL_GPUTextureTransferInfo[1]")
   source[0].transfer_buffer = transfer_buffer
   source[0].offset = 0
   source[0].pixels_per_row = width or 0
   source[0].rows_per_layer = height or 0

   local destination = ffi.new("SDL_GPUTextureRegion[1]")
   destination[0].texture = texture
   destination[0].mip_level = 0
   destination[0].layer = 0
   destination[0].x = 0
   destination[0].y = 0
   destination[0].z = 0
   destination[0].w = width or 0
   destination[0].h = height or 0
   destination[0].d = 1

   sdl3.UploadToGPUTexture(copy_pass, source, destination, false)
   sdl3.EndGPUCopyPass(copy_pass)

   if not sdl3.SubmitGPUCommandBuffer(command_buffer) then
      sdl3.ReleaseGPUTransferBuffer(device, transfer_buffer)
      rig.raise("failed to submit GPU texture upload command buffer: " .. get_error_string())
   end

   sdl3.ReleaseGPUTransferBuffer(device, transfer_buffer)
end

function M.choose_depth_format(device)
   if device == nil then
      rig.raise("sdl3x.choose_depth_format requires an SDL_GPUDevice*")
   end

   local candidates = {
      sdl3.GPU_TEXTUREFORMAT_D32_FLOAT,
      sdl3.GPU_TEXTUREFORMAT_D24_UNORM,
      sdl3.GPU_TEXTUREFORMAT_D16_UNORM,
   }

   for _, format in ipairs(candidates) do
      if sdl3.GPUTextureSupportsFormat(
         device,
         format,
         sdl3.GPU_TEXTURETYPE_2D,
         sdl3.GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET
      ) then
         return format
      end
   end

   rig.raise("no supported depth texture format found")
end

function M.create_depth_texture(device, width, height, format)
   if device == nil then
      rig.raise("sdl3x.create_depth_texture requires an SDL_GPUDevice*")
   end

   if format == nil then
      format = M.choose_depth_format(device)
   end

   local create_info = ffi.new("SDL_GPUTextureCreateInfo[1]")
   create_info[0].type = sdl3.GPU_TEXTURETYPE_2D
   create_info[0].format = format
   create_info[0].usage = sdl3.GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET
   create_info[0].width = width
   create_info[0].height = height
   create_info[0].layer_count_or_depth = 1
   create_info[0].num_levels = 1
   create_info[0].sample_count = sdl3.GPU_SAMPLECOUNT_1
   create_info[0].props = 0

   local texture = sdl3.CreateGPUTexture(device, create_info)
   if texture == nil then
      rig.raise("failed to create GPU depth texture: " .. get_error_string())
   end

   return texture, format
end

local function current_monotonic_seconds()
   local counter = tonumber(sdl3.GetPerformanceCounter())
   local frequency = tonumber(sdl3.GetPerformanceFrequency())
   if frequency == nil or frequency <= 0 then
      rig.raise("sdl3.GetPerformanceFrequency returned an invalid value")
   end
   return counter / frequency
end

local function current_time_seconds()
   local ticks = ffi.new("int64_t[1]")
   if not sdl3.GetCurrentTime(ticks) then
      rig.raise("sdl3.GetCurrentTime failed: " .. M.get_error())
   end
   return tonumber(ticks[0]) / 1000000000.0
end

--[ Runtime services ]--

local sdl3_gpu_mesh_service = {
   build_vertex_input = function(mesh)
      if type(mesh) ~= "table" then
         rig.raise("mesh.vertex_input provider expects a mesh table")
      end

      local attributes = {
         {
            location = 0,
            format = "FLOAT3",
            offset = mesh.attribute_offsets.position,
         },
         {
            location = 1,
            format = "FLOAT3",
            offset = mesh.attribute_offsets.color,
         },
      }

      if mesh.layout == "position_color_f32" then
         -- no additional attributes
      elseif mesh.layout == "position_color_uv_f32" then
         attributes[#attributes + 1] = {
            location = 2,
            format = "FLOAT2",
            offset = mesh.attribute_offsets.uv,
         }
      else
         rig.raise("unsupported mesh layout '%s'", mesh.layout)
      end

      return M.build_vertex_input_state {
         buffers = {
            {
               slot = 0,
               pitch = mesh.vertex_stride,
               input_rate = "vertex",
               attributes = attributes,
            },
         },
      }
   end,
}

local function make_shader_stage_service_sdl3_gpu(context)
   local device = context:capability("graphics.context").device

   return {
      create_stage = function(spec)
         local artifact = spec
         if artifact.artifact_kind == "source" then
            artifact = shader.compile(artifact)
         end
         if artifact.artifact_kind ~= "spirv" then
            error(
               ("shader.stage provider 'sdl3_gpu' requires a SPIR-V artifact, got '%s'"):format(
                  tostring(artifact.artifact_kind)
               ))
         end

         return M.create_gpu_shader(device, artifact, spec.props)
      end,
      destroy_stage = function(stage)
         if GPUShader:is_instance(stage) then
            stage:release()
            return
         end

         sdl3.ReleaseGPUShader(device, stage)
      end,
   }
end

local shader_stage_service_sdl3_gl = {
   create_stage = function(spec)
      if spec.artifact_kind ~= "source" then
         rig.raise(
            "shader.stage provider 'sdl3_gl' requires a source artifact, got '%s'",
            tostring(spec.artifact_kind)
         )
      end
      if spec.language ~= "glsl" then
         rig.raise(
            "shader.stage provider 'sdl3_gl' currently supports only GLSL source, got '%s'",
            tostring(spec.language)
         )
      end

      return require("glx").Shader {
         stage = spec.stage,
         source = spec.source,
         source_name = spec.source_name,
      }
   end,
   destroy_stage = function(stage)
      stage:release()
   end,
}

local gl_resolver_service_sdl3_gl = {
   get_gl_proc_address = function(name)
      return M.get_gl_proc_address(name)
   end,
}

--[ App classes ]--

-- SDL binds the generic application base to the SDL window/graphics context.
local App = rig.Class(app.App)
local SceneApp = rig.Class(scene.SceneApp)

App.app_name = "sdl3x"
App.config_namespace = "sdl3x"
SceneApp.app_name = "sdl3x"
SceneApp.config_namespace = "sdl3x"

M.App = App
M.SceneApp = SceneApp

--[ compositional runtime components ]--

local SdlSubsystem = rig.Class()
M.SdlSubsystem = SdlSubsystem

function M.plugin(spec)
   spec = spec or {}
   return runtime.plugin {
      id = spec.id or "sdl3x",
      capabilities = {
         ["sdl3.subsystem"] = {},
         ["sdl3.window"] = {},
         ["sdl3.input"] = {},
         ["font.renderer"] = {},
         ["shader.stage"] = {},
         ["mesh.vertex_input"] = {},
         ["gl.resolver"] = {},
         ["render.scene"] = {},
         ["render.scene.impl"] = {},
         ["render.mesh"] = {},
         ["render.texture"] = {},
         ["render.target"] = {},
      },
      extension_points = {
         ["sdl3.key"] = { method = "on_key" },
         ["sdl3.mouse"] = { method = "on_mouse" },
         ["sdl3.resize"] = { method = "on_resize" },
         ["sdl3.close"] = { method = "on_close" },
         ["sdl3.focus"] = { method = "on_focus" },
      },
   }
end

function SdlSubsystem:init(flags_number)
   local required = normalize_init_flags(flags_number)
   local initialized = sdl3.WasInit(required)
   local owned = nil

   if not has_all_bits(initialized, required) then
      if not sdl3.Init(required) then
         rig.raise("failed to initialize SDL: " .. get_error_string())
      end
      owned = required
   end

   self.required = required
   self.owned_init_flags = owned
   self.released = false
end

function SdlSubsystem:release()
   if self.released then
      return
   end

   self.released = true
   if self.owned_init_flags ~= nil then
      sdl3.QuitSubSystem(self.owned_init_flags)
      self.owned_init_flags = nil
   end
end

function M.subsystem_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "sdl3.subsystem" },
      },
      create = function()
         return SdlSubsystem(options.init_flags or (sdl3.INIT_VIDEO + sdl3.INIT_EVENTS))
      end,
      release = function(subsystem)
         subsystem:release()
      end,
   })
end

function M.window_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "sdl3.window" },
      },
      requires = {
         { capability = "sdl3.subsystem" },
      },
      create = function()
         return M.Window {
            window_props = options.window_props,
         }
      end,
      release = function(window)
         window:release()
      end,
   })
end

local SdlInput = rig.Class()
M.SdlInput = SdlInput

function SdlInput:init(spec)
   self.window = spec.window
   self.initial = spec.initial ~= false
   self.resize_state = nil
end

function SdlInput:_emit_resize(emit, event_name, timestamp_ns)
   local width, height = self.window:get_size()
   local pixel_width, pixel_height = self.window:get_size_in_pixels()
   local previous = self.resize_state

   if previous ~= nil
      and previous.width == width
      and previous.height == height
      and previous.pixel_width == pixel_width
      and previous.pixel_height == pixel_height
      and event_name ~= "initial" then
      return
   end

   self.resize_state = {
      width = width,
      height = height,
      pixel_width = pixel_width,
      pixel_height = pixel_height,
   }

   local ns = timestamp_ns or 0
   emit("sdl3.resize", {
      type = "resize",
      event = event_name,
      width = width,
      height = height,
      pixel_width = pixel_width,
      pixel_height = pixel_height,
      initial = event_name == "initial",
      timestamp_ns = ns,
      timestamp_ms = math.floor(ns / 1000000),
   })
end

function SdlInput:_emit_key(emit, key_data)
   local key_name = sdl3.GetKeyName(key_data.key)
   local key = "Unknown"
   local mods = tonumber(key_data.mod) or 0
   local timestamp_ns = tonumber(key_data.timestamp) or 0

   if key_name ~= nil and key_name[0] ~= 0 then
      key = ffi.string(key_name)
   end

   emit("sdl3.key", {
      type = "key",
      action = key_data.down and "down" or "up",
      key = key,
      code = tonumber(key_data.key),
      scancode = tonumber(key_data.scancode),
      ["repeat"] = key_data["repeat"] and true or false,
      timestamp_ns = timestamp_ns,
      timestamp_ms = math.floor(timestamp_ns / 1000000),
      mods = {
         shift = has_any_bits(mods, sdl3.KMOD_SHIFT),
         ctrl = has_any_bits(mods, sdl3.KMOD_CTRL),
         alt = has_any_bits(mods, sdl3.KMOD_ALT),
         super = has_any_bits(mods, sdl3.KMOD_GUI),
      },
   })
end

function SdlInput:_emit_mouse_motion(emit, motion)
   local timestamp_ns = tonumber(motion.timestamp) or 0

   emit("sdl3.mouse", {
      type = "mouse",
      action = "move",
      x = tonumber(motion.x) or 0,
      y = tonumber(motion.y) or 0,
      xrel = tonumber(motion.xrel) or 0,
      yrel = tonumber(motion.yrel) or 0,
      buttons = tonumber(motion.state) or 0,
      timestamp_ns = timestamp_ns,
      timestamp_ms = math.floor(timestamp_ns / 1000000),
   })
end

function SdlInput:_emit_mouse_button(emit, button)
   local timestamp_ns = tonumber(button.timestamp) or 0

   emit("sdl3.mouse", {
      type = "mouse",
      action = button.down and "down" or "up",
      button = tonumber(button.button) or 0,
      clicks = tonumber(button.clicks) or 0,
      x = tonumber(button.x) or 0,
      y = tonumber(button.y) or 0,
      timestamp_ns = timestamp_ns,
      timestamp_ms = math.floor(timestamp_ns / 1000000),
   })
end

function SdlInput:poll(emit)
   if self.initial then
      self.initial = false
      self:_emit_resize(emit, "initial", 0)
   end

   local event = ffi.new("SDL_Event[1]")
   while sdl3.PollEvent(event) do
      local current = event[0]
      local event_type = tonumber(current.type) or 0

      if event_type == sdl3.EVENT_QUIT
         or event_type == sdl3.EVENT_WINDOW_CLOSE_REQUESTED then
         self.closed = true
         emit("sdl3.close", { type = "close" })
      elseif event_type == sdl3.EVENT_KEY_DOWN or event_type == sdl3.EVENT_KEY_UP then
         self:_emit_key(emit, current.key)
      elseif event_type == sdl3.EVENT_WINDOW_RESIZED then
         self:_emit_resize(emit, "resized", tonumber(current.window.timestamp) or 0)
      elseif event_type == sdl3.EVENT_WINDOW_PIXEL_SIZE_CHANGED then
         self:_emit_resize(
            emit,
            "pixel_size_changed",
            tonumber(current.window.timestamp) or 0
         )
      elseif event_type == sdl3.EVENT_MOUSE_MOTION then
         self:_emit_mouse_motion(emit, current.motion)
      elseif event_type == sdl3.EVENT_MOUSE_BUTTON_DOWN
         or event_type == sdl3.EVENT_MOUSE_BUTTON_UP then
         self:_emit_mouse_button(emit, current.button)
      elseif event_type == sdl3.EVENT_WINDOW_FOCUS_GAINED then
         emit("sdl3.focus", { type = "focus", focused = true })
      elseif event_type == sdl3.EVENT_WINDOW_FOCUS_LOST then
         emit("sdl3.focus", { type = "focus", focused = false })
      end
   end
end

function M.input_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "sdl3.input" },
      },
      requires = {
         { capability = "sdl3.subsystem" },
         { capability = "sdl3.window" },
      },
      create = function(context)
         return SdlInput {
            window = context.runtime.capability_values["sdl3.window"],
            initial = options.initial_resize,
         }
      end,
      progress = {
         poll = function(context)
            local input = context.runtime.capability_values["sdl3.input"]
            if input ~= nil then
               input:poll(context.emit)
            end
         end,
         should_stop = function(context)
            local input = context.runtime.capability_values["sdl3.input"]
            return input ~= nil and input.closed == true
         end,
      },
   })
end

--[ graphics context components ]--

local function create_renderer_context(options, context)
   local window = context.runtime.capability_values["sdl3.window"]
   local create_renderer = options.create_renderer or default_create_renderer

   if type(create_renderer) ~= "function" then
      rig.raise("sdl3x create_renderer must be a function")
   end

   local renderer, err = create_renderer(window)
   if renderer == nil then
      rig.raise(
         format_factory_error(
            "sdl3x create_renderer",
            err,
            "expected SDL_Renderer* cdata"
         )
      )
   end
   if type(renderer) ~= "cdata" then
      rig.raise("sdl3x create_renderer must return SDL_Renderer* cdata")
   end

   return {
      backend = "renderer",
      window = window,
      renderer = renderer,
      clear = function(self, r, g, b, a)
         local rr = color.unit_to_byte(r)
         local gg = color.unit_to_byte(g, 0)
         local bb = color.unit_to_byte(b, 0)
         local aa = color.unit_to_byte(a, 1)

         if not sdl3.SetRenderDrawColor(renderer, rr, gg, bb, aa) then
            rig.raise("failed to set draw color: " .. get_error_string())
         end
         if not sdl3.RenderClear(renderer) then
            rig.raise("failed to clear render target: " .. get_error_string())
         end
      end,
      present = function()
         if not sdl3.RenderPresent(renderer) then
            rig.raise("failed to present renderer: " .. get_error_string())
         end
      end,
      render_frame = function(self, render_fn)
         if render_fn ~= nil then
            render_fn()
         end
         if not sdl3.RenderPresent(renderer) then
            rig.raise("failed to present renderer: " .. get_error_string())
         end
      end,
      set_vsync = function(enabled)
         if not sdl3.SetRenderVSync(renderer, enabled and 1 or 0) then
            rig.raise("failed to set renderer vsync: " .. get_error_string())
         end
      end,
      release = function()
         sdl3.DestroyRenderer(renderer)
      end,
   }
end

local function create_gl_context(options, context)
   local window = context.runtime.capability_values["sdl3.window"]

   apply_gl_attributes(options.gl_attributes)

   local gl_context = sdl3.GL_CreateContext(window.ptr)
   if gl_context == nil then
      rig.raise("failed to create OpenGL context: " .. get_error_string())
   end

   if not sdl3.GL_MakeCurrent(window.ptr, gl_context) then
      sdl3.GL_DestroyContext(gl_context)
      rig.raise("failed to make OpenGL context current: " .. get_error_string())
   end

   local swap_interval = options.swap_interval
   if swap_interval == nil then
      swap_interval = 1
   end
   if not sdl3.GL_SetSwapInterval(gl_attribute_int(swap_interval)) then
      sdl3.GL_DestroyContext(gl_context)
      rig.raise("failed to set OpenGL swap interval: " .. get_error_string())
   end

   return {
      backend = "gl",
      window = window,
      context = gl_context,
      present = function()
         sdl3.GL_SwapWindow(window.ptr)
      end,
      render_frame = function(self, render_fn)
         if render_fn ~= nil then
            render_fn()
         end
         sdl3.GL_SwapWindow(window.ptr)
      end,
      set_swap_interval = function(interval)
         if not sdl3.GL_SetSwapInterval(gl_attribute_int(interval)) then
            rig.raise("failed to set OpenGL swap interval: " .. get_error_string())
         end
      end,
      get_proc_address = function(name)
         return M.get_gl_proc_address(name)
      end,
      release = function()
         sdl3.GL_DestroyContext(gl_context)
      end,
   }
end

local function create_gpu_context(options, context)
   local window = context.runtime.capability_values["sdl3.window"]
   local format_flags = options.shader_formats
   if format_flags == nil then
      format_flags = sdl3.GPU_SHADERFORMAT_SPIRV
   end
   local debug_mode = options.debug_mode and true or false
   local backend_name = options.backend_name

   if not sdl3.GPUSupportsShaderFormats(format_flags, backend_name) then
      rig.raise(build_gpu_support_error(format_flags, backend_name, get_error_string()))
   end

   local device = sdl3.CreateGPUDevice(format_flags, debug_mode, backend_name)
   if device == nil then
      rig.raise(build_gpu_support_error(format_flags, backend_name, get_error_string()))
   end

   if not sdl3.ClaimWindowForGPUDevice(device, window.ptr) then
      sdl3.DestroyGPUDevice(device)
      rig.raise("failed to claim SDL window for GPU device: " .. get_error_string())
   end

   return {
      backend = "gpu",
      window = window,
      device = device,
      render_frame = function(self, render_fn)
         local command_buffer = sdl3.AcquireGPUCommandBuffer(device)
         if command_buffer == nil then
            rig.raise("failed to acquire GPU command buffer: " .. get_error_string())
         end

         local swapchain_texture_out = ffi.new("SDL_GPUTexture *[1]")
         local width_out = ffi.new("Uint32[1]")
         local height_out = ffi.new("Uint32[1]")
         if not sdl3.WaitAndAcquireGPUSwapchainTexture(
            command_buffer,
            window.ptr,
            swapchain_texture_out,
            width_out,
            height_out
         ) then
            rig.raise("failed to acquire swapchain texture: " .. get_error_string())
         end

         local swapchain_texture = swapchain_texture_out[0]
         if swapchain_texture ~= nil and render_fn ~= nil then
            render_fn(
               command_buffer,
               swapchain_texture,
               tonumber(width_out[0]) or 0,
               tonumber(height_out[0]) or 0
            )
         end

         if not sdl3.SubmitGPUCommandBuffer(command_buffer) then
            rig.raise("failed to submit GPU command buffer: " .. get_error_string())
         end

         return swapchain_texture ~= nil
      end,
      release = function()
         sdl3.WaitForGPUIdle(device)
         sdl3.ReleaseWindowFromGPUDevice(device, window.ptr)
         sdl3.DestroyGPUDevice(device)
      end,
   }
end

function M.renderer_context_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "graphics.context", properties = { backend = "renderer" } },
      },
      requires = {
         { capability = "sdl3.window" },
      },
      create = function(context)
         return create_renderer_context(options, context)
      end,
      release = function(graphics)
         graphics.release()
      end,
   })
end

function M.gl_context_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "graphics.context", properties = { backend = "gl" } },
      },
      requires = {
         { capability = "sdl3.window" },
      },
      create = function(context)
         return create_gl_context(options, context)
      end,
      release = function(graphics)
         graphics.release()
      end,
   })
end

function M.gpu_context_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "graphics.context", properties = { backend = "gpu" } },
      },
      requires = {
         { capability = "sdl3.window" },
      },
      create = function(context)
         return create_gpu_context(options, context)
      end,
      release = function(graphics)
         graphics.release()
      end,
   })
end

--[ rendering service provider components ]--

function M.mesh_vertex_input_component(plugin, options)
   options = options or {}
   return graphics.provider_component(plugin, options, {
      capability = "mesh.vertex_input",
      backend = "gpu",
      provider = sdl3_gpu_mesh_service,
      bind = mesh.bind,
   })
end

function M.gpu_shader_stage_component(plugin, options)
   options = options or {}
   return graphics.provider_component(plugin, options, {
      capability = "shader.stage",
      backend = "gpu",
      make = make_shader_stage_service_sdl3_gpu,
      bind = shader.bind,
   })
end

function M.gl_shader_stage_component(plugin, options)
   options = options or {}
   return graphics.provider_component(plugin, options, {
      capability = "shader.stage",
      backend = "gl",
      provider = shader_stage_service_sdl3_gl,
      bind = shader.bind,
   })
end

function M.font_renderer_component(plugin, options)
   options = options or {}
   return graphics.provider_component(plugin, options, {
      capability = "font.renderer",
      backend = "renderer",
      make = make_sdl3_font_provider,
      bind = font.bind,
   })
end

function M.gl_font_renderer_component(plugin, options)
   options = options or {}
   return graphics.provider_component(plugin, options, {
      capability = "font.renderer",
      backend = "gl",
      make = make_sdl3_gl_font_provider,
      bind = font.bind,
      -- The GL font provider issues GL calls during creation, drawing, and
      -- release, so it must outlive the resolver's release.
      requires = {
         { capability = "gl.resolver" },
      },
      release = function()
         destroy_gl_font_backend_state()
      end,
   })
end

function M.gl_resolver_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "gl.resolver" },
      },
      requires = {
         {
            capability = "graphics.context",
            properties = { backend = "gl" },
         },
      },
      create = function()
         local gl = require("gl")
         gl.set_resolver(gl_resolver_service_sdl3_gl)
         return gl_resolver_service_sdl3_gl
      end,
      release = function()
         require("gl").clear_resolver()
      end,
   })
end

--[ render scene implementations ]--

-- The OpenGL scene implementation lives in `glx` (see `glx.RenderScene`). This
-- component selects it for the GL graphics context.
function M.gl_scene_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      provides = {
         { capability = "render.scene.impl", properties = { backend = "gl" } },
      },
      requires = {
         { capability = "graphics.context", properties = { backend = "gl" } },
         { capability = "gl.resolver" },
      },
      create = function()
         return glx.RenderScene
      end,
   })
end

--[ default mesh shaders ]--

local gl_mesh_vertex_source = [[
#version 330 core

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_color;

out vec3 out_color;

uniform mat4 u_mvp;

void main()
{
   gl_Position = u_mvp * vec4(in_position, 1.0);
   out_color = in_color;
}
]]

local gl_mesh_fragment_source = [[
#version 330 core

in vec3 out_color;
out vec4 frag_color;

void main()
{
   frag_color = vec4(out_color, 1.0);
}
]]

local gpu_mesh_vertex_source = [[
#version 450

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_color;

layout(location = 0) out vec3 out_color;

layout(set = 1, binding = 0) uniform Camera {
   mat4 mvp;
} camera;

void main()
{
   gl_Position = camera.mvp * vec4(in_position, 1.0);
   out_color = in_color;
}
]]

local gpu_mesh_fragment_source = [[
#version 450

layout(location = 0) in vec3 in_color;
layout(location = 0) out vec4 out_color;

void main()
{
   out_color = vec4(in_color, 1.0);
}
]]

-- Textured variants of the built-in material. They add a UV attribute at
-- location 2 and sample the texture through the conventional `u_texture`
-- uniform/sampler at slot 0.
local gl_mesh_textured_vertex_source = [[
#version 330 core

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_color;
layout(location = 2) in vec2 in_uv;

out vec3 out_color;
out vec2 out_uv;

uniform mat4 u_mvp;

void main()
{
   gl_Position = u_mvp * vec4(in_position, 1.0);
   out_color = in_color;
   out_uv = in_uv;
}
]]

local gl_mesh_textured_fragment_source = [[
#version 330 core

in vec3 out_color;
in vec2 out_uv;
out vec4 frag_color;

uniform sampler2D u_texture;

void main()
{
   frag_color = vec4(out_color, 1.0) * texture(u_texture, out_uv);
}
]]

local gpu_mesh_textured_vertex_source = [[
#version 450

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_color;
layout(location = 2) in vec2 in_uv;

layout(location = 0) out vec3 out_color;
layout(location = 1) out vec2 out_uv;

layout(set = 1, binding = 0) uniform Camera {
   mat4 mvp;
} camera;

void main()
{
   gl_Position = camera.mvp * vec4(in_position, 1.0);
   out_color = in_color;
   out_uv = in_uv;
}
]]

local gpu_mesh_textured_fragment_source = [[
#version 450

layout(location = 0) in vec3 in_color;
layout(location = 1) in vec2 in_uv;
layout(location = 0) out vec4 out_color;

layout(set = 2, binding = 0) uniform sampler2D u_texture;

void main()
{
   out_color = vec4(in_color, 1.0) * texture(u_texture, in_uv);
}
]]

local gl_builtin_material = {
   unlit = {
      vertex = gl_mesh_vertex_source,
      fragment = gl_mesh_fragment_source,
   },
   textured = {
      vertex = gl_mesh_textured_vertex_source,
      fragment = gl_mesh_textured_fragment_source,
   },
}

local gpu_builtin_material = {
   unlit = {
      vertex = gpu_mesh_vertex_source,
      fragment = gpu_mesh_fragment_source,
   },
   textured = {
      vertex = gpu_mesh_textured_vertex_source,
      fragment = gpu_mesh_textured_fragment_source,
   },
}

local function release_scope(scope)
   local errors = scope:release()
   if errors ~= nil and #errors > 0 then
      error(table.concat(errors, "\n"), 0)
   end
end

--[ mesh factories ]--

local function gl_primitive(gl, topology)
   if topology == "lines" then
      return gl.LINES
   end
   if topology == "line_strip" then
      return gl.LINE_STRIP
   end
   return gl.TRIANGLES
end

--[ texture factories ]--

local function gl_filter(gl, filter)
   if filter == "nearest" then
      return gl.NEAREST
   end
   return gl.LINEAR
end

local function gl_wrap(gl, wrap)
   if wrap == "repeat" then
      return gl.REPEAT
   end
   return gl.CLAMP_TO_EDGE
end

-- Turns `render.texture` values into GL textures, sharing one texture per value
-- through the owning scope. Samplers are folded into the GL texture object, so
-- binding the texture also selects its filtering and addressing mode.
local function make_gl_texture_factory(scope)
   local cache = {}

   return {
      create = function(texture)
         if type(texture) ~= "table" or texture.kind ~= "render.texture" then
            rig.raise("render.texture provider expects a render.texture value")
         end

         local cached = cache[texture]
         if cached ~= nil then
            return cached
         end

         local gl = require("gl")
         local image = texture.image
         local handle = glx.Texture2D()
         scope:adopt(handle, function(_, resource)
            resource:release()
         end)

         handle:bind(0)
         handle:parameter(gl.TEXTURE_MIN_FILTER, gl_filter(gl, texture.filter))
         handle:parameter(gl.TEXTURE_MAG_FILTER, gl_filter(gl, texture.filter))
         handle:parameter(gl.TEXTURE_WRAP_S, gl_wrap(gl, texture.wrap))
         handle:parameter(gl.TEXTURE_WRAP_T, gl_wrap(gl, texture.wrap))
         handle:image(
            0,
            gl.RGBA8,
            image.width,
            image.height,
            gl.RGBA,
            gl.UNSIGNED_BYTE,
            image.pixels
         )

         local value = {
            width = image.width,
            height = image.height,
            bind = function(_, unit)
               handle:bind(unit or 0)
            end,
         }
         cache[texture] = value
         return value
      end,
   }
end

-- Turns `render.target` values into a GL color texture plus a framebuffer,
-- sharing one surface per value. The color texture is top-down for sampling: a
-- pass renders into the framebuffer with a flipped projection, so the resulting
-- texture matches the convention of uploaded images.
local function make_gl_target_factory(scope)
   local cache = {}

   return {
      create = function(target)
         if type(target) ~= "table" or target.kind ~= "render.target" then
            rig.raise("render.target provider expects a render.target value")
         end

         local cached = cache[target]
         if cached ~= nil then
            return cached
         end

         local gl = require("gl")
         local handle = glx.Texture2D()
         scope:adopt(handle, function(_, resource)
            resource:release()
         end)

         handle:bind(0)
         handle:parameter(gl.TEXTURE_MIN_FILTER, gl_filter(gl, target.filter))
         handle:parameter(gl.TEXTURE_MAG_FILTER, gl_filter(gl, target.filter))
         handle:parameter(gl.TEXTURE_WRAP_S, gl_wrap(gl, target.wrap))
         handle:parameter(gl.TEXTURE_WRAP_T, gl_wrap(gl, target.wrap))
         handle:image(
            0,
            gl.RGBA8,
            target.width,
            target.height,
            gl.RGBA,
            gl.UNSIGNED_BYTE,
            nil
         )

         local framebuffer = glx.Framebuffer()
         scope:adopt(framebuffer, function(_, resource)
            resource:release()
         end)
         framebuffer:color(handle)
         if target.depth then
            framebuffer:depth(target.width, target.height)
         end
         framebuffer:check()

         local texture_handle = {
            width = target.width,
            height = target.height,
            flip_v = false,
            bind = function(_, unit)
               handle:bind(unit or 0)
            end,
         }

         local value = {
            width = target.width,
            height = target.height,
            flip_v = true,
            framebuffer = framebuffer,
            texture = texture_handle,
         }
         cache[target] = value
         return value
      end,
   }
end

local function make_gl_mesh_factory(shader_provider, scope, texture_factory, target_factory)
   return {
      create = function(mesh, material)
         local gl = require("gl")

         local texture_handle =
            render.resolve_material_texture(material, texture_factory, target_factory)

         local vertex_source, fragment_source, label = render.material_sources(
            mesh,
            material,
            texture_handle ~= nil,
            gl_builtin_material
         )

         local vertex_stage = shader_provider:create_stage({
            language = material and material.language or "glsl",
            stage = "vertex",
            source_name = label .. ".vert.glsl",
            source = vertex_source,
         })
         local fragment_stage = shader_provider:create_stage({
            language = material and material.language or "glsl",
            stage = "fragment",
            source_name = label .. ".frag.glsl",
            source = fragment_source,
         })

         local program = glx.Program {
            shaders = { vertex_stage, fragment_stage },
         }
         scope:adopt(program, function(_, resource)
            resource:release()
         end)

         local vbo = glx.Buffer { target = gl.ARRAY_BUFFER }
         scope:adopt(vbo, function(_, resource)
            resource:release()
         end)

         local vao = glx.VertexArray()
         scope:adopt(vao, function(_, resource)
            resource:release()
         end)

         vao:bind()
         vbo:set_data(mesh.vertex_blob, gl.STATIC_DRAW)
         vao:attribute(
            0,
            3,
            gl.FLOAT,
            gl.FALSE,
            mesh.vertex_stride,
            mesh.attribute_offsets.position
         )
         vao:attribute(
            1,
            3,
            gl.FLOAT,
            gl.FALSE,
            mesh.vertex_stride,
            mesh.attribute_offsets.color
         )
         if mesh.attribute_offsets.uv ~= nil then
            vao:attribute(
               2,
               2,
               gl.FLOAT,
               gl.FALSE,
               mesh.vertex_stride,
               mesh.attribute_offsets.uv
            )
         end

         local primitive = gl_primitive(gl, mesh.topology)
         local has_texture_uniform = texture_handle ~= nil
            and program:uniform_location("u_texture") >= 0

         return {
            draw = function(_, surface, mvp)
               program:use()
               program:set_uniform_matrix4fv("u_mvp", mvp)
               if texture_handle ~= nil then
                  texture_handle:bind(0)
                  if has_texture_uniform then
                     program:set_uniform1i("u_texture", 0)
                  end
               end
               vao:bind()
               gl.DrawArrays(primitive, 0, mesh.vertex_count)
            end,
         }
      end,
   }
end

function M.gl_texture_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      provides = {
         { capability = "render.texture", properties = { backend = "gl" } },
      },
      requires = {
         { capability = "graphics.context", properties = { backend = "gl" } },
         { capability = "gl.resolver" },
      },
      create = function(context)
         local scope = rig.ResourceScope(context, "gl texture factory resources")
         context.adopt(scope, release_scope)
         return make_gl_texture_factory(scope)
      end,
   })
end

function M.gl_target_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      provides = {
         { capability = "render.target", properties = { backend = "gl" } },
      },
      requires = {
         { capability = "graphics.context", properties = { backend = "gl" } },
         { capability = "gl.resolver" },
      },
      create = function(context)
         local scope = rig.ResourceScope(context, "gl target factory resources")
         context.adopt(scope, release_scope)
         return make_gl_target_factory(scope)
      end,
   })
end

function M.gl_mesh_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      provides = {
         { capability = "render.mesh", properties = { backend = "gl" } },
      },
      requires = {
         { capability = "graphics.context", properties = { backend = "gl" } },
         { capability = "gl.resolver" },
         { capability = "shader.stage" },
         { capability = "render.texture", optional = true },
         { capability = "render.target", optional = true },
      },
      create = function(context)
         local scope = rig.ResourceScope(context, "gl mesh factory resources")
         context.adopt(scope, release_scope)
         return make_gl_mesh_factory(
            context:capability("shader.stage"),
            scope,
            context:capability("render.texture"),
            context:capability("render.target")
         )
      end,
   })
end

--[ GPU render scene ]--

-- The SDL_GPU specialization of the scene interface. It owns the depth target
-- and the render pass that its drawables record into.
local GpuRenderScene = rig.Class(scene.RenderScene)
M.GpuRenderScene = GpuRenderScene

function GpuRenderScene:init(options)
   self:super().init(self, options)

   self.device = self.graphics.device
   self.window = self.graphics.window
   self.width = 1
   self.height = 1
   self.depth_format = nil
   self.depth_texture = nil
   self.depth_width = 0
   self.depth_height = 0
   self.command_buffer = nil
   self.pass = nil
   self.swapchain_texture = nil
   self.swapchain_width = 1
   self.swapchain_height = 1
   self.gpu_resources = M.ResourceScope(self.device, "gpu scene resources")
   if self.adopt ~= nil then
      self.adopt(self.gpu_resources, release_scope)
   end
end

function GpuRenderScene:ensure_depth_texture(width, height)
   if self.depth_texture ~= nil
      and self.depth_width == width
      and self.depth_height == height then
      return
   end

   if self.depth_format == nil then
      self.depth_format = M.choose_depth_format(self.device)
   end

   self.depth_texture = self.gpu_resources:replace("depth_texture",
      M.create_depth_texture(self.device, width, height, self.depth_format),
      function(device, resource)
         sdl3.ReleaseGPUTexture(device, resource)
      end)
   self.depth_width = width
   self.depth_height = height
end

local function build_gpu_color_target_info(texture, r, g, b, a)
   local info = ffi.new("SDL_GPUColorTargetInfo[1]")
   info[0].texture = texture
   info[0].mip_level = 0
   info[0].layer_or_depth_plane = 0
   info[0].clear_color.r = r
   info[0].clear_color.g = g
   info[0].clear_color.b = b
   info[0].clear_color.a = a
   info[0].load_op = sdl3.GPU_LOADOP_CLEAR
   info[0].store_op = sdl3.GPU_STOREOP_STORE
   info[0].resolve_texture = nil
   info[0].resolve_mip_level = 0
   info[0].resolve_layer = 0
   info[0].cycle = false
   info[0].cycle_resolve_texture = false
   return info
end

local function build_gpu_depth_target_info(texture)
   local info = ffi.new("SDL_GPUDepthStencilTargetInfo[1]")
   info[0].texture = texture
   info[0].clear_depth = 1.0
   info[0].load_op = sdl3.GPU_LOADOP_CLEAR
   info[0].store_op = sdl3.GPU_STOREOP_DONT_CARE
   info[0].stencil_load_op = sdl3.GPU_LOADOP_DONT_CARE
   info[0].stencil_store_op = sdl3.GPU_STOREOP_DONT_CARE
   info[0].cycle = false
   info[0].clear_stencil = 0
   info[0].mip_level = 0
   info[0].layer = 0
   return info
end

function GpuRenderScene:begin_pass(color_texture, depth_texture)
   local r, g, b, a = self.background_color:to_rgbaf()
   local color_target_info = build_gpu_color_target_info(color_texture, r, g, b, a)
   local depth_target_info = nil
   if depth_texture ~= nil then
      depth_target_info = build_gpu_depth_target_info(depth_texture)
   end

   self.pass = sdl3.BeginGPURenderPass(
      self.command_buffer,
      color_target_info,
      1,
      depth_target_info
   )
   if self.pass == nil then
      rig.raise("failed to begin GPU render pass: " .. M.get_error())
   end
end

function GpuRenderScene:begin_frame(command_buffer, swapchain_texture, width, height)
   self.width = math.max(1, tonumber(width) or 1)
   self.height = math.max(1, tonumber(height) or 1)
   self:ensure_depth_texture(self.width, self.height)
   self.command_buffer = command_buffer
   self.swapchain_texture = swapchain_texture
   self.swapchain_width = self.width
   self.swapchain_height = self.height
   self:begin_pass(swapchain_texture, self.depth_texture)
end

function GpuRenderScene:enter_target(handle)
   if self.pass ~= nil then
      sdl3.EndGPURenderPass(self.pass)
      self.pass = nil
   end
   self:begin_pass(handle.color_texture, handle.depth_texture)
end

function GpuRenderScene:leave_target(handle)
   if self.pass ~= nil then
      sdl3.EndGPURenderPass(self.pass)
      self.pass = nil
   end
   self:begin_pass(self.swapchain_texture, self.depth_texture)
end

function GpuRenderScene:end_frame()
   if self.pass ~= nil then
      sdl3.EndGPURenderPass(self.pass)
      self.pass = nil
   end
   self.command_buffer = nil
   self.swapchain_texture = nil
end

function M.gpu_scene_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      provides = {
         { capability = "render.scene.impl", properties = { backend = "gpu" } },
      },
      requires = {
         { capability = "graphics.context", properties = { backend = "gpu" } },
      },
      create = function()
         return GpuRenderScene
      end,
   })
end

local function gpu_primitive(topology)
   if topology == "lines" then
      return sdl3.GPU_PRIMITIVETYPE_LINELIST
   end
   if topology == "line_strip" then
      return sdl3.GPU_PRIMITIVETYPE_LINESTRIP
   end
   return sdl3.GPU_PRIMITIVETYPE_TRIANGLELIST
end

local function gpu_filter(filter)
   if filter == "nearest" then
      return sdl3.GPU_FILTER_NEAREST
   end
   return sdl3.GPU_FILTER_LINEAR
end

local function gpu_address_mode(wrap)
   if wrap == "repeat" then
      return sdl3.GPU_SAMPLERADDRESSMODE_REPEAT
   end
   if wrap == "mirror" then
      return sdl3.GPU_SAMPLERADDRESSMODE_MIRRORED_REPEAT
   end
   return sdl3.GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE
end

-- Turns `render.texture` values into SDL_GPU textures plus their samplers,
-- sharing one pair per value through the owning scope. Samplers are explicit on
-- SDL_GPU, so the value carries both.
local function create_gpu_sampler(device, scope, filter, wrap)
   local sampler_info = ffi.new("SDL_GPUSamplerCreateInfo[1]")
   sampler_info[0].min_filter = gpu_filter(filter)
   sampler_info[0].mag_filter = gpu_filter(filter)
   sampler_info[0].mipmap_mode = sdl3.GPU_SAMPLERMIPMAPMODE_NEAREST
   sampler_info[0].address_mode_u = gpu_address_mode(wrap)
   sampler_info[0].address_mode_v = gpu_address_mode(wrap)
   sampler_info[0].address_mode_w = gpu_address_mode(wrap)
   sampler_info[0].mip_lod_bias = 0.0
   sampler_info[0].max_anisotropy = 0.0
   sampler_info[0].compare_op = sdl3.GPU_COMPAREOP_ALWAYS
   sampler_info[0].min_lod = 0.0
   sampler_info[0].max_lod = 1000.0
   sampler_info[0].enable_anisotropy = false
   sampler_info[0].enable_compare = false
   sampler_info[0].padding1 = 0
   sampler_info[0].padding2 = 0
   sampler_info[0].props = 0

   local sampler = sdl3.CreateGPUSampler(device, sampler_info)
   if sampler == nil then
      rig.raise("failed to create GPU sampler: " .. get_error_string())
   end
   scope:adopt(sampler, function(dev, resource)
      sdl3.ReleaseGPUSampler(dev, resource)
   end)
   return sampler
end

local function make_gpu_texture_factory(options)
   local device = options.device
   local scope = options.scope
   local cache = {}

   return {
      create = function(texture)
         if type(texture) ~= "table" or texture.kind ~= "render.texture" then
            rig.raise("render.texture provider expects a render.texture value")
         end

         local cached = cache[texture]
         if cached ~= nil then
            return cached
         end

         local image = texture.image

         local create_info = ffi.new("SDL_GPUTextureCreateInfo[1]")
         create_info[0].type = sdl3.GPU_TEXTURETYPE_2D
         create_info[0].format = sdl3.GPU_TEXTUREFORMAT_R8G8B8A8_UNORM
         create_info[0].usage = sdl3.GPU_TEXTUREUSAGE_SAMPLER
         create_info[0].width = image.width
         create_info[0].height = image.height
         create_info[0].layer_count_or_depth = 1
         create_info[0].num_levels = 1
         create_info[0].sample_count = sdl3.GPU_SAMPLECOUNT_1
         create_info[0].props = 0

         local gpu_texture = sdl3.CreateGPUTexture(device, create_info)
         if gpu_texture == nil then
            rig.raise("failed to create GPU texture: " .. get_error_string())
         end
         scope:adopt(gpu_texture, function(dev, resource)
            sdl3.ReleaseGPUTexture(dev, resource)
         end)
         M.upload_to_gpu_texture(
            device,
            gpu_texture,
            image.pixels,
            image.width,
            image.height
         )

         local sampler = create_gpu_sampler(device, scope, texture.filter, texture.wrap)

         local binding = ffi.new("SDL_GPUTextureSamplerBinding[1]")
         binding[0].texture = gpu_texture
         binding[0].sampler = sampler

         local value = {
            width = image.width,
            height = image.height,
            bind = function(_, pass, slot)
               sdl3.BindGPUFragmentSamplers(pass, slot or 0, binding, 1)
            end,
         }
         cache[texture] = value
         return value
      end,
   }
end

-- Turns `render.target` values into an SDL_GPU color texture (sampleable and a
-- render target) plus an optional depth texture, sharing one surface per value.
-- The color texture uses the swapchain format so mesh pipelines built for the
-- window also match the offscreen pass.
local function make_gpu_target_factory(options)
   local device = options.device
   local window = options.window
   local scope = options.scope
   local cache = {}

   return {
      create = function(target)
         if type(target) ~= "table" or target.kind ~= "render.target" then
            rig.raise("render.target provider expects a render.target value")
         end

         local cached = cache[target]
         if cached ~= nil then
            return cached
         end

         local format = sdl3.GetGPUSwapchainTextureFormat(device, window.ptr)
         local create_info = ffi.new("SDL_GPUTextureCreateInfo[1]")
         create_info[0].type = sdl3.GPU_TEXTURETYPE_2D
         create_info[0].format = format
         create_info[0].usage = bit.bor(
            sdl3.GPU_TEXTUREUSAGE_COLOR_TARGET,
            sdl3.GPU_TEXTUREUSAGE_SAMPLER
         )
         create_info[0].width = target.width
         create_info[0].height = target.height
         create_info[0].layer_count_or_depth = 1
         create_info[0].num_levels = 1
         create_info[0].sample_count = sdl3.GPU_SAMPLECOUNT_1
         create_info[0].props = 0

         local color_texture = sdl3.CreateGPUTexture(device, create_info)
         if color_texture == nil then
            rig.raise("failed to create GPU render target: " .. get_error_string())
         end
         scope:adopt(color_texture, function(dev, resource)
            sdl3.ReleaseGPUTexture(dev, resource)
         end)

         local depth_texture = nil
         if target.depth then
            depth_texture = M.create_depth_texture(
               device,
               target.width,
               target.height
            )
            scope:adopt(depth_texture, function(dev, resource)
               sdl3.ReleaseGPUTexture(dev, resource)
            end)
         end

         local sampler =
            create_gpu_sampler(device, scope, target.filter, target.wrap)
         local binding = ffi.new("SDL_GPUTextureSamplerBinding[1]")
         binding[0].texture = color_texture
         binding[0].sampler = sampler

         local texture_handle = {
            width = target.width,
            height = target.height,
            flip_v = false,
            bind = function(_, pass, slot)
               sdl3.BindGPUFragmentSamplers(pass, slot or 0, binding, 1)
            end,
         }

         local value = {
            width = target.width,
            height = target.height,
            flip_v = false,
            color_texture = color_texture,
            depth_texture = depth_texture,
            texture = texture_handle,
         }
         cache[target] = value
         return value
      end,
   }
end

local function make_gpu_mesh_factory(options)
   local device = options.device
   local window = options.window
   local shader_provider = options.shader_provider
   local mesh_provider = options.mesh_provider
   local texture_factory = options.texture_factory
   local target_factory = options.target_factory
   local scope = options.scope

   return {
      create = function(mesh, material)
         local vertex_input = mesh_provider:build_vertex_input(mesh)

         local texture_handle =
            render.resolve_material_texture(material, texture_factory, target_factory)

         local vertex_source, fragment_source, label = render.material_sources(
            mesh,
            material,
            texture_handle ~= nil,
            gpu_builtin_material
         )

         local vertex_stage = shader_provider:create_stage(shader.compile {
            language = material and material.language or "glsl",
            stage = "vertex",
            source_name = label .. ".vert.glsl",
            source = vertex_source,
         })
         scope:adopt(vertex_stage, function(_, resource)
            shader_provider:destroy_stage(resource)
         end)

         local fragment_stage = shader_provider:create_stage(shader.compile {
            language = material and material.language or "glsl",
            stage = "fragment",
            source_name = label .. ".frag.glsl",
            source = fragment_source,
         })
         scope:adopt(fragment_stage, function(_, resource)
            shader_provider:destroy_stage(resource)
         end)

         local swapchain_format = sdl3.GetGPUSwapchainTextureFormat(
            device,
            window.ptr
         )
         local depth_format = M.choose_depth_format(device)

         local pipeline = scope:create_graphics_pipeline {
            vertex_shader = vertex_stage,
            fragment_shader = fragment_stage,
            vertex_input = vertex_input,
            primitive_type = gpu_primitive(mesh.topology),
            rasterizer_state = {
               fill_mode = sdl3.GPU_FILLMODE_FILL,
               cull_mode = sdl3.GPU_CULLMODE_NONE,
               front_face = sdl3.GPU_FRONTFACE_COUNTER_CLOCKWISE,
               enable_depth_bias = false,
               enable_depth_clip = true,
            },
            multisample_state = {
               sample_count = sdl3.GPU_SAMPLECOUNT_1,
               sample_mask = 0,
               enable_mask = false,
               enable_alpha_to_coverage = false,
            },
            depth_stencil_state = {
               compare_op = sdl3.GPU_COMPAREOP_LESS,
               enable_depth_test = true,
               enable_depth_write = true,
               enable_stencil_test = false,
            },
            target_info = {
               color_target_descriptions = {
                  { format = swapchain_format },
               },
               depth_stencil_format = depth_format,
               has_depth_stencil_target = true,
            },
            props = 0,
         }

         local vertex_buffer = scope:create_gpu_buffer {
            usage = sdl3.GPU_BUFFERUSAGE_VERTEX,
            size = #mesh.vertex_blob,
            props = 0,
         }
         M.upload_to_gpu_buffer(device, vertex_buffer, mesh.vertex_blob)

         local binding = ffi.new("SDL_GPUBufferBinding[1]")
         binding[0].buffer = vertex_buffer
         binding[0].offset = 0

         return {
            draw = function(_, surface, mvp)
               sdl3.PushGPUVertexUniformData(
                  surface.command_buffer,
                  0,
                  mvp,
                  ffi.sizeof(mvp)
               )
               sdl3.BindGPUGraphicsPipeline(surface.pass, pipeline)
               sdl3.BindGPUVertexBuffers(surface.pass, 0, binding, 1)
               if texture_handle ~= nil then
                  texture_handle:bind(surface.pass, 0)
               end
               sdl3.DrawGPUPrimitives(
                  surface.pass,
                  mesh.vertex_count,
                  1,
                  0,
                  0
               )
            end,
         }
      end,
   }
end

--[ GPU font backend ]--

-- The SDL_GPU font pipeline. It draws one screen-space textured quad per packed
-- glyph, generating the quad from `gl_VertexIndex` so no vertex buffer is needed;
-- per-glyph rect/UV/color/view data is pushed as a vertex uniform. The draw lands
-- in the active render pass owned by the GPU render scene.

local gpu_font_vertex_source = [[
#version 450

layout(std140, set = 1, binding = 0) uniform FontDraw {
   vec4 rect;
   vec4 uv;
   vec4 color;
   vec4 view;
} draw;

layout(location = 0) out vec2 out_uv;
layout(location = 1) out vec4 out_color;

void main()
{
   vec2 corners[6] = vec2[6](
      vec2(0.0, 0.0),
      vec2(1.0, 0.0),
      vec2(1.0, 1.0),
      vec2(0.0, 0.0),
      vec2(1.0, 1.0),
      vec2(0.0, 1.0)
   );

   vec2 corner = corners[gl_VertexIndex];
   vec2 position = draw.rect.xy + corner * draw.rect.zw;
   vec2 clip = vec2(
      position.x / draw.view.x * 2.0 - 1.0,
      1.0 - position.y / draw.view.y * 2.0
   );

   gl_Position = vec4(clip, 0.0, 1.0);
   out_uv = mix(draw.uv.xy, draw.uv.zw, corner);
   out_color = draw.color;
}
]]

local gpu_font_fragment_source = [[
#version 450

layout(location = 0) in vec2 in_uv;
layout(location = 1) in vec4 in_color;
layout(location = 0) out vec4 out_color;

layout(set = 2, binding = 0) uniform sampler2D u_atlas;

void main()
{
   float coverage = texture(u_atlas, in_uv).a;
   out_color = vec4(in_color.rgb, in_color.a * coverage);
}
]]

local function make_sdl3_gpu_font_provider(context)
   local graphics = context:capability("graphics.context")
   local device = graphics.device
   local window = graphics.window
   local scene = context:capability("render.scene")
   local shader_provider = context:capability("shader.stage")

   local scope = M.ResourceScope(device, "gpu font resources")
   context.adopt(scope, release_scope)

   local swapchain_format = sdl3.GetGPUSwapchainTextureFormat(device, window.ptr)
   local depth_format = M.choose_depth_format(device)

   local vertex_stage = shader_provider:create_stage(shader.compile {
      language = "glsl",
      stage = "vertex",
      source_name = "font.vert.glsl",
      source = gpu_font_vertex_source,
   })
   scope:adopt(vertex_stage, function(_, resource)
      shader_provider:destroy_stage(resource)
   end)

   local fragment_stage = shader_provider:create_stage(shader.compile {
      language = "glsl",
      stage = "fragment",
      source_name = "font.frag.glsl",
      source = gpu_font_fragment_source,
   })
   scope:adopt(fragment_stage, function(_, resource)
      shader_provider:destroy_stage(resource)
   end)

   local pipeline = scope:create_graphics_pipeline {
      vertex_shader = vertex_stage,
      fragment_shader = fragment_stage,
      vertex_input = M.build_vertex_input_state { buffers = {} },
      primitive_type = sdl3.GPU_PRIMITIVETYPE_TRIANGLELIST,
      rasterizer_state = {
         fill_mode = sdl3.GPU_FILLMODE_FILL,
         cull_mode = sdl3.GPU_CULLMODE_NONE,
         front_face = sdl3.GPU_FRONTFACE_COUNTER_CLOCKWISE,
         enable_depth_bias = false,
         enable_depth_clip = true,
      },
      multisample_state = {
         sample_count = sdl3.GPU_SAMPLECOUNT_1,
         sample_mask = 0,
         enable_mask = false,
         enable_alpha_to_coverage = false,
      },
      depth_stencil_state = {
         compare_op = sdl3.GPU_COMPAREOP_ALWAYS,
         enable_depth_test = false,
         enable_depth_write = false,
         enable_stencil_test = false,
      },
      target_info = {
         color_target_descriptions = {
            {
               format = swapchain_format,
               blend_state = {
                  src_color_blendfactor = sdl3.GPU_BLENDFACTOR_SRC_ALPHA,
                  dst_color_blendfactor = sdl3.GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                  color_blend_op = sdl3.GPU_BLENDOP_ADD,
                  src_alpha_blendfactor = sdl3.GPU_BLENDFACTOR_ONE,
                  dst_alpha_blendfactor = sdl3.GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                  alpha_blend_op = sdl3.GPU_BLENDOP_ADD,
                  color_write_mask = 0xF,
                  enable_blend = true,
                  enable_color_write_mask = false,
               },
            },
         },
         depth_stencil_format = depth_format,
         has_depth_stencil_target = true,
      },
      props = 0,
   }

   local sampler = create_gpu_sampler(device, scope, "linear", "clamp")
   local sampler_binding = ffi.new("SDL_GPUTextureSamplerBinding[1]")
   sampler_binding[0].sampler = sampler

   local draw_data = ffi.new("float[16]")

   local function upload_page_texture(text_renderer, texture, page, rgba)
      if texture == nil then
         local create_info = ffi.new("SDL_GPUTextureCreateInfo[1]")
         create_info[0].type = sdl3.GPU_TEXTURETYPE_2D
         create_info[0].format = sdl3.GPU_TEXTUREFORMAT_R8G8B8A8_UNORM
         create_info[0].usage = sdl3.GPU_TEXTUREUSAGE_SAMPLER
         create_info[0].width = page.width
         create_info[0].height = page.height
         create_info[0].layer_count_or_depth = 1
         create_info[0].num_levels = 1
         create_info[0].sample_count = sdl3.GPU_SAMPLECOUNT_1
         create_info[0].props = 0

         texture = sdl3.CreateGPUTexture(device, create_info)
         if texture == nil then
            rig.raise(
               "failed to create GPU font atlas texture: " .. get_error_string()
            )
         end
      end

      local bytes = ffi.string(rgba, page.width * page.height * 4)
      M.upload_to_gpu_texture(device, texture, bytes, page.width, page.height)
      return texture
   end

   local function destroy_page_texture(text_renderer, texture)
      if texture ~= nil then
         sdl3.ReleaseGPUTexture(device, texture)
      end
   end

   local function draw_packed_glyph(text_renderer, texture, packed, x, y, draw_color, scale)
      if packed.width <= 0 or packed.height <= 0 then
         return
      end

      local pass = scene ~= nil and scene.pass or nil
      local command_buffer = scene ~= nil and scene.command_buffer or nil
      if pass == nil or command_buffer == nil then
         rig.raise(
            "GPU font draws need an active render pass; draw text from the scene's on_overlay or a node draw"
         )
      end

      local width = scene.width or 1
      local height = scene.height or 1
      if width <= 0 or height <= 0 then
         return
      end

      draw_data[0] = x
      draw_data[1] = y
      draw_data[2] = packed.width * scale
      draw_data[3] = packed.height * scale
      draw_data[4] = packed.u0
      draw_data[5] = packed.v0
      draw_data[6] = packed.u1
      draw_data[7] = packed.v1
      draw_data[8] = draw_color.r / 255.0
      draw_data[9] = draw_color.g / 255.0
      draw_data[10] = draw_color.b / 255.0
      draw_data[11] = draw_color.a / 255.0
      draw_data[12] = width
      draw_data[13] = height
      draw_data[14] = 0.0
      draw_data[15] = 0.0

      sdl3.PushGPUVertexUniformData(
         command_buffer,
         0,
         draw_data,
         ffi.sizeof(draw_data)
      )
      sdl3.BindGPUGraphicsPipeline(pass, pipeline)
      sampler_binding[0].texture = texture
      sdl3.BindGPUFragmentSamplers(pass, 0, sampler_binding, 1)
      sdl3.DrawGPUPrimitives(pass, 6, 1, 0, 0)
   end

   return {
      upload_page_texture = upload_page_texture,
      destroy_page_texture = destroy_page_texture,
      draw_packed_glyph = draw_packed_glyph,
   }
end

function M.gpu_font_renderer_component(plugin, options)
   options = options or {}
   return graphics.provider_component(plugin, options, {
      capability = "font.renderer",
      backend = "gpu",
      make = make_sdl3_gpu_font_provider,
      bind = font.bind,
      requires = {
         { capability = "shader.stage" },
         -- Optional: text draws into the GPU render scene's active pass. Apps
         -- without a scene compile, but drawing text raises a clear error.
         { capability = "render.scene", optional = true },
      },
   })
end

function M.gpu_texture_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      provides = {
         { capability = "render.texture", properties = { backend = "gpu" } },
      },
      requires = {
         { capability = "graphics.context", properties = { backend = "gpu" } },
      },
      create = function(context)
         local graphics = context:capability("graphics.context")
         local scope =
            M.ResourceScope(graphics.device, "gpu texture factory resources")
         context.adopt(scope, release_scope)
         return make_gpu_texture_factory {
            device = graphics.device,
            scope = scope,
         }
      end,
   })
end

function M.gpu_target_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      provides = {
         { capability = "render.target", properties = { backend = "gpu" } },
      },
      requires = {
         { capability = "graphics.context", properties = { backend = "gpu" } },
      },
      create = function(context)
         local graphics = context:capability("graphics.context")
         local scope =
            M.ResourceScope(graphics.device, "gpu target factory resources")
         context.adopt(scope, release_scope)
         return make_gpu_target_factory {
            device = graphics.device,
            window = graphics.window,
            scope = scope,
         }
      end,
   })
end

function M.gpu_mesh_component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      provides = {
         { capability = "render.mesh", properties = { backend = "gpu" } },
      },
      requires = {
         { capability = "graphics.context", properties = { backend = "gpu" } },
         { capability = "shader.stage" },
         { capability = "mesh.vertex_input" },
         { capability = "render.texture", optional = true },
         { capability = "render.target", optional = true },
      },
      create = function(context)
         local graphics = context:capability("graphics.context")
         local scope = M.ResourceScope(graphics.device, "gpu mesh factory resources")
         context.adopt(scope, release_scope)

         return make_gpu_mesh_factory {
            device = graphics.device,
            window = graphics.window,
            shader_provider = context:capability("shader.stage"),
            mesh_provider = context:capability("mesh.vertex_input"),
            texture_factory = context:capability("render.texture"),
            target_factory = context:capability("render.target"),
            scope = scope,
         }
      end,
   })
end

--[ convenience bundles ]--

local function merge_window_props(base, override)
   local merged = {}
   if type(base) == "table" then
      for key, value in pairs(base) do
         merged[key] = value
      end
   end
   if type(override) == "table" then
      for key, value in pairs(override) do
         merged[key] = value
      end
   end
   return merged
end

local function add_core_components(builder, options)
   local clock = runtime.Clock {
      now = function()
         return current_time_seconds()
      end,
      monotonic = function()
         return current_monotonic_seconds()
      end,
   }

   runtime.headless_bundle(builder, {
      clock = clock,
      timer = options.timer,
   })
end

function M.bundle_sdl3(builder, options)
   options = options or {}
   local plugin = M.plugin()

   builder:use(plugin)
   builder:use(graphics.plugin())
   add_core_components(builder, options)
   builder:add(M.subsystem_component(plugin, {
      name = "sdl",
      init_flags = options.init_flags,
   }))
   builder:add(M.window_component(plugin, {
      name = "window",
      window_props = options.window_props,
   }))
   builder:add(M.input_component(plugin, { name = "input" }))
   builder:add(M.renderer_context_component(plugin, {
      name = "graphics",
      create_renderer = options.create_renderer,
   }))
   builder:add(M.font_renderer_component(plugin, { name = "font" }))
   builder:add(graphics.frame_component(plugin, {
      name = "frame",
      render = options.render,
      frame_profiler = options.frame_profiler,
   }))
   return builder
end

function M.bundle_sdl3_gl(builder, options)
   options = options or {}
   local plugin = M.plugin()
   local window_props = merge_window_props(options.window_props, {
      [sdl3.PROP_WINDOW_CREATE_OPENGL_BOOLEAN] = true,
   })

   builder:use(plugin)
   builder:use(graphics.plugin())
   add_core_components(builder, options)
   builder:add(M.subsystem_component(plugin, {
      name = "sdl",
      init_flags = options.init_flags,
   }))
   builder:add(M.window_component(plugin, {
      name = "window",
      window_props = window_props,
   }))
   builder:add(M.input_component(plugin, { name = "input" }))
   builder:add(M.gl_context_component(plugin, {
      name = "graphics",
      gl_attributes = options.gl_attributes,
      swap_interval = options.swap_interval,
   }))
   builder:add(M.gl_font_renderer_component(plugin, { name = "font" }))
   builder:add(M.gl_resolver_component(plugin, { name = "gl_resolver" }))
   builder:add(M.gl_shader_stage_component(plugin, { name = "shader" }))
   builder:add(M.gl_scene_component(plugin, {}))
   builder:add(M.gl_texture_component(plugin, {}))
   builder:add(M.gl_target_component(plugin, {}))
   builder:add(M.gl_mesh_component(plugin, {}))
   builder:add(graphics.frame_component(plugin, {
      name = "frame",
      render = options.render,
      frame_profiler = options.frame_profiler,
   }))
   return builder
end

function M.bundle_sdl3_gpu(builder, options)
   options = options or {}
   local plugin = M.plugin()

   builder:use(plugin)
   builder:use(graphics.plugin())
   add_core_components(builder, options)
   builder:add(M.subsystem_component(plugin, {
      name = "sdl",
      init_flags = options.init_flags,
   }))
   builder:add(M.window_component(plugin, {
      name = "window",
      window_props = options.window_props,
   }))
   builder:add(M.input_component(plugin, { name = "input" }))
   builder:add(M.gpu_context_component(plugin, {
      name = "graphics",
      shader_formats = options.shader_formats,
      debug_mode = options.debug_mode,
      backend_name = options.backend_name,
   }))
   builder:add(M.mesh_vertex_input_component(plugin, { name = "mesh" }))
   builder:add(M.gpu_shader_stage_component(plugin, { name = "shader" }))
   builder:add(M.gpu_font_renderer_component(plugin, { name = "font" }))
   builder:add(M.gpu_scene_component(plugin, {}))
   builder:add(M.gpu_texture_component(plugin, {}))
   builder:add(M.gpu_target_component(plugin, {}))
   builder:add(M.gpu_mesh_component(plugin, {}))
   builder:add(graphics.frame_component(plugin, {
      name = "frame",
      render = options.render,
      frame_profiler = options.frame_profiler,
   }))
   return builder
end

return M
