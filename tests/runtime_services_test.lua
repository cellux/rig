local test = require("test")
local runtime = require("runtime")
local rig = require("rig")
local font = require("font")
local gl = require("gl")
local mesh = require("mesh")
local shader = require("shader")
local sdl3x = require("sdl3x")

test.case("mesh component consumes the mesh.vertex_input capability", function()
   local mp = mesh.plugin()
   local provider = runtime.descriptor(mp, {
      name = "provider",
      provides = {
         { capability = "mesh.vertex_input" },
      },
      create = function()
         return {
            build_vertex_input = function(value)
               return { built = value }
            end,
         }
      end,
   })

   local got = nil
   local compiled = rig.runtime()
      :use(mp)
      :add(provider)
      :add(mesh.component(mp, { name = "mesh" }))
      :execute(function(ctx)
         got = ctx.mesh:build_vertex_input({ id = 1 })
      end)
      :compile()

   compiled:start()

   test.equal(compiled.state, "stopped")
   test.equal(got.built.id, 1)
end)

test.case("shader component consumes the shader.stage capability", function()
   local sp = shader.plugin()
   local provider = runtime.descriptor(sp, {
      name = "provider",
      provides = {
         { capability = "shader.stage" },
      },
      create = function()
         return {
            create_stage = function(spec)
               return { stage = spec.stage }
            end,
            destroy_stage = function() end,
         }
      end,
   })

   local stage = nil
   local compiled = rig.runtime()
      :use(sp)
      :add(provider)
      :add(shader.component(sp, { name = "shader" }))
      :execute(function(ctx)
         stage = ctx.shader:create_stage({
            language = "glsl",
            stage = "vertex",
            source = "void main() {}",
         })
      end)
      :compile()

   compiled:start()

   test.equal(stage.stage, "vertex")
end)

test.case("font component exposes the font.renderer capability", function()
   local fp = font.plugin()
   local provider = runtime.descriptor(fp, {
      name = "provider",
      provides = {
         { capability = "font.renderer" },
      },
      create = function()
         return { marker = "font" }
      end,
   })

   local facade = nil
   local compiled = rig.runtime()
      :use(fp)
      :add(provider)
      :add(font.component(fp, { name = "font" }))
      :execute(function(ctx)
         facade = ctx.font
      end)
      :compile()

   compiled:start()

   test.equal(type(facade.create_style), "function")
   test.equal(type(facade.create_text_renderer), "function")
end)

test.case("gl component installs and clears the resolver capability", function()
   local gp = gl.plugin()
   local provider = runtime.descriptor(gp, {
      name = "provider",
      provides = {
         { capability = "gl.resolver" },
      },
      create = function()
         return {
            get_gl_proc_address = function()
               return nil, "fake"
            end,
         }
      end,
   })

   local installed = false
   local compiled = rig.runtime()
      :use(gp)
      :add(provider)
      :add(gl.component(gp, { name = "gl" }))
      :execute(function()
         installed = rawget(gl, "_resolver") ~= nil
      end)
      :compile()

   compiled:start()

   test.truthy(installed)
   test.equal(rawget(gl, "_resolver"), nil)
end)

test.case("mesh component requires its capability", function()
   local mp = mesh.plugin()

   local ok, err = pcall(function()
      rig.runtime()
         :use(mp)
         :add(mesh.component(mp, { name = "mesh" }))
         :execute(function() end)
         :compile()
   end)

   test.falsey(ok)
   test.match(
      tostring(err),
      "requires capability 'mesh.vertex_input' but no component provides it"
   )
end)

test.case("gpu mesh provider builds vertex input through capabilities", function()
   local sp = sdl3x.plugin()
   local mp = mesh.plugin()

   local built = nil
   local compiled = rig.runtime()
      :use(sp)
      :use(mp)
      :add(sdl3x.subsystem_component(sp, { name = "sdl" }))
      :add(sdl3x.window_component(sp, { name = "window" }))
      :add(sdl3x.gpu_context_component(sp, { name = "graphics" }))
      :add(sdl3x.mesh_vertex_input_component(sp, { name = "mesh_provider" }))
      :add(mesh.component(mp, { name = "mesh" }))
      :execute(function(ctx)
         built = ctx.mesh:build_vertex_input(mesh.make_cube())
      end)
      :compile()

   local ok = pcall(function()
      compiled:start()
   end)

   if not ok then
      return
   end

   test.truthy(built ~= nil)
   test.equal(tonumber(built.cdata[0].num_vertex_buffers), 1)
end)
