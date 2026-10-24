local color = require("color")
local clamp = require("mathx").clamp
local clamp01 = require("mathx").clamp01
local profiler = require("profiler")
local rig = require("rig")
local time = require("time")

-- An ant colony built on the backend-neutral 2D stack: `draw` supplies the
-- rectangles and lines, and everything else is plain Lua. The same script runs
-- on SDL_Renderer, OpenGL, and SDL_GPU. Pick one with RIG_BACKEND (see
-- examples/backend.lua); the default is `gl`.

local backend = rig.require("./backend").select {
   backends = { renderer = true, gl = true, gpu = true },
}

local ant_count = 96
local ant_speed = 52.0
local ant_margin = 8
local font_scale = 4
local base_sensor_distance = 16.0
local base_sensor_half_width = 6.0
local base_body_radius = 6.0
local max_turn_step = 0.12

local surface_width = 1
local surface_height = 1
local ant_scale = 1.0

local background_color = color.rgbaf(0.06, 0.08, 0.05, 1.0)
local fps_panel_color = color.rgbaf(0.08, 0.09, 0.07, 1.0)
local fps_text_color = color.rgbaf(0.96, 0.96, 0.88, 1.0)
local slider_panel_dim_color = color.rgbaf(0.05, 0.06, 0.05, 0.35)
local slider_panel_bright_color = color.rgbaf(0.22, 0.24, 0.22, 0.92)
local slider_track_dim_color = color.rgbaf(0.18, 0.20, 0.18, 0.45)
local slider_track_bright_color = color.rgbaf(0.84, 0.86, 0.80, 1.0)
local slider_fill_dim_color = color.rgbaf(0.28, 0.20, 0.10, 0.45)
local slider_fill_bright_color = color.rgbaf(0.98, 0.72, 0.26, 1.0)
local slider_knob_dim_color = color.rgbaf(0.42, 0.42, 0.40, 0.55)
local slider_knob_bright_color = color.rgbaf(1.00, 0.99, 0.92, 1.0)
local slider_outline_dim_color = color.rgbaf(0.18, 0.10, 0.04, 1.0)
local slider_outline_bright_color = color.rgbaf(1.00, 0.74, 0.24, 1.0)
local slider_panel_color = color.WHITE:copy()
local slider_track_color = color.WHITE:copy()
local slider_fill_color = color.WHITE:copy()
local slider_knob_color = color.WHITE:copy()
local slider_outline_color = color.WHITE:copy()

local palette_cycle = {
   color.rgbaf(0.92, 0.72, 0.29, 1.0),
   color.rgbaf(0.93, 0.46, 0.34, 1.0),
   color.rgbaf(0.36, 0.77, 0.55, 1.0),
   color.rgbaf(0.38, 0.66, 0.91, 1.0),
   color.rgbaf(0.84, 0.49, 0.83, 1.0),
}

-- A tiny 3x5 bitmap font for the FPS readout, drawn entirely with `draw.rect`.
local glyphs = {
   ["0"] = { "111", "101", "101", "101", "111" },
   ["1"] = { "010", "110", "010", "010", "111" },
   ["2"] = { "111", "001", "111", "100", "111" },
   ["3"] = { "111", "001", "111", "001", "111" },
   ["4"] = { "101", "101", "111", "001", "001" },
   ["5"] = { "111", "100", "111", "001", "111" },
   ["6"] = { "111", "100", "111", "101", "111" },
   ["7"] = { "111", "001", "001", "001", "001" },
   ["8"] = { "111", "101", "111", "101", "111" },
   ["9"] = { "111", "101", "111", "001", "111" },
   ["F"] = { "111", "100", "110", "100", "100" },
   ["P"] = { "110", "101", "110", "100", "100" },
   ["S"] = { "111", "100", "111", "001", "111" },
   [" "] = { "000", "000", "000", "000", "000" },
}

math.randomseed(math.floor(time.monotonic() * 1000000) % 2147483647)

local ants = {}
local canvas = nil
local frame_profiler = nil

--[ small math helpers ]--

local function choose_turn()
   local roll = math.random()
   if roll < 0.10 then
      return -1
   end
   if roll > 0.90 then
      return 1
   end
   return 0
end

local function normalize_angle(angle)
   return angle % (math.pi * 2.0)
end

local function shortest_angle_delta(from_angle, to_angle)
   local full_turn = math.pi * 2.0
   local delta = (to_angle - from_angle) % full_turn
   if delta > math.pi then
      delta = delta - full_turn
   end
   return delta
end

