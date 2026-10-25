local color = require("color")
local mathx = require("mathx")
local mesh = require("mesh")
local rig = require("rig")

-- Procedural mesh gallery for the Phase 2 mesh contract: indexed geometry,
-- normals/UVs, architectural generators, and builder composition. The built-in
-- material is unlit, so this example verifies geometry, winding, and index ranges
-- rather than lighting.
--
-- Controls: drag to orbit, Q/E to dolly.
--
--    RIG_BACKEND=gl  ./build/rig examples/procedural_mesh.lua
--    RIG_BACKEND=gpu ./build/rig examples/procedural_mesh.lua

local backend = rig.require("./backend").select {
   backends = { gl = true, gpu = true },
}

local stone = color.rgb(214, 201, 178)
local warm_stone = color.rgb(190, 166, 132)
local brick = color.rgb(156, 62, 48)
local cream = color.rgb(231, 216, 184)
local wood = color.rgb(96, 70, 48)

local function translation(x, y, z)
   return mathx.mat4_translation(mathx.mat4(), x, y, z)
end

local display = {}

local function add(geometry, x, y, z)
   display[#display + 1] = {
      mesh = geometry,
      transform = translation(x, y, z),
   }
end

add(
   mesh.make_floor_bay {
      width = 18.0,
      depth = 14.0,
      segments = 9,
      color = warm_stone,
      uv_scale = 0.5,
   },
   0.0,
   0.0,
   0.0
)

-- Box
add(
   mesh.make_box {
      width = 1.4,
      height = 1.4,
      depth = 1.4,
      color = stone,
   },
   -6.5,
   0.7,
   -3.0
)

-- Truncated cylinder
add(
   mesh.make_cylinder {
      radius = 0.8,
      top_radius = 0.45,
      height = 2.2,
      segments = 20,
      color = brick,
   },
   -4.0,
   1.1,
   -3.0
)

-- Column with base and capital
add(
   mesh.make_column {
      radius = 0.32,
      height = 3.6,
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
   },
   -1.4,
   0.0,
   -3.0
)

-- Flared capital alone
add(
   mesh.make_capital {
      radius = 0.4,
      top_radius = 0.65,
      height = 0.55,
      abacus_height = 0.18,
      abacus_width = 1.5,
      color = stone,
      abacus_color = cream,
   },
   1.2,
   1.1,
   -3.0
)

-- Horseshoe arch with alternating voussoirs
add(
   mesh.make_horseshoe_arch {
      radius = 1.45,
      thickness = 0.28,
      depth = 0.42,
      segments = 22,
      stripe_colors = { brick, cream },
   },
   3.9,
   1.65,
   -3.0
)

-- Round arch
add(
   mesh.make_round_arch {
      radius = 1.2,
      thickness = 0.24,
      depth = 0.38,
      segments = 18,
      color = stone,
   },
   6.8,
   1.5,
   -3.0
)

-- Wall with a window opening
add(
   mesh.make_wall {
      width = 4.6,
      height = 3.2,
      thickness = 0.3,
      color = cream,
      reveal_color = warm_stone,
      openings = {
         { x = 1.45, y = 1.0, width = 1.7, height = 1.5 },
      },
   },
   -4.0,
   0.0,
   3.0
)

-- Hollow barrel vault
add(
   mesh.make_barrel_vault {
      radius = 2.0,
      thickness = 0.24,
      length = 3.4,
      segments = 20,
      start_angle = 0.0,
      end_angle = math.pi,
      color = wood,
   },
   -0.2,
   2.1,
   2.8
)

-- Builder-composed plinth with two material sections. The unlit material ignores
-- the section materials, but the merged mesh exercises the indexed merge path.
local plinth = mesh.builder()
plinth:add(
   mesh.make_box {
      width = 2.2,
      height = 0.3,
      depth = 1.6,
      color = warm_stone,
   },
   {
      name = "plinth_base",
      material = "stone",
      transform = translation(0.0, 0.15, 0.0),
   }
)
plinth:add(
   mesh.make_box {
      width = 1.8,
      height = 0.25,
      depth = 1.3,
      color = cream,
   },
   {
      name = "plinth_top",
      material = "cream",
      transform = translation(0.0, 0.425, 0.0),
   }
)
add(plinth:build(), 4.2, 0.0, 2.4)

rig.run {
   title = "Rig " .. backend.label .. " Procedural Mesh Gallery",
   bundle = backend.bundle,
   bundle_options = backend.bundle_options,
   background = color.rgb(34, 38, 46),
   camera_controls = {
      kind = "orbit",
      target = { 0.0, 1.6, 0.0 },
      distance = 16.0,
      pitch = 0.32,
      yaw = math.pi,
   },
   build = function(app)
      app:on_draw(function(_, frame)
         for i = 1, #display do
            local entry = display[i]
            frame.surface:draw_mesh(entry.mesh, entry.transform)
         end
      end)
   end,
}
