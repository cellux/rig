-- Córdoba Phase 1 technical spike.
--
-- This is deliberately throwaway code (D24). It proves the OpenGL path can:
--   * load a pre-existing texture,
--   * generate a parameterized architectural mesh,
--   * drive a first-person camera from focused-window mouse movement,
--   * render a reflective-floor experiment.
--
-- It is not the Córdoba shell and is not a compatibility surface. The mesh
-- builder and floor shader are expected to be replaced by the Phase 2–6 modules.

local asset = require("asset")
local color = require("color")
local ffi = require("ffi")
local mesh = require("mesh")
local render = require("render")
local rig = require("rig")
local sdl3x = require("sdl3x")

local floor_mesh
local arcade_mesh
local frame_count = 0
local floor_material
local lit_material

local eye_height = 1.65
local camera = {
   position = { 0.0, eye_height, -18.0 },
   yaw = 0.0,
   pitch = -0.02,
   speed = 5.0,
}

local function pack_vertices(vertices)
   local values = {}
   for i = 1, #vertices do
      local vertex = vertices[i]
      for j = 1, 8 do
         values[#values + 1] = vertex[j]
      end
   end

   local data = ffi.new("float[?]", #values)
   for i = 1, #values do
      data[i - 1] = values[i]
   end

   return {
      layout = "position_color_uv_f32",
      topology = "triangles",
      vertex_stride = 32,
      vertex_count = #vertices,
      attribute_offsets = {
         position = 0,
         color = 12,
         uv = 24,
      },
      vertex_blob = ffi.string(ffi.cast("const char *", data), ffi.sizeof(data)),
   }
end

local function builder()
   local vertices = {}

   local function push(x, y, z, r, g, b, u, v)
      vertices[#vertices + 1] = { x, y, z, r, g, b, u or 0.0, v or 0.0 }
   end

   local function quad(a, b, c, d, tint)
      local r, g, bl = tint:to_rgbf()
      push(a[1], a[2], a[3], r, g, bl, 0.0, 0.0)
      push(b[1], b[2], b[3], r, g, bl, 1.0, 0.0)
      push(c[1], c[2], c[3], r, g, bl, 1.0, 1.0)
      push(a[1], a[2], a[3], r, g, bl, 0.0, 0.0)
      push(c[1], c[2], c[3], r, g, bl, 1.0, 1.0)
      push(d[1], d[2], d[3], r, g, bl, 0.0, 1.0)
   end

   local function box(cx, cy, cz, sx, sy, sz, tint)
      local x0, x1 = cx - sx * 0.5, cx + sx * 0.5
      local y0, y1 = cy - sy * 0.5, cy + sy * 0.5
      local z0, z1 = cz - sz * 0.5, cz + sz * 0.5
      quad({ x0, y1, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, { x0, y1, z1 }, tint)
      quad({ x0, y0, z1 }, { x1, y0, z1 }, { x1, y0, z0 }, { x0, y0, z0 }, tint)
      quad({ x0, y0, z0 }, { x1, y0, z0 }, { x1, y1, z0 }, { x0, y1, z0 }, tint)
      quad({ x1, y0, z1 }, { x0, y0, z1 }, { x0, y1, z1 }, { x1, y1, z1 }, tint)
      quad({ x0, y0, z1 }, { x0, y0, z0 }, { x0, y1, z0 }, { x0, y1, z1 }, tint)
      quad({ x1, y0, z0 }, { x1, y0, z1 }, { x1, y1, z1 }, { x1, y1, z0 }, tint)
   end

   local function column(x, z)
      local stone = color.rgb(188, 178, 158)
      local shadow = color.rgb(150, 138, 120)
      local sides = 8
      local radius = 0.28
      local bottom, top = 0.0, 4.55
      for i = 0, sides - 1 do
         local a0 = (i / sides) * math.pi * 2.0
         local a1 = ((i + 1) / sides) * math.pi * 2.0
         local p0 = { x + math.cos(a0) * radius, bottom, z + math.sin(a0) * radius }
         local p1 = { x + math.cos(a0) * radius, top, z + math.sin(a0) * radius }
         local p2 = { x + math.cos(a1) * radius, top, z + math.sin(a1) * radius }
         local p3 = { x + math.cos(a1) * radius, bottom, z + math.sin(a1) * radius }
         local tint = (i % 2 == 0) and stone or shadow
         quad(p0, p1, p2, p3, tint)
      end
      box(x, 0.18, z, 0.72, 0.36, 0.72, shadow)
      box(x, top + 0.22, z, 0.78, 0.44, 0.78, stone)
   end

   -- Extruded arc band. `ux`,`uz` is the horizontal direction between supports.
   local function arch(cx, cz, ux, uz, span, spring, radius, thickness, depth,
                        a0, a1, tint_a, tint_b)
      local nx, nz = -uz, ux
      local half_depth = depth * 0.5
      local inner = radius - thickness * 0.5
      local outer = radius + thickness * 0.5
      local segments = 22

      local function point(theta, r, side)
         local c, s = math.cos(theta), math.sin(theta)
         return {
            cx + ux * r * c + nx * side * half_depth,
            spring + r * s,
            cz + uz * r * c + nz * side * half_depth,
         }
      end

      for i = 0, segments - 1 do
         local t0 = a0 + (a1 - a0) * (i / segments)
         local t1 = a0 + (a1 - a0) * ((i + 1) / segments)
         local tint = (i % 2 == 0) and tint_a or tint_b

         local i0f, i1f = point(t0, inner, 1.0), point(t1, inner, 1.0)
         local o0f, o1f = point(t0, outer, 1.0), point(t1, outer, 1.0)
         local i0b, i1b = point(t0, inner, -1.0), point(t1, inner, -1.0)
         local o0b, o1b = point(t0, outer, -1.0), point(t1, outer, -1.0)

         quad(i0f, o0f, o1f, i1f, tint)
         quad(i1b, o1b, o0b, i0b, tint)
         quad(o0f, o0b, o1b, o1f, tint)
         quad(i1f, i1b, i0b, i0f, tint)
      end

      local tint = tint_a
      for _, t in ipairs({ a0, a1 }) do
         local i, o = point(t, inner, 1.0), point(t, outer, 1.0)
         local ib, ob = point(t, inner, -1.0), point(t, outer, -1.0)
         quad(i, o, ob, ib, tint)
      end
   end

   return {
      push = push,
      quad = quad,
      box = box,
      column = column,
      arch = arch,
      finish = function()
         return pack_vertices(vertices)
      end,
   }
end

local brick = color.rgb(166, 63, 48)
local cream = color.rgb(216, 201, 170)
local plaster = color.rgb(222, 212, 188)
local wood = color.rgb(73, 51, 34)

local function build_floor()
   local b = builder()
   local west, east = -30.0, 30.0
   local north, south = -26.0, 56.0
   b.quad(
      { west, 0.0, north },
      { east, 0.0, north },
      { east, 0.0, south },
      { west, 0.0, south },
      color.rgb(255, 255, 255)
   )
   return b.finish()
end

local function build_arcade()
   local b = builder()
   local xs = { -24, -18, -12, -6, 0, 6, 12, 18, 24 }
   local zs = { -12, -6, 0, 6, 12, 18, 24, 30, 36 }

   for _, x in ipairs(xs) do
      for _, z in ipairs(zs) do
         b.column(x, z)
      end
   end

   for _, z in ipairs(zs) do
      for i = 1, #xs - 1 do
         local x0, x1 = xs[i], xs[i + 1]
         local span = x1 - x0
         local cx, cz = (x0 + x1) * 0.5, z
         b.arch(cx, cz, 1.0, 0.0, span, 4.25, span * 0.5, 0.38, 0.58,
            -0.36, math.pi + 0.36, cream, brick)
         b.arch(cx, cz, 1.0, 0.0, span, 7.15, span * 0.5, 0.32, 0.48,
            0.0, math.pi, cream, brick)
      end
   end

   for _, x in ipairs(xs) do
      for i = 1, #zs - 1 do
         local z0, z1 = zs[i], zs[i + 1]
         local span = z1 - z0
         local cx, cz = x, (z0 + z1) * 0.5
         b.arch(cx, cz, 0.0, 1.0, span, 4.25, span * 0.5, 0.38, 0.58,
            -0.36, math.pi + 0.36, cream, brick)
         b.arch(cx, cz, 0.0, 1.0, span, 7.15, span * 0.5, 0.32, 0.48,
            0.0, math.pi, cream, brick)
      end
   end

   -- A dark timber ceiling and a pale terminal wall suggest the transition
   -- towards the cathedral without pretending to model it yet.
   b.quad(
      { -30.0, 11.2, -26.0 },
      { 30.0, 11.2, -26.0 },
      { 30.0, 11.2, 56.0 },
      { -30.0, 11.2, 56.0 },
      wood
   )
   b.box(0.0, 5.5, 47.0, 60.0, 11.0, 1.0, plaster)
   b.box(-29.5, 5.5, 15.0, 1.0, 11.0, 82.0, plaster)
   b.box(29.5, 5.5, 15.0, 1.0, 11.0, 82.0, plaster)

   return b.finish()
end

local function update_camera(frame)
   local input = frame.input
   local dx, dy = input:mouse_delta()
   local sensitivity = 0.0026
   camera.yaw = camera.yaw - dx * sensitivity
   camera.pitch = camera.pitch - dy * sensitivity
   local limit = math.pi * 0.5 - 0.02
   camera.pitch = math.max(-limit, math.min(limit, camera.pitch))

   local forward = input:axis("S", "W")
   local strafe = input:axis("A", "D")
   if input.shift then
      camera.speed = 9.0
   else
      camera.speed = 5.0
   end

   local sin_yaw, cos_yaw = math.sin(camera.yaw), math.cos(camera.yaw)
   local px, pz = camera.position[1], camera.position[3]
   local distance = camera.speed * frame.dt
   px = px + (sin_yaw * forward - cos_yaw * strafe) * distance
   pz = pz + (cos_yaw * forward + sin_yaw * strafe) * distance
   camera.position[1] = math.max(-28.5, math.min(28.5, px))
   camera.position[3] = math.max(-24.5, math.min(54.5, pz))

   local cos_pitch = math.cos(camera.pitch)
   local target = {
      camera.position[1] + sin_yaw * cos_pitch,
      camera.position[2] + math.sin(camera.pitch),
      camera.position[3] + cos_yaw * cos_pitch,
   }
   frame.surface:set_camera {
      eye = camera.position,
      target = target,
      up = { 0.0, 1.0, 0.0 },
      fov_degrees = 66.0,
      near = 0.08,
      far = 120.0,
   }
end

floor_mesh = build_floor()
arcade_mesh = build_arcade()

rig.run {
   title = "Córdoba Phase 1 Spike",
   bundle = sdl3x.bundle_sdl3_gl,
   bundle_options = {
      gl_attributes = {
         context_major_version = 4,
         context_minor_version = 5,
         context_profile = "core",
         doublebuffer = true,
         depth_size = 24,
      },
      swap_interval = 1,
   },
   camera = {
      eye = camera.position,
      target = { 0.0, 1.3, 0.0 },
      fov_degrees = 66.0,
      near = 0.08,
      far = 120.0,
   },
   build = function(app)
      app:on_update(function(_, frame)
         update_camera(frame)
         frame_count = frame_count + 1
         local screenshot_path = os.getenv("CORDOBA_SPIKE_SCREENSHOT")
         if screenshot_path ~= nil and frame_count == 30 then
            app:screenshot(screenshot_path)
         end
         if os.getenv("CORDOBA_SPIKE_EXIT") == "1" and frame_count == 36 then
            app.runtime:stop()
         end
      end)
      app:on_draw(function(_, frame)
         frame.surface:draw_mesh(floor_mesh, nil, floor_material)
         frame.surface:draw_mesh(arcade_mesh, nil, lit_material)
      end)
   end,
   start = function()
      local checker = render.texture {
         image = asset.image("../assets/checker.png"),
         name = "spike-checker",
         filter = "linear",
         wrap = "repeat",
      }
      floor_material = asset.material {
         name = "spike-floor",
         vertex = "assets/spike_floor.vert",
         fragment = "assets/spike_floor.frag",
         texture = checker,
      }
      lit_material = asset.material {
         name = "spike-lit",
         vertex = "assets/spike_lit.vert",
         fragment = "assets/spike_lit.frag",
      }
   end,
}
