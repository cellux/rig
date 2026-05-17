local sdl3 = require("sdl3")
local sched = require("sched")
local ffi = ffi

local window_width = 960
local window_height = 540
local ant_count = 96
local ant_speed = 52.0
local ant_margin = 8
local font_scale = 4
local base_sensor_distance = 16.0
local base_sensor_half_width = 6.0
local base_body_radius = 6.0
local max_turn_step = 0.12
local ant_scale = 1.0

local ants = {}
local rect = ffi.new("SDL_FRect[1]")
local perf_frequency = tonumber(sdl3.GetPerformanceFrequency())
local fps_counter_started = tonumber(sdl3.GetPerformanceCounter())
local fps_last_sample = fps_counter_started
local fps_frame_count = 0
local fps_value = 0.0
local slider = {
   x = window_width - 184,
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
ant_scale = 0.65 + slider.value * 1.55

local palette = {
   { 0.92, 0.72, 0.29, 1.0 },
   { 0.93, 0.46, 0.34, 1.0 },
   { 0.36, 0.77, 0.55, 1.0 },
   { 0.38, 0.66, 0.91, 1.0 },
   { 0.84, 0.49, 0.83, 1.0 },
}

local glyphs = {
   ["0"] = {
      "111",
      "101",
      "101",
      "101",
      "111",
   },
   ["1"] = {
      "010",
      "110",
      "010",
      "010",
      "111",
   },
   ["2"] = {
      "111",
      "001",
      "111",
      "100",
      "111",
   },
   ["3"] = {
      "111",
      "001",
      "111",
      "001",
      "111",
   },
   ["4"] = {
      "101",
      "101",
      "111",
      "001",
      "001",
   },
   ["5"] = {
      "111",
      "100",
      "111",
      "001",
      "111",
   },
   ["6"] = {
      "111",
      "100",
      "111",
      "101",
      "111",
   },
   ["7"] = {
      "111",
      "001",
      "001",
      "001",
      "001",
   },
   ["8"] = {
      "111",
      "101",
      "111",
      "101",
      "111",
   },
   ["9"] = {
      "111",
      "101",
      "111",
      "001",
      "111",
   },
   ["F"] = {
      "111",
      "100",
      "110",
      "100",
      "100",
   },
   ["P"] = {
      "110",
      "101",
      "110",
      "100",
      "100",
   },
   ["S"] = {
      "111",
      "100",
      "111",
      "001",
      "111",
   },
   [" "] = {
      "000",
      "000",
      "000",
      "000",
      "000",
   },
}

math.randomseed(tonumber(sdl3.GetPerformanceCounter()))

local function clamp(value, low, high)
   if value < low then
      return low
   end
   if value > high then
      return high
   end
   return value
end

local function clamp01(value)
   return clamp(value, 0.0, 1.0)
end

local function lerp(a, b, t)
   return a + (b - a) * t
end

local function mix_color(dim, bright, amount)
   return {
      lerp(dim[1], bright[1], amount),
      lerp(dim[2], bright[2], amount),
      lerp(dim[3], bright[3], amount),
      lerp(dim[4], bright[4], amount),
   }
end

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

local function set_color(renderer, color)
   local r = math.floor(color[1] * 255 + 0.5)
   local g = math.floor(color[2] * 255 + 0.5)
   local b = math.floor(color[3] * 255 + 0.5)
   local a = math.floor(color[4] * 255 + 0.5)
   if not sdl3.SetRenderDrawColor(renderer, r, g, b, a) then
      error("failed to set renderer color: " .. ffi.string(sdl3.GetError()), 0)
   end
end

local function point_in_rect(x, y, rx, ry, rw, rh)
   return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function fill_rect(renderer, x, y, w, h)
   rect[0].x = x
   rect[0].y = y
   rect[0].w = w
   rect[0].h = h
   if not sdl3.RenderFillRect(renderer, rect) then
      error("failed to draw ant segment: " .. ffi.string(sdl3.GetError()), 0)
   end
end

local function draw_line(renderer, x1, y1, x2, y2)
   if not sdl3.RenderLine(renderer, x1, y1, x2, y2) then
      error("failed to draw ant leg: " .. ffi.string(sdl3.GetError()), 0)
   end
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

local function draw_glyph(renderer, glyph, x, y, scale)
   for row = 1, #glyph do
      local pattern = glyph[row]
      for col = 1, #pattern do
         if pattern:sub(col, col) == "1" then
            fill_rect(
               renderer,
               x + (col - 1) * scale,
               y + (row - 1) * scale,
               scale,
               scale
            )
         end
      end
   end
end

local function draw_text(renderer, text, x, y, scale, color)
   set_color(renderer, color)

   local cursor_x = x
   for i = 1, #text do
      local ch = text:sub(i, i)
      local glyph = glyphs[ch] or glyphs[" "]
      draw_glyph(renderer, glyph, cursor_x, y, scale)
      cursor_x = cursor_x + 4 * scale
   end
end

local function draw_fps_overlay(renderer)
   local label = ("FPS %d"):format(math.floor(fps_value + 0.5))
   local panel_w = (#label * 4 * font_scale) + 8
   local panel_h = (5 * font_scale) + 8
   local panel_x = 12
   local panel_y = 12

   set_color(renderer, { 0.08, 0.09, 0.07, 1.0 })
   fill_rect(renderer, panel_x, panel_y, panel_w, panel_h)

   draw_text(
      renderer,
      label,
      panel_x + 4,
      panel_y + 4,
      font_scale,
      { 0.96, 0.96, 0.88, 1.0 }
   )
end

local function update_slider_value_from_mouse(x)
   local knob_half = slider.knob_size * 0.5
   local usable_left = slider.x + knob_half
   local usable_right = slider.x + slider.w - knob_half
   local value = (x - usable_left) / (usable_right - usable_left)
   slider.value = clamp01(value)
   ant_scale = 0.65 + slider.value * 1.55
end

local function update_slider_hover(x, y)
   local pad = 6
   slider.hover = point_in_rect(
      x,
      y,
      slider.x - pad,
      slider.y - pad,
      slider.w + pad * 2,
      slider.h + pad * 2
   )
   slider.target_emphasis = (slider.dragging or slider.hover) and 1.0 or 0.0
end

local function draw_slider(renderer)
   local amount = clamp01(slider.emphasis)
   local panel_color = mix_color(
      { 0.05, 0.06, 0.05, 0.35 },
      { 0.22, 0.24, 0.22, 0.92 },
      amount
   )
   local track_color = mix_color(
      { 0.18, 0.20, 0.18, 0.45 },
      { 0.84, 0.86, 0.80, 1.0 },
      amount
   )
   local fill_color = mix_color(
      { 0.28, 0.20, 0.10, 0.45 },
      { 0.98, 0.72, 0.26, 1.0 },
      amount
   )
   local knob_color = mix_color(
      { 0.42, 0.42, 0.40, 0.55 },
      { 1.00, 0.99, 0.92, 1.0 },
      amount
   )
   local panel_pad = 6
   local track_h = 4
   local knob_half = slider.knob_size * 0.5
   local track_y = slider.y + math.floor((slider.h - track_h) * 0.5)
   local knob_x = slider.x + knob_half + slider.value * (slider.w - slider.knob_size)
   local knob_y = slider.y + slider.h * 0.5
   local fill_w = math.max(0, knob_x - slider.x)
   local outline_color = mix_color(
      { 0.18, 0.10, 0.04, 1.0 },
      { 1.00, 0.74, 0.24, 1.0 },
      amount
   )

   set_color(renderer, panel_color)
   fill_rect(
      renderer,
      slider.x - panel_pad,
      slider.y - panel_pad,
      slider.w + panel_pad * 2,
      slider.h + panel_pad * 2
   )

   set_color(renderer, outline_color)
   draw_line(
      renderer,
      slider.x - panel_pad - 1,
      slider.y - panel_pad - 1,
      slider.x + slider.w + panel_pad + 1,
      slider.y - panel_pad - 1
   )
   draw_line(
      renderer,
      slider.x - panel_pad - 1,
      slider.y + slider.h + panel_pad + 1,
      slider.x + slider.w + panel_pad + 1,
      slider.y + slider.h + panel_pad + 1
   )
   draw_line(
      renderer,
      slider.x - panel_pad - 1,
      slider.y - panel_pad - 1,
      slider.x - panel_pad - 1,
      slider.y + slider.h + panel_pad + 1
   )
   draw_line(
      renderer,
      slider.x + slider.w + panel_pad + 1,
      slider.y - panel_pad - 1,
      slider.x + slider.w + panel_pad + 1,
      slider.y + slider.h + panel_pad + 1
   )

   set_color(renderer, track_color)
   fill_rect(renderer, slider.x, track_y, slider.w, track_h)

   set_color(renderer, fill_color)
   fill_rect(renderer, slider.x, track_y, fill_w, track_h)

   set_color(renderer, knob_color)
   fill_rect(
      renderer,
      knob_x - knob_half,
      knob_y - knob_half,
      slider.knob_size,
      slider.knob_size
   )
end

local function update_fps()
   fps_frame_count = fps_frame_count + 1

   local now = tonumber(sdl3.GetPerformanceCounter())
   local elapsed = (now - fps_last_sample) / perf_frequency
   if elapsed < 0.25 then
      return
   end

   fps_value = fps_frame_count / elapsed
   fps_frame_count = 0
   fps_last_sample = now
end

local function draw_ant(renderer, ant)
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

   set_color(renderer, ant.color)
   fill_rect(
      renderer,
      abdomen_x - abdomen_radius,
      abdomen_y - abdomen_radius,
      abdomen_radius * 2.0,
      abdomen_radius * 2.0
   )
   fill_rect(
      renderer,
      thorax_x - thorax_radius,
      thorax_y - thorax_radius,
      thorax_radius * 2.0,
      thorax_radius * 2.0
   )
   fill_rect(
      renderer,
      head_x - head_radius,
      head_y - head_radius,
      head_radius * 2.0,
      head_radius * 2.0
   )

   draw_line(renderer, leg_1_x1, leg_1_y1, leg_1_x2, leg_1_y2)
   draw_line(renderer, leg_2_x1, leg_2_y1, leg_2_x2, leg_2_y2)
   draw_line(renderer, leg_3_x1, leg_3_y1, leg_3_x2, leg_3_y2)
   draw_line(renderer, leg_4_x1, leg_4_y1, leg_4_x2, leg_4_y2)
   draw_line(renderer, head_x, head_y, antenna_1_x2, antenna_1_y2)
   draw_line(renderer, head_x, head_y, antenna_2_x2, antenna_2_y2)
end

local function sense_forward_obstacle(ant)
   local fx = math.cos(ant.angle)
   local fy = math.sin(ant.angle)
   local nearest_forward = nil
   local steer = 0
   local max_forward_distance = sensor_distance()
   local max_half_width = sensor_half_width()

   for i = 1, #ants do
      local other = ants[i]
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

local function resolve_overlap(ant)
   local min_distance = body_radius() * 2.0
   local min_distance_sq = min_distance * min_distance
   local collided = false
   local push_x = 0.0
   local push_y = 0.0

   for i = 1, #ants do
      local other = ants[i]
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
      ant.x = clamp(ant.x + push_x, ant_margin, window_width - ant_margin)
      ant.y = clamp(ant.y + push_y, ant_margin, window_height - ant_margin)
      ant.desired_angle = normalize_angle(
         math.atan2(push_y, push_x) + (math.random() - 0.5) * 0.4
      )
   end

   return collided
end

local function handle_mouse(mouse_info)
   local x = mouse_info.x or 0
   local y = mouse_info.y or 0

   update_slider_hover(x, y)

   if mouse_info.action == "move" then
      if slider.dragging then
         update_slider_value_from_mouse(x)
      end
      return
   end

   if mouse_info.button ~= sdl3.BUTTON_LEFT then
      return
   end

   if mouse_info.action == "down" then
      if slider.hover then
         slider.dragging = true
         slider.target_emphasis = 1.0
         update_slider_value_from_mouse(x)
      end
   elseif mouse_info.action == "up" then
      if slider.dragging then
         update_slider_value_from_mouse(x)
      end
      slider.dragging = false
      update_slider_hover(x, y)
   end
end

local function animate_slider()
   while true do
      slider.emphasis = slider.emphasis
         + (slider.target_emphasis - slider.emphasis) * 0.35

      if math.abs(slider.target_emphasis - slider.emphasis) < 0.002 then
         slider.emphasis = slider.target_emphasis
      end

      sched.yield()
   end
end

local function step_ant(ant)
   ant.angle = turn_toward(ant.angle, ant.desired_angle, ant.turn_speed)

   local avoid_direction, avoid_strength = sense_forward_obstacle(ant)
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

   if ant.x < ant_margin or ant.x > window_width - ant_margin then
      ant.x = clamp(ant.x, ant_margin, window_width - ant_margin)
      ant.desired_angle = normalize_angle(math.pi - ant.angle)
      bounced = true
   end
   if ant.y < ant_margin or ant.y > window_height - ant_margin then
      ant.y = clamp(ant.y, ant_margin, window_height - ant_margin)
      ant.desired_angle = normalize_angle(-ant.angle)
      bounced = true
   end

   if bounced then
      ant.desired_angle = steer_angle(
         ant.desired_angle,
         (math.random() - 0.5) * 0.8
      )
      return
   end

   local collided = resolve_overlap(ant)
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

local function run_ant(ant)
   sched.sleep(math.random() * ant.step_interval)

   while true do
      step_ant(ant)

      local delay = ant.step_interval
      if math.random() < ant.pause_chance then
         delay = delay + 0.06 + math.random() * 0.18
      end

      sched.sleep(delay)
   end
end

local function initialize_ants()
   ants = {}

   for i = 1, ant_count do
      local color = palette[((i - 1) % #palette) + 1]
      local ant = {
         x = math.random(ant_margin, window_width - ant_margin),
         y = math.random(ant_margin, window_height - ant_margin),
         angle = math.random() * math.pi * 2.0,
         desired_angle = 0.0,
         turn_speed = max_turn_step * (0.8 + math.random() * 0.5),
         speed = 0.0,
         step_interval = 0.012 + math.random() * 0.020,
         pause_chance = 0.01 + math.random() * 0.04,
         walk_phase = math.random() * math.pi * 2.0,
         color = color,
      }
      ant.desired_angle = ant.angle
      ant.speed = ant_speed * ant.step_interval * (0.85 + math.random() * 0.35)
      ants[i] = ant
      sched.spawn(run_ant, ant)
   end

   sched.spawn(animate_slider)
end

local function on_render()
   local renderer = sdl3.get_renderer()
   if renderer == nil then
      error("sdl3 runtime did not provide a renderer", 0)
   end

   update_fps()
   sdl3.clear(0.06, 0.08, 0.05, 1.0)

   for i = 1, #ants do
      draw_ant(renderer, ants[i])
   end

   draw_fps_overlay(renderer)
   draw_slider(renderer)
end

rig.run {
   mode = "sdl3",
   hooks = {
      after_setup = initialize_ants,
   },
   sdl3 = {
      window_props = {
         [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "Rig SDL Ants",
         [sdl3.PROP_WINDOW_CREATE_WIDTH_NUMBER] = window_width,
         [sdl3.PROP_WINDOW_CREATE_HEIGHT_NUMBER] = window_height,
         [sdl3.PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN] = true,
      },
      on_render = on_render,
      on_mouse = handle_mouse,
   },
}
