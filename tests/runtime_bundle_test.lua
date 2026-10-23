local test = require("test")
local runtime = require("runtime")
local rig = require("rig")
local uv = require("uv")
local sdl3x = require("sdl3x")

local function has_bindings(compiled, names)
   for i = 1, #names do
      test.truthy(compiled.plan.bindings[names[i]] ~= nil)
   end
end

test.case("sdl3 bundle composes the renderer stack", function()
   local builder = rig.runtime()
   sdl3x.bundle_sdl3(builder)
   local compiled = builder:execute(function() end):compile()

   has_bindings(compiled, {
      "sdl",
      "window",
      "input",
      "graphics",
      "font",
      "frame",
   })
   test.equal(
      compiled.plan.bindings.graphics.provides[1].properties.backend,
      "renderer"
   )
end)

test.case("sdl3_gl bundle composes the opengl stack", function()
   local builder = rig.runtime()
   sdl3x.bundle_sdl3_gl(builder)
   local compiled = builder:execute(function() end):compile()

   has_bindings(compiled, {
      "sdl",
      "window",
      "input",
      "graphics",
      "font",
      "gl_resolver",
      "shader",
      "frame",
   })
   test.equal(
      compiled.plan.bindings.graphics.provides[1].properties.backend,
      "gl"
   )
end)

test.case("sdl3_gpu bundle composes the gpu stack", function()
   local builder = rig.runtime()
   sdl3x.bundle_sdl3_gpu(builder)
   local compiled = builder:execute(function() end):compile()

   has_bindings(compiled, {
      "sdl",
      "window",
      "input",
      "graphics",
      "mesh",
      "shader",
      "frame",
   })
   test.equal(
      compiled.plan.bindings.graphics.provides[1].properties.backend,
      "gpu"
   )
end)

test.case("uv bundle composes the async stack", function()
   local builder = rig.runtime()
   uv.bundle_uv(builder)
   local compiled = builder:execute(function() end):compile()

   has_bindings(compiled, { "clock", "timer", "scheduler", "uv" })
end)

test.case("headless bundle composes a scheduler without I/O", function()
   local builder = rig.runtime()
   runtime.headless_bundle(builder)
   local compiled = builder:execute(function() end):compile()

   has_bindings(compiled, { "clock", "timer", "scheduler" })
   test.equal(compiled.plan.bindings.uv, nil)
end)

test.case("attaching a plugin alone adds no runtime behavior", function()
   local builder = rig.runtime()
   builder:use(sdl3x.plugin())
   local compiled = builder:execute(function() end):compile()

   test.equal(#compiled.plan.components, 0)
end)
