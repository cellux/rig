local test = require("test")

local old_getenv = os.getenv
os.getenv = function(name)
   if name == "RIG_ENABLE_SCREENSHOTS" then
      return "1"
   end
   return old_getenv(name)
end
local screenshot = require("screenshot")
local png = require("png")
os.getenv = old_getenv

local function fake_image()
   return {
      width = 2,
      height = 2,
      channels = 4,
      pixels = string.char(
         255, 0, 0, 255,
         0, 255, 0, 255,
         0, 0, 255, 255,
         255, 255, 0, 255
      ),
   }
end

local function fake_provider()
   local calls = 0
   return {
      calls = function()
         return calls
      end,
      capture = function(_, options)
         calls = calls + 1
         local image = fake_image()
         if options and options.width then
            image.width = options.width
         end
         return image
      end,
   }
end

local function temp_path()
   local path = os.tmpname()
   os.remove(path)
   return path .. ".png"
end

test.case("screenshot provider is required for capture", function()
   screenshot.clear_provider()
   local ok, err = pcall(function()
      screenshot.capture({})
   end)
   test.falsey(ok)
   test.match(tostring(err), "screenshot%.capture provider")
end)

test.case("screenshot.save writes a decodable PNG through the provider", function()
   local provider = fake_provider()
   screenshot.set_provider(provider)

   local path = temp_path()
   local saved, image = screenshot.save({}, path)

   test.equal(saved, path)
   test.equal(image.width, 2)
   test.equal(image.height, 2)
   test.equal(provider.calls(), 1)

   local file = io.open(path, "rb")
   test.truthy(file ~= nil)
   local bytes = file:read("*a")
   file:close()
   os.remove(path)

   local decoded = png.decode(bytes, path)
   test.equal(decoded.width, 2)
   test.equal(decoded.height, 2)
   test.equal(string.byte(decoded.pixels, 1), 255)
   test.equal(string.byte(decoded.pixels, 2), 0)
   test.equal(string.byte(decoded.pixels, 3), 0)

   screenshot.clear_provider()
end)

test.case("screenshot.flush writes queued requests at end of frame", function()
   screenshot.clear()
   screenshot.clear_provider()
   local provider = fake_provider()
   screenshot.set_provider(provider)

   local path = temp_path()
   local request = screenshot.request(path)
   test.equal(request.path, path)

   local surface = {}
   local app = { surface = surface }
   local requests = screenshot.flush(app, { surface = surface })
   test.equal(#requests, 1)
   test.equal(provider.calls(), 1)

   local file = io.open(path, "rb")
   test.truthy(file ~= nil)
   local bytes = file:read("*a")
   file:close()
   os.remove(path)

   local image = png.decode(bytes, path)
   test.equal(image.width, 2)
   test.equal(image.height, 2)
   test.equal(#screenshot.flush(app, {}), 0)

   screenshot.clear_provider()
end)

test.case("screenshot.bind validates the provider contract", function()
   local ok, err = pcall(function()
      screenshot.bind({})
   end)
   test.falsey(ok)
   test.match(tostring(err), "capture")
end)

test.case("screenshot.component consumes the backend provider capability", function()
   local rig = require("rig")
   local runtime = require("runtime")

   screenshot.clear_provider()
   local plugin = screenshot.plugin()
   local backend_plugin = runtime.plugin {
      id = "fake_screenshot_backend",
      capabilities = {
         ["screenshot.capture"] = {},
      },
   }
   local provider = fake_provider()

   local seen = nil
   local compiled = rig.runtime()
      :use(plugin)
      :use(backend_plugin)
      :add(runtime.descriptor(backend_plugin, {
         name = "provider",
         provides = {
            { capability = "screenshot.capture" },
         },
         create = function()
            return provider
         end,
      }))
      :add(screenshot.component(plugin, { name = "screenshot" }))
      :execute(function()
         seen = screenshot.provider()
      end)
      :compile()

   compiled:start()
   test.equal(seen, provider)
   test.equal(screenshot.provider(), nil)
end)