local function turn_toward(from_angle, to_angle, max_step)
   local delta = shortest_angle_delta(from_angle, to_angle)
   if delta > max_step then
      delta = max_step
   elseif delta < -max_step then
      delta = -max_step
   end
   return normalize_angle(from_angle + delta)
end

local function steer_angle(angle, delta)
   return normalize_angle(angle + delta)
end

local function rotate_local(cos_angle, sin_angle, x, y)
   return x * cos_angle - y * sin_angle, x * sin_angle + y * cos_angle
end

local function to_world(ant, cos_angle, sin_angle, x, y)
   local rx, ry = rotate_local(cos_angle, sin_angle, x, y)
   return ant.x + rx, ant.y + ry
end

local function point_in_rect(x, y, rx, ry, rw, rh)
   return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function body_radius()
   return base_body_radius * ant_scale
end

local function sensor_distance()
   return base_sensor_distance * ant_scale
end

local function sensor_half_width()
   return base_sensor_half_width * ant_scale
end

local function update_ant_scale_from_slider(value)
   ant_scale = 0.65 + value * 1.55
end

--[ slider ]--

local slider = {
   x = 0,
   y = 14,
   w = 152,
   h = 18,
   dragging = false,
   hover = false,
   value = 0.4,
   emphasis = 0.0,
   target_emphasis = 0.0,
   knob_size = 14,
}
update_ant_scale_from_slider(slider.value)

function slider:update_value_from_mouse(x)
   local knob_half = self.knob_size * 0.5
   local usable_left = self.x + knob_half
   local usable_right = self.x + self.w - knob_half
   local value = (x - usable_left) / (usable_right - usable_left)
   self.value = clamp01(value)
   update_ant_scale_from_slider(self.value)
end

function slider:update_hover(x, y)
   local pad = 6
   self.hover = point_in_rect(
      x,
      y,
      self.x - pad,
      self.y - pad,
      self.w + pad * 2,
      self.h + pad * 2
   )
   self.target_emphasis = (self.dragging or self.hover) and 1.0 or 0.0
end

function slider:handle_mouse(mouse_info)
   local x = mouse_info.x or 0
   local y = mouse_info.y or 0

   self:update_hover(x, y)

   if mouse_info.action == "move" then
      if self.dragging then
         self:update_value_from_mouse(x)
      end
      return
   end

   if mouse_info.button ~= 1 then
      return
   end

   if mouse_info.action == "down" then
      if self.hover then
         self.dragging = true
         self.target_emphasis = 1.0
         self:update_value_from_mouse(x)
      end
   elseif mouse_info.action == "up" then
      if self.dragging then
         self:update_value_from_mouse(x)
      end
      self.dragging = false
      self:update_hover(x, y)
   end
end

function slider:update(dt)
   local blend = 1.0 - math.exp(-12.0 * dt)
   self.emphasis = self.emphasis + (self.target_emphasis - self.emphasis) * blend

   if math.abs(self.target_emphasis - self.emphasis) < 0.002 then
      self.emphasis = self.target_emphasis
   end
end

function slider:draw()
   local amount = clamp01(self.emphasis)
   slider_panel_color:set_mix(slider_panel_dim_color, slider_panel_bright_color, amount)
   slider_track_color:set_mix(slider_track_dim_color, slider_track_bright_color, amount)
   slider_fill_color:set_mix(slider_fill_dim_color, slider_fill_bright_color, amount)
   slider_knob_color:set_mix(slider_knob_dim_color, slider_knob_bright_color, amount)
   slider_outline_color:set_mix(
      slider_outline_dim_color,
      slider_outline_bright_color,
      amount
   )

   local panel_pad = 6
   local track_h = 4
   local knob_half = self.knob_size * 0.5
   local track_y = self.y + math.floor((self.h - track_h) * 0.5)
   local knob_x = self.x + knob_half + self.value * (self.w - self.knob_size)
   local knob_y = self.y + self.h * 0.5
   local fill_w = math.max(0, knob_x - self.x)

   canvas:rect(
      self.x - panel_pad,
      self.y - panel_pad,
      self.w + panel_pad * 2,
      self.h + panel_pad * 2,
      slider_panel_color
   )

   local left = self.x - panel_pad - 1
   local right = self.x + self.w + panel_pad + 1
   local top = self.y - panel_pad - 1
   local bottom = self.y + self.h + panel_pad + 1
   canvas:line(left, top, right, top, slider_outline_color)
   canvas:line(left, bottom, right, bottom, slider_outline_color)
   canvas:line(left, top, left, bottom, slider_outline_color)
   canvas:line(right, top, right, bottom, slider_outline_color)

   canvas:rect(self.x, track_y, self.w, track_h, slider_track_color)
   canvas:rect(self.x, track_y, fill_w, track_h, slider_fill_color)
   canvas:rect(
      knob_x - knob_half,
      knob_y - knob_half,
      self.knob_size,
      self.knob_size,
      slider_knob_color
   )
