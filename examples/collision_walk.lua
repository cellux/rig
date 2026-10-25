local collision = require("collision")
local color = require("color")
local mathx = require("mathx")
local mesh = require("mesh")
local rig = require("rig")

-- Phase 4 collision walk demo. Static collision lives independently from the
-- render meshes; the debug line mesh shows the actual proxies.
--
-- Controls:
--   W/A/S/D  walk
--   mouse    look while the window is focused
--   R        reset to the spawn pose
--   C        toggle collision debug lines
--
--    ./build/rig examples/collision_walk.lua

local backend = rig.require("./backend").select {
   backends = { gl = true, gpu = true },
}

local function translation(x, y, z)
   return mathx.mat4_translation(mathx.mat4(), x, y, z)
end

local function rotation_y(angle)
   return mathx.mat4_rotation_y(mathx.mat4(), angle)
end

local function transform(x, y, z, angle)
   return mathx.mat4_multiply(
      mathx.mat4(),
      translation(x, y, z),
      rotation_y(angle or 0.0)
   )
end

local stone = color.rgb(206, 196, 176)
local warm_stone = color.rgb(184, 164, 134)
local brick = color.rgb(158, 72, 54)
local dark_wood = color.rgb(92, 68, 48)

local world = collision.world()
local display = {}

local function add_display(geometry, x, y, z, angle)
   display[#display + 1] = {
      mesh = geometry,
      transform = transform(x, y, z, angle),
   }
end

add_display(
   mesh.make_floor_bay {
      width = 24.0,
      depth = 24.0,
      segments = 12,
      color = warm_stone,
      uv_scale = 0.5,
   },
   0.0,
   0.0,
   0.0
)

-- Outer walls.
local wall_height = 3.2
local wall_thickness = 0.4
local wall_mesh_x = mesh.make_box {
   width = wall_thickness,
   height = wall_height,
   depth = 22.0,
   color = stone,
}
local wall_mesh_z = mesh.make_box {
   width = 22.0,
   height = wall_height,
   depth = wall_thickness,
   color = stone,
}
for _, spec in ipairs {
   { x = -11.0, z = 0.0, mesh = wall_mesh_x },
   { x = 11.0, z = 0.0, mesh = wall_mesh_x },
   { x = 0.0, z = -11.0, mesh = wall_mesh_z },
   { x = 0.0, z = 11.0, mesh = wall_mesh_z },
} do
   add_display(spec.mesh, spec.x, wall_height * 0.5, spec.z)
   world:add_box {
      x = spec.x,
      z = spec.z,
      width = spec.mesh == wall_mesh_x and wall_thickness or 22.0,
      depth = spec.mesh == wall_mesh_x and 22.0 or wall_thickness,
   }
end

-- A grid of columns with circular collision proxies.
local column_mesh = mesh.make_column {
   radius = 0.32,
   height = 3.8,
   base_height = 0.35,
   base_radius = 0.48,
   capital_height = 0.45,
   capital_radius = 0.48,
   abacus_height = 0.16,
   abacus_width = 1.15,
   segments = 20,
   color = stone,
   base_color = warm_stone,
   capital_color = warm_stone,
   abacus_color = stone,
}
for x = -6.0, 6.0, 6.0 do
   for z = -4.0, 4.0, 4.0 do
      if not (x == 0.0 and z == 0.0) then
         add_display(column_mesh, x, 0.0, z)
         world:add_circle { x = x, z = z, radius = 0.5 }
      end
   end
end

-- Rotated wall: an oriented-box proxy matches the rendered box.
local angled_angle = math.rad(35.0)
local angled_mesh = mesh.make_box {
   width = 5.0,
   height = 2.6,
   depth = 0.35,
   color = brick,
}
add_display(angled_mesh, 4.2, 1.3, 1.2, angled_angle)
world:add_box {
   x = 4.2,
   z = 1.2,
   width = 5.0,
   depth = 0.35,
   angle = angled_angle,
}

-- Low fence: a thin segment proxy matches the rendered rail.
local fence_mesh = mesh.make_box {
   width = 4.0,
   height = 0.9,
   depth = 0.08,
   color = dark_wood,
}
add_display(fence_mesh, -4.0, 0.45, 2.4)
world:add_segment {
   from = { -6.0, 2.4 },
   to = { -2.0, 2.4 },
   thickness = 0.08,
}

-- Octagonal plinth: a polygon proxy demonstrates arbitrary convex footprints.
local plinth_radius = 1.1
local plinth_mesh = mesh.make_cylinder {
   radius = plinth_radius,
   height = 0.9,
   segments = 8,
   color = stone,
}
add_display(plinth_mesh, 0.0, 0.45, 4.2)
local plinth_points = {}
for i = 0, 7 do
   local angle = (i / 8.0) * math.pi * 2.0
   plinth_points[#plinth_points + 1] = {
      math.cos(angle) * plinth_radius,
      4.2 + math.sin(angle) * plinth_radius,
   }
end
world:add_polygon { points = plinth_points }

local debug_mesh = world:debug_mesh { y = 0.025, circle_segments = 24 }
local debug_enabled = true

rig.run {
   title = "Rig " .. backend.label .. " Collision Walk",
   bundle = backend.bundle,
   bundle_options = backend.bundle_options,
   background = color.rgb(34, 38, 44),
   camera_controls = {
      kind = "walk",
      collision = world,
      position = { -8.0, 0.0, -9.0 },
      yaw = 0.72,
      eye_height = 1.65,
      speed = 3.0,
      radius = 0.3,
   },
   build = function(app)
      app:on_key(function(_, info)
         if info.action == "down"
            and not info["repeat"]
            and string.upper(info.key or "") == "C" then
            debug_enabled = not debug_enabled
         end
      end)

      app:on_draw(function(_, frame)
         for i = 1, #display do
            local entry = display[i]
            frame.surface:draw_mesh(entry.mesh, entry.transform)
         end
         if debug_enabled and debug_mesh ~= nil then
            frame.surface:draw_mesh(debug_mesh)
         end
      end)
   end,
}
