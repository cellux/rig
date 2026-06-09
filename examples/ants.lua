local sdl3 = require("sdl3")
local sched = require("sched")
local mathx = require("mathx")
local profiler = require("profiler")
local ffi = require("ffi")

-- Populated by the initial sdl3 on_resize callback before after_setup runs.
local window_width
local window_height
local ant_count = 96
local ant_speed = 52.0
local ant_margin = 8
local font_scale = 4
local base_sensor_distance = 16.0
local base_sensor_half_width = 6.0
local base_body_radius = 6.0
local max_turn_step = 0.12
local ant_scale = 1.0

local Ant = rig.class()
local Slider = rig.class()

local ants = {}
local rect = ffi.new("SDL_FRect[1]")
local frame_profiler = profiler.FrameProfiler()
local slider
local clamp = mathx.clamp
local clamp01 = mathx.clamp01
local lerp = mathx.lerp

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
      rig.raise("failed to set renderer color: " .. ffi.string(sdl3.GetError()))
   end
end

local function point_in_rect(x, y, rx, ry, rw, rh)
   return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function update_ant_scale_from_slider(value)
   ant_scale = 0.65 + value * 1.55
end

local function fill_rect(renderer, x, y, w, h)
   rect[0].x = x
   rect[0].y = y
   rect[0].w = w
   rect[0].h = h
   if not sdl3.RenderFillRect(renderer, rect) then
      rig.raise("failed to draw ant segment: " .. ffi.string(sdl3.GetError()))
   end
end

local function draw_line(renderer, x1, y1, x2, y2)
   if not sdl3.RenderLine(renderer, x1, y1, x2, y2) then
      rig.raise("failed to draw ant leg: " .. ffi.string(sdl3.GetError()))
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

function Slider:init()
   self.x = nil
   self.y = 14
   self.w = 152
   self.h = 18
   self.dragging = false
   self.hover = false
   self.value = 0.4
   self.emphasis = 0.0
   self.target_emphasis = 0.0
   self.knob_size = 14
   update_ant_scale_from_slider(self.value)
end

function Slider:update_value_from_mouse(x)
   local knob_half = self.knob_size * 0.5
   local usable_left = self.x + knob_half
   local usable_right = self.x + self.w - knob_half
   local value = (x - usable_left) / (usable_right - usable_left)
   self.value = clamp01(value)
   update_ant_scale_from_slider(self.value)
end

function Slider:update_hover(x, y)
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

function Slider:handle_mouse(mouse_info)
   local x = mouse_info.x or 0
   local y = mouse_info.y or 0

   self:update_hover(x, y)

   if mouse_info.action == "move" then
      if self.dragging then
         self:update_value_from_mouse(x)
      end
      return
   end

   if mouse_info.button ~= sdl3.BUTTON_LEFT then
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

function Slider:tick()
   self.emphasis = self.emphasis
      + (self.target_emphasis - self.emphasis) * 0.35

   if math.abs(self.target_emphasis - self.emphasis) < 0.002 then
      self.emphasis = self.target_emphasis
   end
end

slider = Slider()

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
   local profile = frame_profiler:snapshot()
   local label = ("FPS %d"):format(math.floor(profile.fps + 0.5))
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

function Slider:draw(renderer)
   local amount = clamp01(self.emphasis)
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
   local knob_half = self.knob_size * 0.5
   local track_y = self.y + math.floor((self.h - track_h) * 0.5)
   local knob_x = self.x + knob_half + self.value * (self.w - self.knob_size)
   local knob_y = self.y + self.h * 0.5
   local fill_w = math.max(0, knob_x - self.x)
   local outline_color = mix_color(
      { 0.18, 0.10, 0.04, 1.0 },
      { 1.00, 0.74, 0.24, 1.0 },
      amount
   )

   set_color(renderer, panel_color)
   fill_rect(
      renderer,
      self.x - panel_pad,
      self.y - panel_pad,
      self.w + panel_pad * 2,
      self.h + panel_pad * 2
   )

   set_color(renderer, outline_color)
   draw_line(
      renderer,
      self.x - panel_pad - 1,
      self.y - panel_pad - 1,
      self.x + self.w + panel_pad + 1,
      self.y - panel_pad - 1
   )
   draw_line(
      renderer,
      self.x - panel_pad - 1,
      self.y + self.h + panel_pad + 1,
      self.x + self.w + panel_pad + 1,
      self.y + self.h + panel_pad + 1
   )
   draw_line(
      renderer,
      self.x - panel_pad - 1,
      self.y - panel_pad - 1,
      self.x - panel_pad - 1,
      self.y + self.h + panel_pad + 1
   )
   draw_line(
      renderer,
      self.x + self.w + panel_pad + 1,
      self.y - panel_pad - 1,
      self.x + self.w + panel_pad + 1,
      self.y + self.h + panel_pad + 1
   )

   set_color(renderer, track_color)
   fill_rect(renderer, self.x, track_y, self.w, track_h)

   set_color(renderer, fill_color)
   fill_rect(renderer, self.x, track_y, fill_w, track_h)

   set_color(renderer, knob_color)
   fill_rect(
      renderer,
      knob_x - knob_half,
      knob_y - knob_half,
      self.knob_size,
      self.knob_size
   )