end

--[ ants ]--

local function create_ant(index, ant_color)
   return {
      id = index,
      x = 0,
      y = 0,
      angle = math.random() * math.pi * 2.0,
      desired_angle = 0,
      turn_speed = max_turn_step * (0.8 + math.random() * 0.5),
      step_interval = 0.012 + math.random() * 0.020,
      pause_chance = 0.01 + math.random() * 0.04,
      walk_phase = math.random() * math.pi * 2.0,
      color = ant_color,
      timer = 0.0,
   }
end

local function initialize_ant(ant)
   ant.desired_angle = ant.angle
   ant.speed = ant_speed * ant.step_interval * (0.85 + math.random() * 0.35)
   ant.timer = math.random() * ant.step_interval
end

local function place_ant_randomly(ant)
   ant.x = math.random(ant_margin, math.max(ant_margin, surface_width - ant_margin))
   ant.y = math.random(ant_margin, math.max(ant_margin, surface_height - ant_margin))
end

local function clamp_ant_to_window(ant)
   ant.x = clamp(ant.x, ant_margin, math.max(ant_margin, surface_width - ant_margin))
   ant.y = clamp(ant.y, ant_margin, math.max(ant_margin, surface_height - ant_margin))
end

local function sense_forward_obstacle(ant, all_ants)
   local fx = math.cos(ant.angle)
   local fy = math.sin(ant.angle)
   local nearest_forward = nil
   local steer = 0
   local max_forward_distance = sensor_distance()
   local max_half_width = sensor_half_width()

   for i = 1, #all_ants do
      local other = all_ants[i]
      if other ~= ant then
         local dx = other.x - ant.x
         local dy = other.y - ant.y
         local forward = dx * fx + dy * fy

         if forward > 0.0 and forward < max_forward_distance then
            local lateral = -fy * dx + fx * dy
            if math.abs(lateral) < max_half_width then
               if nearest_forward == nil or forward < nearest_forward then
                  nearest_forward = forward
                  if lateral >= 0 then
                     steer = -1
                  else
                     steer = 1
                  end
               end
            end
         end
      end
   end

   if nearest_forward == nil then
      return 0, 0.0
   end

   return steer, 1.0 - nearest_forward / max_forward_distance
end

local function resolve_overlap(ant, all_ants)
   local min_distance = body_radius() * 2.0
   local min_distance_sq = min_distance * min_distance
   local collided = false
   local push_x = 0.0
   local push_y = 0.0

   for i = 1, #all_ants do
      local other = all_ants[i]
      if other ~= ant then
         local dx = ant.x - other.x
         local dy = ant.y - other.y
         local distance_sq = dx * dx + dy * dy

         if distance_sq < min_distance_sq then
            collided = true

            if distance_sq < 0.0001 then
               local angle = math.random() * math.pi * 2.0
               dx = math.cos(angle)
               dy = math.sin(angle)
               distance_sq = 1.0
            end

            local distance = math.sqrt(distance_sq)
            local overlap = min_distance - distance
            push_x = push_x + (dx / distance) * overlap
            push_y = push_y + (dy / distance) * overlap
         end
      end
   end

   if collided then
      ant.x = clamp(ant.x + push_x, ant_margin, math.max(ant_margin, surface_width - ant_margin))
      ant.y = clamp(ant.y + push_y, ant_margin, math.max(ant_margin, surface_height - ant_margin))
      ant.desired_angle = normalize_angle(
         math.atan2(push_y, push_x) + (math.random() - 0.5) * 0.4
      )
   end

   return collided
end

