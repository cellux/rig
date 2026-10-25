local asset = require("asset")
local color = require("color")
local font = require("font")
local rig = require("rig")

-- Present-day Córdoba Mosque-Cathedral. The walkable interior is the full
-- published 125 m x 118 m prayer hall: the hypostyle field, the Christian
-- cathedral insertion, the Villaviciosa chapel, the maqsura/mihrab, and the
-- perimeter chapels.
--
-- Controls:
--   W/A/S/D   walk
--   mouse     look while the window is focused
--   R         reset to the route start
--   C         toggle collision proxies
--   F         toggle full/simple lighting (overrides the preset)
--   Q         cycle the visual preset (Rich / Balanced / Performance)
--   M         reduce the scene to the detailed MVP route
--   G         toggle mouse grab
--   H         toggle the HUD
--
-- See `examples/Cordoba/README.md` for presets, run commands, and limitations.

local backend = rig.require("../backend").select {
   backends = { gl = true },
}

local config = rig.require("./scene/config")
local materials_module = rig.require("./scene/materials")
local architecture = rig.require("./scene/architecture")

local materials = materials_module.create()
local scene = architecture.build(config, materials)

local hud_style = nil
local hud_enabled = true
local collision_enabled = false
local full_lighting = true
local smooth_dt = nil
local frame_count = 0
local camera_override_applied = false

-- Optional headless verification hooks. They are inert unless the environment
-- sets them, so the interactive example is unchanged.
local function env_number(name, fallback)
   local value = tonumber(os.getenv(name) or "")
   return value or fallback
end

