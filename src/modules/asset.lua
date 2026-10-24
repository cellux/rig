local M = ... or {}

local jpeg = require("jpeg")
local png = require("png")
local rig = require("rig")

-- Path-relative, cached asset loading. Paths are resolved against the directory
-- of the script that calls the asset function, so demos can ship alongside their
-- assets and be launched from anywhere. Loaded bytes are cached by canonical
-- path (rig.realpath), so repeated requests share one read.

local file_cache = {}
local image_cache = {}
local material_cache = {}
local mesh_cache = {}

local function caller_directory()
   -- user -> asset.<fn> -> caller_directory
   local source = rig.source_of(debug.getinfo(3, "S"))
   if source == nil then
      return ""
   end
   return rig.dirname(source)
end

local function resolve_relative(directory, path)
   if type(path) ~= "string" or path == "" then
      rig.raise("asset paths must be non-empty strings")
   end

   local resolved = rig.join_path(directory, path)
   local key = resolved
   if type(rig.realpath) == "function" then
      key = rig.realpath(resolved) or resolved
   end
   return resolved, key
end

local function load_file(resolved, key)
   local cached = file_cache[key]
   if cached ~= nil then
      return cached
   end

   local contents, err = rig.read_file(resolved)
   if contents == nil then
      rig.raise("asset: failed to read '%s': %s", resolved, err or "unknown error")
   end
   file_cache[key] = contents
   return contents
end

local function load_bytes(path)
   return load_file(resolve_relative(caller_directory(), path))
end

-- Resolves `path` against the calling script's directory and returns the path.
function M.path(path)
   return (resolve_relative(caller_directory(), path))
end

-- Raw file contents as a Lua string (cached). `text` is an alias.
M.bytes = load_bytes
M.text = load_bytes

-- Decodes image bytes, choosing the decoder by file extension (falling back to
-- trying PNG then JPEG).
local function decode_image(bytes, path, lower)
   if lower:match("%.png$") then
      return png.decode(bytes, path)
   end
   if lower:match("%.jpe?g$") then
      return jpeg.decode(bytes, path)
   end

   local image, err = png.decode(bytes, path)
   if image ~= nil then
      return image
   end
   local jpeg_image, jpeg_err = jpeg.decode(bytes, path)
   if jpeg_image ~= nil then
      return jpeg_image
   end
   return nil, err or jpeg_err
end

-- Loads and decodes an image relative to the script. Returns
-- `{ width, height, channels, pixels }`, cached by canonical path.
function M.image(path)
   local resolved, key = resolve_relative(caller_directory(), path)
   local cached = image_cache[key]
   if cached ~= nil then
      return cached
   end

   local bytes = load_file(resolved, key)
   local image, err = decode_image(bytes, resolved, resolved:lower())
   if image == nil then
      rig.raise(err)
   end
   image_cache[key] = image
   return image
end

-- Loads GLSL vertex/fragment sources relative to the script and returns a
-- `render.material`.
function M.material(spec)
   spec = spec or {}
   if type(spec.vertex) ~= "string" or type(spec.fragment) ~= "string" then
      rig.raise("asset.material requires vertex and fragment paths")
   end

   local directory = caller_directory()
   local vertex_resolved, vertex_key = resolve_relative(directory, spec.vertex)
   local fragment_resolved, fragment_key = resolve_relative(directory, spec.fragment)

   local cache_key = vertex_key .. "\0" .. fragment_key
   local cached = material_cache[cache_key]
   if cached ~= nil then
      return cached
   end

   local render = require("render")
   local material = render.material {
      name = spec.name,
      language = spec.language,
      vertex = load_file(vertex_resolved, vertex_key),
      fragment = load_file(fragment_resolved, fragment_key),
      texture = spec.texture,
   }
   material_cache[cache_key] = material
   return material
end

-- Loads a Wavefront OBJ mesh relative to the script and parses it through
-- `mesh.parse_obj`, cached by canonical path.
function M.mesh(path, options)
   local resolved, key = resolve_relative(caller_directory(), path)
   local cached = mesh_cache[key]
   if cached ~= nil then
      return cached
   end

   local text = load_file(resolved, key)
   local mesh = require("mesh")
   local parsed = mesh.parse_obj(text, options)
   mesh_cache[key] = parsed
   return parsed
end

return M