local function step_ant(ant)
   ant.angle = turn_toward(ant.angle, ant.desired_angle, ant.turn_speed)

   local avoid_direction, avoid_strength = sense_forward_obstacle(ant, ants)
   if avoid_direction ~= 0 then
      ant.desired_angle = steer_angle(
         ant.desired_angle,
         avoid_direction * (0.020 + avoid_strength * 0.060)
      )
   end

   local move_scale = 1.0
   if avoid_direction ~= 0 then
      move_scale = 1.0 - math.min(0.95, avoid_strength * 1.4)
      if avoid_strength > 0.65 then
         move_scale = 0.0
      end
   end

   ant.x = ant.x + math.cos(ant.angle) * ant.speed * move_scale
   ant.y = ant.y + math.sin(ant.angle) * ant.speed * move_scale
   ant.walk_phase = normalize_angle(ant.walk_phase + 0.55 + move_scale * 0.65)

   local bounced = false
   local max_x = math.max(ant_margin, surface_width - ant_margin)
   local max_y = math.max(ant_margin, surface_height - ant_margin)

   if ant.x < ant_margin or ant.x > max_x then
      ant.x = clamp(ant.x, ant_margin, max_x)
      ant.desired_angle = normalize_angle(math.pi - ant.angle)
      bounced = true
   end
   if ant.y < ant_margin or ant.y > max_y then
      ant.y = clamp(ant.y, ant_margin, max_y)
      ant.desired_angle = normalize_angle(-ant.angle)
      bounced = true
   end

   if bounced then
      ant.desired_angle = steer_angle(ant.desired_angle, (math.random() - 0.5) * 0.8)
      return
   end

   local collided = resolve_overlap(ant, ants)
   if collided then
      return
   end

   if avoid_direction == 0 then
      local turn_choice = choose_turn()
      if turn_choice ~= 0 then
         ant.desired_angle = steer_angle(
            ant.desired_angle,
            turn_choice * (0.003 + math.random() * 0.006)
         )
      end
   end
end

local function draw_ant(ant)
   local scale = ant_scale
   local cos_angle = math.cos(ant.angle)
   local sin_angle = math.sin(ant.angle)
   local gait = math.sin(ant.walk_phase)
   local gait_opposite = math.sin(ant.walk_phase + math.pi)
   local front_leg_swing = gait * 1.8 * scale
   local back_leg_swing = gait_opposite * 1.6 * scale
   local antenna_swing = gait * 0.9 * scale

   local head_x, head_y = to_world(ant, cos_angle, sin_angle, 5.0 * scale, 0.0)
   local thorax_x, thorax_y = to_world(ant, cos_angle, sin_angle, 0.0, 0.0)
   local abdomen_x, abdomen_y = to_world(ant, cos_angle, sin_angle, -5.0 * scale, 0.0)

   local leg_1_x1, leg_1_y1 = to_world(ant, cos_angle, sin_angle, 1.0 * scale, -1.0 * scale)
   local leg_1_x2, leg_1_y2 = to_world(
      ant,
      cos_angle,
      sin_angle,
      5.0 * scale + front_leg_swing,
      -4.0 * scale - front_leg_swing * 0.6
   )
   local leg_2_x1, leg_2_y1 = to_world(ant, cos_angle, sin_angle, 1.0 * scale, 1.0 * scale)
   local leg_2_x2, leg_2_y2 = to_world(
      ant,
      cos_angle,
      sin_angle,
      5.0 * scale - front_leg_swing,
      4.0 * scale + front_leg_swing * 0.6
   )
   local leg_3_x1, leg_3_y1 = to_world(ant, cos_angle, sin_angle, -2.0 * scale, -1.0 * scale)
   local leg_3_x2, leg_3_y2 = to_world(
      ant,
      cos_angle,
      sin_angle,
      -6.0 * scale - back_leg_swing,
      -4.0 * scale - back_leg_swing * 0.6
   )
   local leg_4_x1, leg_4_y1 = to_world(ant, cos_angle, sin_angle, -2.0 * scale, 1.0 * scale)
   local leg_4_x2, leg_4_y2 = to_world(
      ant,
      cos_angle,
      sin_angle,
      -6.0 * scale + back_leg_swing,
      4.0 * scale + back_leg_swing * 0.6
   )
   local antenna_1_x2, antenna_1_y2 = to_world(
      ant,
      cos_angle,
      sin_angle,
      8.0 * scale,
      -2.0 * scale - antenna_swing
   )
   local antenna_2_x2, antenna_2_y2 = to_world(
      ant,
      cos_angle,
      sin_angle,
      8.0 * scale,
      2.0 * scale + antenna_swing
   )
   local abdomen_radius = math.max(2.0, 2.0 * scale)
   local thorax_radius = math.max(2.0, 2.0 * scale)
   local head_radius = math.max(1.0, 1.5 * scale)

   local ant_color = ant.color
   canvas:rect(
      abdomen_x - abdomen_radius,
      abdomen_y - abdomen_radius,
      abdomen_radius * 2.0,
      abdomen_radius * 2.0,
      ant_color
   )
   canvas:rect(
      thorax_x - thorax_radius,
      thorax_y - thorax_radius,
      thorax_radius * 2.0,
      thorax_radius * 2.0,
      ant_color
   )
   canvas:rect(
      head_x - head_radius,
      head_y - head_radius,
      head_radius * 2.0,
      head_radius * 2.0,
      ant_color
   )

   canvas:line(leg_1_x1, leg_1_y1, leg_1_x2, leg_1_y2, ant_color)
   canvas:line(leg_2_x1, leg_2_y1, leg_2_x2, leg_2_y2, ant_color)
   canvas:line(leg_3_x1, leg_3_y1, leg_3_x2, leg_3_y2, ant_color)
   canvas:line(leg_4_x1, leg_4_y1, leg_4_x2, leg_4_y2, ant_color)
   canvas:line(head_x, head_y, antenna_1_x2, antenna_1_y2, ant_color)
   canvas:line(head_x, head_y, antenna_2_x2, antenna_2_y2, ant_color)
