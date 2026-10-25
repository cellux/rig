local M = ... or {}

local png = require("png")
local rig = require("rig")
local runtime = require("runtime")

-- Screenshot capture is optional engine surface area. The render path itself is
-- unchanged; sketches only perform the per-frame flush when the feature flag is
-- enabled, so normal runs pay no screenshot cost.
local function flag_enabled(name)
   local value = os.getenv(name)
   if value == nil or value == "" or value == "0" then
      return false
   end
   local lower = string.lower(value)
   return lower ~= "false" and lower ~= "no" and lower ~= "off"
end

local ENABLED = flag_enabled("RIG_ENABLE_SCREENSHOTS")

local pending = {}
local auto_index = 0
local active_provider = nil

local function next_path()
   auto_index = auto_index + 1
   return ("screenshot-%04d.png"):format(auto_index)
end

local function normalize_request(path_or_options, options)
   local request
   if type(path_or_options) == "table" then
      request = {}
      for key, value in pairs(path_or_options) do
         request[key] = value
      end
      if options ~= nil then
         for key, value in pairs(options) do
            request[key] = value
         end
      end
   else
      request = {}
      if options ~= nil then
         for key, value in pairs(options) do
            request[key] = value
         end
      end
      request.path = path_or_options
   end

   if request.path == nil then
      request.path = next_path()
   end
   return request
end

local function write_file(path, bytes)
   local file, err = io.open(path, "wb")
   if file == nil then
      rig.raise("screenshot: failed to open '%s': %s", path, tostring(err))
   end
   local ok, write_err = file:write(bytes)
   file:close()
   if not ok then
      rig.raise("screenshot: failed to write '%s': %s", path, tostring(write_err))
   end
   return path
end

-- Declares the `screenshot.capture` capability. Backends provide implementations
-- through their own provider components; `screenshot.component` consumes one.
function M.plugin(spec)
   spec = spec or {}
   return runtime.plugin {
      id = spec.id or "screenshot",
      capabilities = {
         ["screenshot.capture"] = {},
      },
   }
end

-- Validates and returns a screenshot provider. A provider implements
-- `capture(surface, options) -> image` and owns its backend's readback details.
function M.bind(provider)
   if type(provider) ~= "table" or type(provider.capture) ~= "function" then
      rig.raise("screenshot provider must provide a capture(surface, options) method")
   end
   return provider
end

-- Consumes the `screenshot.capture` capability and installs the provider for the
-- backend-neutral helper functions. The provider is cleared on release.
function M.component(plugin, options)
   options = options or {}
   return runtime.descriptor(plugin, {
      name = options.name,
      requires = {
         { capability = "screenshot.capture" },
      },
      create = function(context)
         local provider = M.bind(context:capability("screenshot.capture"))
         active_provider = provider
         return provider
      end,
      release = function()
         active_provider = nil
      end,
   })
end

-- Installs a provider directly. Mostly useful for tests, tools, and hand-built
-- runtimes that do not use the component system.
function M.set_provider(provider)
   active_provider = M.bind(provider)
   return active_provider
end

function M.clear_provider()
   active_provider = nil
end

function M.provider()
   return active_provider
end

-- True when RIG_ENABLE_SCREENSHOTS enables the facility.
function M.enabled()
   return ENABLED
end

-- Captures the current surface immediately and returns a top-down RGBA image.
-- The caller is responsible for capturing before the backend presents the frame.
function M.capture(surface, options)
   if not ENABLED then
      rig.raise("screenshot.capture requires RIG_ENABLE_SCREENSHOTS")
   end
   if active_provider == nil then
      rig.raise("screenshot.capture requires a screenshot.capture provider")
   end
   return active_provider.capture(surface, options)
end

-- Encodes an RGBA image as PNG and writes it to `path`.
function M.write(path, image)
   if not ENABLED then
      rig.raise("screenshot.write requires RIG_ENABLE_SCREENSHOTS")
   end
   local bytes, err = png.encode(image, path)
   if bytes == nil then
      rig.raise("screenshot: %s", tostring(err))
   end
   return write_file(path, bytes)
end

-- Captures and writes in one call.
function M.save(surface, path_or_options, options)
   local request = normalize_request(path_or_options, options)
   local image = M.capture(surface, request)
   M.write(request.path, image)
   return request.path, image
end

-- Queues a capture for the end of the current frame. The sketch facade calls
-- `flush` after overlays and before presentation. Paths default to
-- `screenshot-NNNN.png` in the working directory.
function M.request(path_or_options, options)
   if not ENABLED then
      rig.raise("screenshot.request requires RIG_ENABLE_SCREENSHOTS")
   end
   local request = normalize_request(path_or_options, options)
   pending[#pending + 1] = request
   return request
end

-- Writes every queued capture using `app.surface`/`frame.surface`. Safe to call
-- when nothing is queued. No-op when the feature flag is disabled.
function M.flush(app, frame)
   if not ENABLED then
      return nil
   end
   if #pending == 0 then
      return {}
   end

   local surface = nil
   if app ~= nil then
      surface = app.surface or app.scene
   end
   if surface == nil and frame ~= nil then
      surface = frame.surface
   end
   if surface == nil then
      rig.raise("screenshot.flush requires a running app or a frame with a surface")
   end

   local requests = pending
   pending = {}
   for i = 1, #requests do
      local request = requests[i]
      local image = M.capture(surface, request)
      M.write(request.path, image)
   end
   return requests
end

-- Drops queued captures without writing them. Intended for tests and tools.
function M.clear()
   pending = {}
   auto_index = 0
end

return M