local function apply_camera_override(app)
   if camera_override_applied then
      return
   end
   camera_override_applied = true
   local spec = os.getenv("CORDOBA_CAMERA")
   if spec == nil or spec == "" then
      return
   end
   local x, y, z, yaw, pitch = spec:match("([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
   local walk = app.camera_controllers[1]
   if walk == nil or x == nil then
      return
   end
   walk.position = { tonumber(x), tonumber(y), tonumber(z) }
   walk.yaw = tonumber(yaw)
   walk.pitch = tonumber(pitch)
   if walk.collision ~= nil then
      walk.position[1], walk.position[3] = walk.collision:resolve_circle(
         walk.position[1],
         walk.position[3],
         walk.radius
      )
   end
end

-- Progressive visual configurations selectable with `Q`. Each bundles the
-- floor reflection target, lighting model, content visibility, and cull range so
-- the trade-offs are explicit and documented in `examples/Cordoba/README.md`.
local presets = {
   {
      name = "Rich",
      floor = materials.floor,
      reflection = materials.reflection_targets.high,
      reflection_distance = 95.0,
      lighting = true,
      contents = true,
      summary = "640x360 planar reflections, full lighting, all contents",
   },
   {
      name = "Balanced",
      floor = materials.floor_balanced,
      reflection = materials.reflection_targets.balanced,
      reflection_distance = 65.0,
      lighting = true,
      contents = true,
      summary = "384x216 reflections (shorter range), full lighting, all contents",
   },
   {
      name = "Performance",
      floor = materials.floor_fallback,
      reflection = nil,
      reflection_distance = 0.0,
      lighting = false,
      contents = false,
      summary = "no reflection pass, simple lighting, no contents",
   },
}
local preset_index = 1
local mvp_only = os.getenv("CORDOBA_MVP") == "1"
local last_draw_count = 0

local function current_preset()
   return presets[preset_index]
end

local function initial_preset_index()
   local requested = os.getenv("CORDOBA_PRESET")
   if requested == nil or requested == "" then
      return 1
   end
   for i, preset in ipairs(presets) do
      if string.lower(preset.name) == string.lower(requested) then
         return i
      end
   end
   local numeric = tonumber(requested)
   if numeric ~= nil and presets[numeric] ~= nil then
      return numeric
   end
   return 1
end

local function current_zone(app)
   local walk = app.camera_controllers[1]
   local position = walk and walk.position or config.start.position
   return config.zone_at(position[1], position[3])
end

local function set_lighting(app, full)
   full_lighting = full
   if app.scene ~= nil then
      app.scene:set_lighting(
         full and materials.lighting_full or materials.lighting_simple
      )
   end
end

local function set_preset(app, index)
   preset_index = index
   set_lighting(app, current_preset().lighting)
end

-- Mirrors a camera across the horizontal plane Y = plane_y. With the reflected
-- up vector this is a true mirror transform; the floor material then samples the
-- pass with screen-space coordinates.
local function mirror_camera(camera, plane_y)
   local offset = plane_y * 2.0
   local eye = camera.eye
   local target = camera.target
   local up = camera.up or { 0.0, 1.0, 0.0 }
   return {
      eye = { eye[1], offset - eye[2], eye[3] },
      target = { target[1], offset - target[2], target[3] },
      up = { up[1], -up[2], up[3] },
      fov_degrees = camera.fov_degrees,
      near = camera.near,
      far = camera.far,
   }
end

local function camera_heading(camera)
   local eye = camera.eye
   local target = camera.target
   local dx, dz = target[1] - eye[1], target[3] - eye[3]
   local length = math.sqrt(dx * dx + dz * dz)
   if length < 1e-6 then
      return { 0.0, 0.0, 1.0 }
   end
   return { dx / length, 0.0, dz / length }
end

-- Region ids visible from the current camera. In MVP mode the result is
-- intersected with the central route regions only.
local function view_half_angle(surface)
   local camera = surface.camera
   local vertical = math.rad(camera.fov_degrees or 60.0)
   local aspect = (surface.width or 1) / math.max(surface.height or 1, 1)
   return math.atan(math.tan(vertical * 0.5) * aspect) + math.rad(6.0)
end

local function collect_visible(camera, half_angle, max_distance)
   local visible = config.visible_regions(camera.eye, camera_heading(camera), {
      half_angle = half_angle,
      max_distance = max_distance,
   })
   if mvp_only then
      local filtered = {}
      for id in pairs(visible) do
         if config.mvp_region_ids[id] then
            filtered[id] = true
         end
      end
      return filtered
   end
   return visible
end

local function draw_drawables(surface, floor_material, visible, draw_contents)
   local count = 0
   for i = 1, #scene.drawables do
      local drawable = scene.drawables[i]
      if (drawable.region == "global" or visible[drawable.region])
         and (draw_contents or drawable.kind ~= "contents") then
         local material = drawable.material
         if drawable.name == "floor" then
            material = floor_material
         end
         surface:draw_mesh(drawable.mesh, nil, material)
         count = count + 1
      end
   end
   return count
end

local function draw_reflection(frame, target, half_angle, max_distance, draw_contents)
   local camera = mirror_camera(frame.surface.camera, 0.0)
   local visible = collect_visible(camera, half_angle, max_distance)
   frame.surface:render_to(target, function(pass_frame)
      for i = 1, #scene.drawables do
         local drawable = scene.drawables[i]
         if drawable.name ~= "floor"
            and (drawable.region == "global" or visible[drawable.region])
            and (draw_contents or drawable.kind ~= "contents") then
            pass_frame.surface:draw_mesh(drawable.mesh, nil, drawable.material)
         end
      end
   end, { camera = camera })
end

local function draw_hud(app, frame)
   if not hud_enabled or hud_style == nil then
      return
   end

   local draw = app.ctx.draw
   draw:rect(16, 16, 880, 108, color.rgba(8, 10, 14, 180))

   local header = "CORDOBA  ·  Phase 10 quality configurations and packaging"
   local controls =
      "WASD walk  ·  R reset  ·  C collision  ·  F lighting  ·  Q preset  ·  M MVP  ·  G grab  ·  H HUD"
   local dt = smooth_dt or (1.0 / 60.0)
   local preset = current_preset()
   local stats = scene.stats or {}
   local state = ("%s  ·  %s  ·  %s  ·  grab %s  ·  draw %d/%d  ·  %d props  ·  %dx%d  ·  %.0f fps"):format(
      current_zone(app),
      preset.name .. (mvp_only and " + MVP" or ""),
      full_lighting and "full lighting" or "simple lighting",
      app:mouse_grab_enabled() and "on" or "off",
      last_draw_count,
      stats.drawables or 0,
      stats.contents_instances or 0,
      frame.surface.width,
      frame.surface.height,
      1.0 / math.max(dt, 0.000001)
   )
   local summary = "Q preset: " .. preset.summary

   hud_style:draw_text(header, 30, 40, function()
      return color.rgb(255, 214, 148)
   end)
   hud_style:draw_text(controls, 30, 60, function()
      return color.rgb(232, 225, 210)
   end)
   hud_style:draw_text(state, 30, 80, function()
      return color.rgb(174, 202, 232)
   end)
   hud_style:draw_text(summary, 30, 100, function()
      return color.rgb(150, 176, 152)
   end)
end

rig.run {
   title = "Córdoba Mosque-Cathedral — " .. backend.label,
   bundle = backend.bundle,
   bundle_options = backend.bundle_options,
   background = color.rgb(17, 19, 24),
   lighting = materials.lighting_full,
   mouse_grab = true,
   camera_controls = {
      kind = "walk",
      collision = scene.collision,
      position = config.start.position,
      yaw = config.start.yaw,
      pitch = config.start.pitch,
      eye_height = config.start.eye_height,
      radius = config.start.radius,
      speed = config.start.speed,
      sensitivity = 0.0022,
      smoothing = 0.055,
   },
   start = function(app)
      local face = font.load_face(asset.path("../../assets/DejaVuSans.ttf"))
      hud_style = app.ctx.font:create_style(face, {
         pixel_size = 14,
         page_width = 256,
         page_height = 128,
         padding = 1,
      })
      hud_style:warm_text(
         "CORDOBA Phase 10 quality configurations packaging Rich Balanced Performance MVP preset lighting contents WASD mouse look R reset C collision F Q M G grab H HUD full simple on off North threshold hypostyle Cathedral south West East Maqsura Villaviciosa Capilla Mayor Crossing transept aisles nave route reflections draw props fps 0123456789x/"
      )
      set_preset(app, initial_preset_index())
   end,
   build = function(app)
      app:on_update(function(_, frame)
         apply_camera_override(app)
         frame_count = frame_count + 1
         if os.getenv("CORDOBA_SWEEP") == "1" and frame_count == 1 then
            local radius = config.start.radius
            local function sweep(name, x, z, dx, dz, steps)
               local px, pz = x, z
               for _ = 1, steps do
                  px, pz = scene.collision:sweep_circle(px, pz, dx, dz, radius)
               end
               print(("SWEEP %-16s start=(%.2f,%.2f) end=(%.2f,%.2f)"):format(
                  name, x, z, px, pz
               ))
            end
            sweep("central-south", 0.0, -51.0, 0.0, 1.0, 130)
            sweep("south-side-exit", 18.0, -30.0, 0.0, 1.0, 70)
            sweep("chapel", -5.0, -18.0, -1.0, 0.0, 30)
            sweep("maqsura", 0.0, 20.0, 0.0, 1.0, 45)
            sweep("west-chapel-bay", -60.0, 0.0, 0.0, 1.0, 10)
            local stats = scene.stats or {}
            print(("STATS drawables=%d regions=%d vertices=%d triangles=%d contents=%d"):format(
               stats.drawables or 0,
               stats.regions or 0,
               stats.vertices or 0,
               stats.triangles or 0,
               stats.contents_instances or 0
            ))
            app.runtime:stop()
         end
         local dt = frame.dt or 0.0
         if dt > 0.0 then
            if smooth_dt == nil then
               smooth_dt = dt
            else
               smooth_dt = smooth_dt * 0.90 + dt * 0.10
            end
         end
         local screenshot = os.getenv("CORDOBA_SCREENSHOT")
         local capture_frame = math.floor(env_number("CORDOBA_CAPTURE_FRAME", 45))
         if screenshot ~= nil and screenshot ~= "" and frame_count == capture_frame then
            app:screenshot(screenshot)
         end
         if os.getenv("CORDOBA_EXIT") == "1" and frame_count == capture_frame + 4 then
            app.runtime:stop()
         end
      end)

      app:on_key(function(_, info)
         if info.action ~= "down" or info["repeat"] then
            return
         end
         local key = string.upper(info.key or "")
         if key == "C" then
            collision_enabled = not collision_enabled
         elseif key == "F" then
            set_lighting(app, not full_lighting)
         elseif key == "Q" then
            local next_index = preset_index % #presets + 1
            set_preset(app, next_index)
         elseif key == "M" then
            mvp_only = not mvp_only
         elseif key == "H" then
            hud_enabled = not hud_enabled
         end
      end)

      app:on_draw(function(_, frame)
         local preset = current_preset()
         local floor_material = preset.floor
         local half_angle = view_half_angle(frame.surface)
         local visible = collect_visible(frame.surface.camera, half_angle, nil)
         if preset.reflection ~= nil and frame.surface.target_factory ~= nil then
            draw_reflection(
               frame,
               preset.reflection,
               half_angle,
               preset.reflection_distance,
               preset.contents
            )
         elseif preset.reflection ~= nil then
            -- The scene has no render-target capability; keep the authored
            -- fallback material rather than failing the draw.
            floor_material = materials.floor_fallback
         end
         last_draw_count = draw_drawables(
            frame.surface,
            floor_material,
            visible,
            preset.contents
         )
         if collision_enabled and scene.debug_mesh ~= nil then
            frame.surface:draw_mesh(scene.debug_mesh)
         end
      end)

      app:on_overlay(function(_, frame)
         draw_hud(app, frame)
      end)
   end,
}
