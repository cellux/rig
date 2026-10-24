local M = ... or {}
local profiler = require("profiler")
local runtime = require("runtime")

--[ graphics contract ]

-- Generic graphics-context and frame/presentation orchestration. Backends (for
-- example `sdl3x`) provide the actual `graphics.context` implementations; this
-- module owns only the backend-neutral contract and the per-frame loop that
-- drives any implementation.

function M.plugin(spec)
   spec = spec or {}
   return runtime.plugin {
      id = spec.id or "graphics",
      capabilities = {
         ["graphics.context"] = {},
      },
   }
end

-- Builds a component that provides `config.capability` from a provider service.
-- The provider is created through `config.make(context)` (or `config.provider`)
-- and bound through `config.bind(provider)`. The component requires a
-- `graphics.context` with `config.backend`.
function M.provider_component(plugin, options, config)
   local bind = config.bind or function(provider)
      return provider
   end
   local make = config.make or function()
      return config.provider
   end

   local descriptor = {
      name = options.name,
      provides = {
         { capability = config.capability },
      },
      requires = {
         {
            capability = "graphics.context",
            properties = { backend = config.backend },
         },
      },
      create = function(context)
         return bind(make(context))
      end,
   }

   if config.release ~= nil then
      descriptor.release = function()
         config.release()
      end
   end

   return runtime.descriptor(plugin, descriptor)
end

-- Provides the backend-neutral per-frame loop. It requires `graphics.context`
-- and contributes a `frame` progress operation that:
--   1. emits `core.before_frame`;
--   2. calls the render callback, defaulting to `instance:render(...)` or the
--      `render.scene` provider;
--   3. presents through the graphics context (`graphics:render_frame(render)`);
--   4. emits `core.after_frame`.
-- `options.frame_profiler` may be `true` or a `profiler.FrameProfiler` options
-- table and wraps the whole frame and the render call.
function M.frame_component(plugin, options)
   options = options or {}

   local frame_profiler = nil
   if options.frame_profiler == true then
      frame_profiler = profiler.FrameProfiler()
   elseif type(options.frame_profiler) == "table" then
      frame_profiler = profiler.FrameProfiler(options.frame_profiler)
   end

   return runtime.descriptor(plugin, {
      name = options.name,
      requires = {
         { capability = "graphics.context" },
         { capability = "render.scene", optional = true },
      },
      create = function()
         return {
            profiler = frame_profiler,
         }
      end,
      progress = {
         frame = function(context)
            local rt = context.runtime
            local graphics = rt.capability_values["graphics.context"]
            if graphics == nil then
               return
            end

            if frame_profiler ~= nil then
               frame_profiler:begin_frame()
            end

            local payload = {
               runtime = rt,
               ctx = rt.ctx,
               graphics = graphics,
               step = context.step,
            }
            rt:emit("core.before_frame", payload)

            local render = options.render
            if render == nil
               and rt.instance ~= nil
               and type(rt.instance.render) == "function" then
               render = function(...)
                  return rt.instance:render(...)
               end
            end
            if render == nil then
               local scene = rt.capability_values["render.scene"]
               if scene ~= nil then
                  render = function(...)
                     return scene:render(...)
                  end
               end
            end

            if frame_profiler ~= nil then
               frame_profiler:begin_cpu()
            end
            graphics:render_frame(render)
            if frame_profiler ~= nil then
               frame_profiler:end_cpu()
            end

            rt:emit("core.after_frame", payload)

            if frame_profiler ~= nil then
               frame_profiler:end_frame()
            end
         end,
      },
   })
end

return M