end

function Ant:init(index, color)
   self.id = index
   self.x = math.random(ant_margin, window_width - ant_margin)
   self.y = math.random(ant_margin, window_height - ant_margin)
   self.angle = math.random() * math.pi * 2.0
   self.desired_angle = self.angle
   self.turn_speed = max_turn_step * (0.8 + math.random() * 0.5)
   self.step_interval = 0.012 + math.random() * 0.020
   self.pause_chance = 0.01 + math.random() * 0.04
   self.walk_phase = math.random() * math.pi * 2.0
   self.color = color
   self.speed = ant_speed * self.step_interval * (0.85 + math.random() * 0.35)
end

function Ant:draw(renderer)
   local scale = ant_scale
   local cos_angle = math.cos(self.angle)
   local sin_angle = math.sin(self.angle)
   local gait = math.sin(self.walk_phase)
   local gait_opposite = math.sin(self.walk_phase + math.pi)
   local front_leg_swing = gait * 1.8 * scale
   local back_leg_swing = gait_opposite * 1.6 * scale
   local antenna_swing = gait * 0.9 * scale

   local head_x, head_y = to_world(self, cos_angle, sin_angle, 5.0 * scale, 0.0)
   local thorax_x, thorax_y = to_world(self, cos_angle, sin_angle, 0.0, 0.0)
   local abdomen_x, abdomen_y = to_world(self, cos_angle, sin_angle, -5.0 * scale, 0.0)

   local leg_1_x1, leg_1_y1 = to_world(self, cos_angle, sin_angle, 1.0 * scale, -1.0 * scale)
   local leg_1_x2, leg_1_y2 = to_world(
      self,
      cos_angle,
      sin_angle,
      5.0 * scale + front_leg_swing,
      -4.0 * scale - front_leg_swing * 0.6
   )
   local leg_2_x1, leg_2_y1 = to_world(self, cos_angle, sin_angle, 1.0 * scale, 1.0 * scale)
   local leg_2_x2, leg_2_y2 = to_world(
      self,
      cos_angle,
      sin_angle,
      5.0 * scale - front_leg_swing,
      4.0 * scale + front_leg_swing * 0.6
   )
   local leg_3_x1, leg_3_y1 = to_world(self, cos_angle, sin_angle, -2.0 * scale, -1.0 * scale)
   local leg_3_x2, leg_3_y2 = to_world(
      self,
      cos_angle,
      sin_angle,
      -6.0 * scale - back_leg_swing,
      -4.0 * scale - back_leg_swing * 0.6
   )
   local leg_4_x1, leg_4_y1 = to_world(self, cos_angle, sin_angle, -2.0 * scale, 1.0 * scale)
   local leg_4_x2, leg_4_y2 = to_world(
      self,
      cos_angle,
      sin_angle,
      -6.0 * scale + back_leg_swing,
      4.0 * scale + back_leg_swing * 0.6
   )
   local antenna_1_x2, antenna_1_y2 = to_world(
      self,
      cos_angle,
      sin_angle,
      8.0 * scale,
      -2.0 * scale - antenna_swing
   )
   local antenna_2_x2, antenna_2_y2 = to_world(
      self,
      cos_angle,
      sin_angle,
      8.0 * scale,
      2.0 * scale + antenna_swing
   )
   local abdomen_radius = math.max(2.0, 2.0 * scale)
   local thorax_radius = math.max(2.0, 2.0 * scale)
   local head_radius = math.max(1.0, 1.5 * scale)

   set_color(renderer, self.color)
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

function Ant:sense_forward_obstacle(all_ants)
   local fx = math.cos(self.angle)
   local fy = math.sin(self.angle)
   local nearest_forward = nil
   local steer = 0
   local max_forward_distance = sensor_distance()
   local max_half_width = sensor_half_width()

   for i = 1, #all_ants do
      local other = all_ants[i]
      if other ~= self then
         local dx = other.x - self.x
         local dy = other.y - self.y
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