end

local function update_ant(ant, dt)
   ant.timer = ant.timer + dt
   local steps = 0
   while ant.timer >= ant.step_interval and steps < 8 do
      ant.timer = ant.timer - ant.step_interval
      step_ant(ant)
      if math.random() < ant.pause_chance then
         ant.timer = ant.timer - (0.06 + math.random() * 0.18)
      end
      steps = steps + 1
   end
end

--[ text and HUD ]--

local function draw_glyph(glyph, x, y, scale, draw_color)
   for row = 1, #glyph do
      local pattern = glyph[row]
      for col = 1, #pattern do
         if pattern:sub(col, col) == "1" then
            canvas:rect(
               x + (col - 1) * scale,
               y + (row - 1) * scale,
               scale,
               scale,
               draw_color
            )
         end
      end
   end
end

local function draw_text(text, x, y, draw_color, scale)
   local cursor_x = x
   for i = 1, #text do
      local ch = text:sub(i, i)
      local glyph = glyphs[ch] or glyphs[" "]
      draw_glyph(glyph, cursor_x, y, scale, draw_color)
      cursor_x = cursor_x + 4 * scale
   end
end

local function draw_fps_overlay()
   local snapshot = frame_profiler:snapshot()
   local label = ("FPS %d"):format(math.floor(snapshot.fps + 0.5))
   local panel_w = (#label * 4 * font_scale) + 8
   local panel_h = (5 * font_scale) + 8
   local panel_x = 12
   local panel_y = 12

   canvas:rect(panel_x, panel_y, panel_w, panel_h, fps_panel_color)
   draw_text(label, panel_x + 4, panel_y + 4, fps_text_color, font_scale)
end

--[ frame callbacks ]--

local function update(app, frame)
   surface_width = math.max(1, frame.surface.width or 1)
   surface_height = math.max(1, frame.surface.height or 1)
   slider.x = surface_width - 184

   frame_profiler:begin_frame()

   local dt = frame.dt
   slider:update(dt)
   for i = 1, #ants do
      update_ant(ants[i], dt)
   end
end

local function draw_overlay(app, frame)
   surface_width = math.max(1, frame.surface.width or 1)
   surface_height = math.max(1, frame.surface.height or 1)

   frame_profiler:begin_cpu()

   for i = 1, #ants do
      draw_ant(ants[i])
   end
   draw_fps_overlay()
   slider:draw()

   frame_profiler:end_cpu()
   frame_profiler:end_frame()
end

local function on_mouse(app, mouse_info)
   slider:handle_mouse(mouse_info)
end

local function on_resize(app, info)
   surface_width = math.max(1, info.pixel_width or info.width or 1)
   surface_height = math.max(1, info.pixel_height or info.height or 1)
   slider.x = surface_width - 184
   for i = 1, #ants do
      clamp_ant_to_window(ants[i])
   end
end

local function start(app)
   frame_profiler = profiler.FrameProfiler { fps = 60 }
   canvas = app.ctx.draw

   local window = app.ctx.window
   if window ~= nil then
      local pixel_width, pixel_height = window:get_size_in_pixels()
      surface_width = math.max(1, tonumber(pixel_width) or 1)
      surface_height = math.max(1, tonumber(pixel_height) or 1)
   end
   slider.x = surface_width - 184

   for i = 1, ant_count do
      local ant = create_ant(i, palette_cycle[((i - 1) % #palette_cycle) + 1])
      initialize_ant(ant)
      place_ant_randomly(ant)
      ants[i] = ant
   end
end

rig.run {
   title = "Rig " .. backend.label .. " Ants",
   bundle = backend.bundle,
   bundle_options = backend.bundle_options,
   background = background_color,
   build = function(app)
      app:on_update(update)
      app:on_overlay(draw_overlay)
      app:on_mouse(on_mouse)
      app:on_resize(on_resize)
   end,
   start = start,
}