function Ant:resolve_overlap(all_ants)
   local min_distance = body_radius() * 2.0
   local min_distance_sq = min_distance * min_distance
   local collided = false
   local push_x = 0.0
   local push_y = 0.0

   for i = 1, #all_ants do
      local other = all_ants[i]
      if other ~= self then
         local dx = self.x - other.x
         local dy = self.y - other.y
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
      self.x = clamp(self.x + push_x, ant_margin, window_width - ant_margin)
      self.y = clamp(self.y + push_y, ant_margin, window_height - ant_margin)
      self.desired_angle = normalize_angle(
         math.atan2(push_y, push_x) + (math.random() - 0.5) * 0.4
      )
   end

   return collided
end

function Ant:clamp_to_window()
   self.x = clamp(self.x, ant_margin, window_width - ant_margin)
   self.y = clamp(self.y, ant_margin, window_height - ant_margin)
end

local function animate_slider()
   while true do
      slider:tick()
      sched.yield()
   end
end

function Ant:step(all_ants)
   self.angle = turn_toward(self.angle, self.desired_angle, self.turn_speed)

   local avoid_direction, avoid_strength = self:sense_forward_obstacle(all_ants)
   if avoid_direction ~= 0 then
      self.desired_angle = steer_angle(
         self.desired_angle,
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

   self.x = self.x + math.cos(self.angle) * self.speed * move_scale
   self.y = self.y + math.sin(self.angle) * self.speed * move_scale
   self.walk_phase = normalize_angle(self.walk_phase + 0.55 + move_scale * 0.65)

   local bounced = false

   if self.x < ant_margin or self.x > window_width - ant_margin then
      self.x = clamp(self.x, ant_margin, window_width - ant_margin)
      self.desired_angle = normalize_angle(math.pi - self.angle)
      bounced = true
   end
   if self.y < ant_margin or self.y > window_height - ant_margin then
      self.y = clamp(self.y, ant_margin, window_height - ant_margin)
      self.desired_angle = normalize_angle(-self.angle)
      bounced = true
   end

   if bounced then
      self.desired_angle = steer_angle(
         self.desired_angle,
         (math.random() - 0.5) * 0.8
      )
      return
   end

   local collided = self:resolve_overlap(all_ants)
   if collided then
      return
   end

   if avoid_direction == 0 then
      local turn_choice = choose_turn()
      if turn_choice ~= 0 then
         self.desired_angle = steer_angle(
            self.desired_angle,
            turn_choice * (0.003 + math.random() * 0.006)
         )
      end
   end
end

function Ant:run(all_ants)
   sched.sleep(math.random() * self.step_interval)

   while true do
      self:step(all_ants)

      local delay = self.step_interval
      if math.random() < self.pause_chance then
         delay = delay + 0.06 + math.random() * 0.18
      end

      sched.sleep(delay)
   end
end

local function initialize_ants()
   ants = {}

   for i = 1, ant_count do
      local color = palette[((i - 1) % #palette) + 1]
      local ant = Ant(i, color)
      ants[i] = ant
      sched.spawn(function()
         ant:run(ants)
      end)
   end

   sched.spawn(animate_slider)
end

local function on_render()
   frame_profiler:begin_cpu()
   local renderer = sdl3.get_renderer()
   if renderer == nil then
      rig.raise("sdl3 runtime did not provide a renderer")
   end

   sdl3.clear(0.06, 0.08, 0.05, 1.0)

   for i = 1, #ants do
      ants[i]:draw(renderer)
   end

   draw_fps_overlay(renderer)
   slider:draw(renderer)
   frame_profiler:end_cpu()
end

local function handle_resize(info)
   window_width = math.max(1, info.width)
   window_height = math.max(1, info.height)
   slider.x = window_width - 184

   for i = 1, #ants do
      ants[i]:clamp_to_window()
   end
end

rig.run {
   mode = "sdl3",
   event_handlers = {
      mouse = function(mouse_info)
         slider:handle_mouse(mouse_info)
      end,
      resize = handle_resize,
   },
   driver_config = {
      sdl3 = {
         window_props = {
            [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "Rig SDL Ants",
            [sdl3.PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN] = true,
         },
         render = on_render,
      },
   },
   hooks = {
      after_setup = initialize_ants,
      before_frame = function()
         frame_profiler:begin_frame()
      end,
      after_frame = function()
         frame_profiler:end_frame()
      end,
   },
}
