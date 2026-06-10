local sdl3 = require("sdl3")
local sched = require("sched")
local font = require("font")
local mathx = require("mathx")
local color = require("color")
local profiler = require("profiler")
local time = require("time")
local ffi = require("ffi")

-- Populated by the initial sdl3 on_resize callback before after_setup runs.
local window_width
local window_height
local font_path
local face
local profiler_style
local frame_profiler
local profiler_enabled = true
local vsync_enabled = true

local draw_rect = ffi.new("SDL_FRect[1]")
local src_rect = ffi.new("SDL_FRect[1]")
local dst_rect = ffi.new("SDL_FRect[1]")
local full_alpha = 255
local fixed_animation_dt = 1.0 / 120.0
local max_animation_dt = 0.05
local max_animation_steps_per_frame = 6
local lerp = mathx.lerp
local transparent = color.TRANSPARENT
local sprite_outline_color = color.BLACK:with_alpha(128)
local title_shadow_color = color.BLACK:with_alpha(220)
local profiler_panel_color = color.BLACK:with_alpha(150)
local profiler_header_color = color.rgb(255, 184, 150)
local profiler_body_color = color.rgb(255, 248, 224)
local profiler_warn_color = color.rgb(255, 214, 160)
local profiler_toggle_color = color.rgb(196, 220, 255)
local sprite_outline_offsets = {
   { -2, -2 },
   { 0, -2 },
   { 2, -2 },
   { -2, 0 },
   { 2, 0 },
   { -2, 2 },
   { 0, 2 },
   { 2, 2 },
}

local Sprite = rig.class()
local RasterSplit = rig.class()

local scene = {
   background_color = color.rgb(6, 8, 18),
   scroll_speed = 204.0,
   scroll_wave_amplitude = 48.0,
   scroll_wave_frequency = 0.001,
   scroll_wave_speed = 2.8,
   scroll_loop_gap = 240.0,
   title_shadow_offset = 4,
   raster_split_count = 8,
   sprite_text = "NEON PHANTOMS",
   title_style = nil,
   scroll_style = nil,
   sprite_style = nil,
   raster_texture = nil,
   raster_texture_height = nil,
   title_run = nil,
   scroll_run = nil,
   sprite_glyphs = nil,
   sprites = {},
   raster_splits = {},
   raster_field = {},
   raster_alpha = 1.0,
   raster_preset_index = 1,
   raster_transition_state = "VISIBLE",
   scroll_offset = 0.0,
   scroll_wave_phase = 0.0,
   raster_phase = 0.0,
   sprite_snake_phase = 0.0,
   title_phase = 0.0,
   raster_enabled = true,
   sprites_enabled = true,
   sprite_outline_enabled = true,
   scroller_enabled = true,
   animate_enabled = true,
   animation_driver_task = nil,
   animation_time = 0.0,
   animation_step_generation = 0,
   animation_step_count = 0,
   animation_step_tasks = {},
   animate_tasks = {},
}

function Sprite:init(index, character, glyph)
   self.character = character
   self.glyph = glyph
   self.color = color.rgb(
      110 + ((index * 31) % 145),
      120 + ((index * 47) % 120),
      150 + ((index * 59) % 90)
   )
   self.lag = (index - 1) * 0.32
   self.bob = (index - 1) * 0.21
end

function Sprite:draw(style, layout, snake_phase, outline_enabled)
   local split_top = layout.split_top
   local split_bottom = split_top + layout.split_height
   local phase = snake_phase - self.lag
   local orbit = 0.5 + 0.5 * math.sin(phase * 0.74)
   local alpha = math.floor(145 + 110 * (0.5 + 0.5 * math.sin(phase * 2.2 + 0.4)))
   local scale = 1.08 + 0.44 * (0.5 + 0.5 * math.sin(phase * 1.7 + 0.8))
   local glyph_width = self.glyph.width * scale
   local x = lerp(0, window_width - glyph_width, orbit)
   local glyph_height = self.glyph.height * scale
   local y_phase = 0.5 + 0.5 * math.sin(phase * 1.45 + self.bob)
   local y = lerp(split_top, split_bottom - glyph_height, y_phase)
   local outline_scale = scale * 1.03

   if outline_enabled then
      for i = 1, #sprite_outline_offsets do
         local offset = sprite_outline_offsets[i]
         style:draw_packed_glyph(
            self.glyph,
            x + offset[1],
            y + offset[2],
            sprite_outline_color,
            outline_scale
         )
      end
   end

   self.color.a = alpha
   style:draw_packed_glyph(
      self.glyph,
      x,
      y,
      self.color,
      scale
   )
end

function RasterSplit:init(index)
   self.index = index
   self.offset = 0.0
   self.speed = 0.0
   self.base_offset = 0.0
end

function RasterSplit:apply_preset(preset_index, split_count, offset_step)
   local split_index = self.index
   if preset_index == 1 then -- Random (Original)
      self.offset = math.random() * math.pi * 2.0
      self.speed = 0.5 + math.random() * 0.4
      self.base_offset = (split_index - 1) * offset_step
   elseif preset_index == 2 then -- Smooth Sine
      self.offset = (split_index - 1) * (math.pi * 2.0 / split_count)
      self.speed = 0.7
      self.base_offset = (split_index - 1) * offset_step * 0.5
   elseif preset_index == 3 then -- Linear Slant
      self.offset = (split_index - 1) * 0.4
      self.speed = 0.8
      self.base_offset = (split_index - 1) * offset_step * 0.2
   elseif preset_index == 4 then -- Grouped Pairs
      local group = math.floor((split_index - 1) / 2)
      self.offset = group * 1.5
      self.speed = 0.6 + (group % 2) * 0.3
      self.base_offset = group * offset_step
   end
end

function RasterSplit:draw(renderer, layout, split_width, split_gap, visible_height, line_height, texture_height, field_height)
   local base_x = layout.left + (self.index - 1) * (split_width + split_gap)
   local motion_range = math.floor(layout.split_height / line_height) * 2
   local split_phase = scene.raster_phase * self.speed + self.offset
   local center_offset = self.base_offset + math.sin(split_phase) * (motion_range * 0.5)
   center_offset = math.floor(center_offset + 0.5)

   local source_y = ((center_offset % field_height) + field_height) % field_height
   local source_y_pixels = source_y * line_height

   if source_y_pixels + visible_height <= texture_height then
      src_rect[0].x = 0
      src_rect[0].y = source_y_pixels
      src_rect[0].w = 1
      src_rect[0].h = visible_height
      dst_rect[0].x = base_x
      dst_rect[0].y = layout.split_top
      dst_rect[0].w = split_width
      dst_rect[0].h = visible_height
      if not sdl3.RenderTexture(renderer, scene.raster_texture, src_rect, dst_rect) then
         rig.raise("failed to render raster texture: " .. ffi.string(sdl3.GetError()))
      end
      return
   end

   local first_height = texture_height - source_y_pixels
   local second_height = visible_height - first_height

   src_rect[0].x = 0
   src_rect[0].y = source_y_pixels
   src_rect[0].w = 1
   src_rect[0].h = first_height
   dst_rect[0].x = base_x
   dst_rect[0].y = layout.split_top
   dst_rect[0].w = split_width
   dst_rect[0].h = first_height
   if not sdl3.RenderTexture(renderer, scene.raster_texture, src_rect, dst_rect) then
      rig.raise("failed to render raster texture head: " .. ffi.string(sdl3.GetError()))
   end

   src_rect[0].x = 0
   src_rect[0].y = 0
   src_rect[0].w = 1
   src_rect[0].h = second_height
   dst_rect[0].x = base_x
   dst_rect[0].y = layout.split_top + first_height
   dst_rect[0].w = split_width
   dst_rect[0].h = second_height
   if not sdl3.RenderTexture(renderer, scene.raster_texture, src_rect, dst_rect) then
      rig.raise("failed to render raster texture tail: " .. ffi.string(sdl3.GetError()))
   end
end

local scroll_text = table.concat({
   "+++ NEON PHANTOMS PROUDLY ROLL ACROSS YOUR PHOSPHOR SKY WITH THE MIDNIGHT MIRROR CRACK, THE CLEANEST LIBERATION TO EVER KICK OPEN A LOCKED LOADER. WE DID NOT COME HERE TO WHISPER, WE CAME TO FLOOD THE SCREEN WITH STATIC, BRAGGING RIGHTS, AND A CHORUS OF DISK DRIVES SURRENDERING IN FEAR. BYTEBARON TORE THE PROTECTION NET APART WHILE KID NOVA COUNTED CYCLES LIKE A CLOCKWORK PREDATOR, AND GLITCH WITCH STIRRED THE LAST OBFUSCATED BRANCH INTO A PERFECT LITTLE BONFIRE.",
   "THE PUBLISHER WRAPPED THIS THING IN CHECKSUMS, TIMERS, ANTI DEBUG TRAPS, STUB LOADERS, GARBLED JUMP TABLES, FAKE FAIL PATHS, AND A SAD LITTLE NOTE TO SAY DO NOT COPY. WE READ THAT NOTE, FRAMED IT, LAUGHED AT IT, AND THEN USED IT AS SCRAP PAPER WHILE VECTOR JACK PATCHED THE FINAL GUARD PAGE IN REAL TIME. IRON MUSE TOOK THE TELEMETRY OUT BACK, PACKET JANE CUT THE PHONE HOME ROUTINE INTO DECORATIVE RIBBONS, AND NOISE LORD TURNED THEIR PRECIOUS VM LAYER INTO A SCHOOL LESSON FOR TRAINEES.",
   "THIS RELEASE IS NOT A DIRT QUICK HACK, NOT A HALF ALIVE TRAINER, NOT A MAYBE CRASH MAYBE WORK EXPERIMENT. THIS IS A FULL BLOODED NEON PHANTOMS CRACK WITH THE SCALPEL SHARPENED, THE BINDERY CLEAN, THE STARTUP QUIET, AND THE USER LEFT ALONE WITH NOTHING BUT THE PROGRAM THEY PAID FOR TRYING TO ACT LIKE IT OWNS THE MACHINE. WE REMOVED THE NAG, THE WATCHDOG, THE EXPIRY, THE BACKGROUND NOISE, THE PETTY LITTLE SHACKLES, AND WE LEFT THE ENGINE RUNNING SMOOTHER THAN THE ORIGINAL BUILD.",
   "GREETINGS FLASH ACROSS THE DATA TUNNEL TO EVERY CREW STILL FLYING THEIR COLORS WITH STYLE: LASER CHOIR, COPPER RAIDERS, SPECTRAL SECTOR, TURBOWIRE, STATIC CHILDREN, SILICON HOWL, GLASS VELOCITY, AND THE OLD MASTERS WHO TAUGHT THE REST OF US THAT A PROPER INTRO SHOULD SOUND LIKE THUNDER AND LOOK LIKE A MACHINE DREAMING IN PURE COLOR. RESPECT TO THE CODERS WHO STILL COUNT RASTER LINES, THE MUSICIANS WHO CAN MAKE THREE CHANNELS CRY, AND THE ARTISTS WHO TURN LIMITATION INTO A WEAPON.",
   "THE MIDNIGHT MIRROR TARGET WAS SUPPOSED TO BE THEIR STATEMENT PIECE, A MONUMENT TO LICENSE SERVERS, HEARTBEAT CHECKS, ENCRYPTED ASSET PIPES, AND LEGAL THREATS TYPED BY PEOPLE WHO THINK A WATERMARK IS A FORTRESS. INSTEAD IT BECAME OUR PRACTICE FIELD. WE CAUGHT THEIR THREAD JITTER, WE MAPPED THEIR BOOTSTRAP LAYER, WE FOLLOWED THEIR SELF PATCHING STUB INTO ITS DEN, AND WE LEFT WITH THE KEYS HANGING FROM OUR BELTS. WHEN THE FIRST UNPACKED FRAME LIT UP THE DEBUG VIEW, SINE PRIEST JUST SAID ANOTHER DOOR WITH CHEAP PAINT and EVERYBODY KNEW THE RACE WAS OVER.",
   "CREDITS ON THIS CARTRIDGE OF GLORY GO LIKE THIS: BYTEBARON FOR THE CORE UNWIND, KID NOVA FOR THE PACKER AUTOPSY, GLITCH WITCH FOR THE SANITY SAVING TRACE SCRIPTS, VECTOR JACK FOR THE FILE FORMAT SURGERY, IRON MUSE FOR THE TEST FARM, PACKET JANE FOR THE NETWORK SILENCE, NOISE LORD FOR THE INTRO POLISH, SINE PRIEST FOR THE COLORS, AND RASTER BELLE FOR REMINDING THE WHOLE CREW THAT PRESENTATION STILL MATTERS EVEN WHEN THE BYTES ARE ALREADY BLEEDING ON THE FLOOR. IF YOU RUN THIS RELEASE, YOU RUN THE WORK OF SPECIALISTS.",
   "TO THE RIVAL GROUPS WHO TALK LOUDER THAN THEY DELIVER, WE SEE THE TEASERS, THE TIMERS, THE DRAMA, THE EXCUSES, THE SCREENSHOTS OF HALF PATCHED BINARIES, THE WHINING ABOUT HARDWARE, THE CLAIM THAT THE PROTECTION IS TOO CLEVER THIS WEEK. RAISE YOUR BAR. THE SCENE IS NOT FED BY DELAY TACTICS AND MYSTERY ZIP FILES. IT IS FED BY CLEAN DROPS, GOOD TOOLS, AND THE NERVE TO FINISH THE JOB BEFORE DAWN. WE ARE NOT IMPRESSED BY HYPE, WE ARE IMPRESSED BY FILES THAT BOOT FIRST TIME AND STAY UP ALL NIGHT WITHOUT A SINGLE COMPLAINT.",
   "SO TURN UP THE SPEAKERS, DIM THE ROOM, AND LET THIS MESSAGE WRAP AROUND THE CATHODE LIKE A VICTORY LAP. NEON PHANTOMS CRACKED MIDNIGHT MIRROR, SHOOK THE ICE OUT OF THE LICENSE CAGE, AND LEFT A TRAIL OF BRIGHT FRAGMENTS FOR ANYONE FAST ENOUGH TO READ THEM. MORE TARGETS ARE ALREADY ON THE TABLE, MORE NIGHT SHIFTS ARE ALREADY HUNGRY, AND MORE PUBLISHERS ARE ABOUT TO LEARN THAT A LOCK IS JUST A RIDDLE WAITING FOR BETTER PEOPLE. UNTIL THE NEXT DROP, KEEP YOUR HEX CLEAN, YOUR TIMING TIGHT, AND YOUR NAME BIGGER THAN THE TITLE SCREEN. +++",
}, " "):gsub("%s+", " ")

local function file_exists(path)
   local file = io.open(path, "rb")
   if file == nil then
      return false
   end
   file:close()
   return true
end

local function find_font_path()
   local candidates = {
      "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
      "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
      "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
      "/usr/share/fonts/TTF/DejaVuSans.ttf",
      "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
      "/usr/share/fonts/dejavu/DejaVuSans.ttf",
   }

   for i = 1, #candidates do
      if file_exists(candidates[i]) then
         return candidates[i]
      end
   end

   rig.raise("examples/scroller.lua could not find a system TTF font; install DejaVu Sans or edit the font candidates")
end

local function current_layout()
   return {
      title_y = math.floor(window_height * 0.175 + 0.5),
      split_top = math.floor(window_height * 0.214 + 0.5),
      split_height = math.floor(window_height * 0.433 + 0.5),
      left = math.floor(window_width * 0.069 + 0.5),
      scroll_y = math.floor(window_height * 0.828 + 0.5),
   }
end

local function set_draw_color(renderer, r, g, b, a)
   if not sdl3.SetRenderDrawColor(renderer, r, g, b, a) then
      rig.raise("failed to set renderer color: " .. ffi.string(sdl3.GetError()))
   end
end

local function fill_rect(renderer, x, y, w, h)
   draw_rect[0].x = x
   draw_rect[0].y = y
   draw_rect[0].w = w
   draw_rect[0].h = h
   if not sdl3.RenderFillRect(renderer, draw_rect) then
      rig.raise("failed to draw rectangle: " .. ffi.string(sdl3.GetError()))
   end
end

local function upload_raster_texture(renderer, field, line_height)
   local texture_height = #field * line_height
   local rgba = ffi.new("uint8_t[?]", texture_height * 4)

   for i = 1, #field do
      local color = field[i]
      for line = 0, line_height - 1 do
         local pixel_index = ((i - 1) * line_height + line) * 4
         color:write_rgba8(rgba, pixel_index)
      end
   end

   local texture = sdl3.CreateTexture(
      renderer,
      sdl3.PIXELFORMAT_RGBA32,
      sdl3.TEXTUREACCESS_STATIC,
      1,
      texture_height
   )
   if texture == nil or texture == ffi.NULL then
      rig.raise("failed to create raster texture: " .. ffi.string(sdl3.GetError()))
   end

   if not sdl3.UpdateTexture(texture, nil, rgba, 4) then
      sdl3.DestroyTexture(texture)
      rig.raise("failed to upload raster texture: " .. ffi.string(sdl3.GetError()))
   end

   if not sdl3.SetTextureBlendMode(texture, sdl3.BLENDMODE_BLEND) then
      sdl3.DestroyTexture(texture)
      rig.raise("failed to set raster texture blend mode: " .. ffi.string(sdl3.GetError()))
   end

   return texture, texture_height
end

local function draw_text_run(style, run, base_x, baseline_y, color_fn)
   local glyph_color = color.WHITE:copy()
   for i = 1, #run.entries do
      local entry = run.entries[i]
      local packed = entry.packed
      local draw_x = base_x + entry.layout_x
      local draw_y = baseline_y + entry.layout_y

      if draw_x + packed.width >= -32 then
         if draw_x <= window_width + 32 then
            glyph_color:set(color_fn(i, entry, draw_x, draw_y))
            style:draw_packed_glyph(packed, draw_x, draw_y, glyph_color, 1.0)
         elseif draw_x > window_width + 32 then
            break
         end
      end
   end
end

local function draw_label(style, text, x, baseline_y, draw_color)
   local run = style:build_run(text)
   draw_text_run(style, run, x, baseline_y, function()
      return draw_color
   end)
end

local function apply_preset(index)
   local offset_step = scene.raster_split_count > 0 and (#scene.raster_field / scene.raster_split_count) or 0
   for i = 1, #scene.raster_splits do
      scene.raster_splits[i]:apply_preset(index, scene.raster_split_count, offset_step)
   end
end

local function draw_rasterbars(renderer, layout)
   local split_gap = 1
   local line_height = 2.0
   local total_width = window_width - layout.left * 2
   local split_width = (total_width - split_gap * (scene.raster_split_count - 1)) / scene.raster_split_count
   local field_height = #scene.raster_field
   local visible_lines = math.floor(layout.split_height / line_height)
   local visible_height = visible_lines * line_height
   local texture_height = scene.raster_texture_height

   if not sdl3.SetTextureAlphaMod(scene.raster_texture, math.floor(scene.raster_alpha * 255 + 0.5)) then
      rig.raise("failed to set raster texture alpha modulation: " .. ffi.string(sdl3.GetError()))
   end

   for i = 1, #scene.raster_splits do
      scene.raster_splits[i]:draw(
         renderer,
         layout,
         split_width,
         split_gap,
         visible_height,
         line_height,
         texture_height,
         field_height
      )
   end
end

local function build_raster_field()
   local function add_color_line(field, r, g, b, a, repeat_count)
      repeat_count = repeat_count or 1
      for _ = 1, repeat_count do
         field[#field + 1] = color.rgba(r, g, b, a)
      end
   end

   local function add_spacer(field, line_count)
      for _ = 1, line_count do
         field[#field + 1] = transparent:copy()
      end
   end

   local function build_bar_intensity_profile()
      local profile = {}
      local radius = 18
      local sidebands = {
         { offset = 0, amplitude = 100 },
         { offset = -8, amplitude = 98 },
         { offset = 8, amplitude = 98 },
         { offset = -16, amplitude = 94 },
         { offset = 16, amplitude = 94 },
         { offset = -24, amplitude = 88 },
         { offset = 24, amplitude = 88 },
         { offset = -32, amplitude = 80 },
         { offset = 32, amplitude = 80 },
         { offset = -40, amplitude = 70 },
         { offset = 40, amplitude = 70 },
      }

      for x = -52, 52 do
         local strength = 0
         for i = 1, #sidebands do
            local band = sidebands[i]
            local distance = math.abs(x - band.offset)
            if distance <= radius then
               local value = band.amplitude * (1.0 - distance / radius)
               if value > strength then
                  strength = value
               end
            end
         end
         profile[#profile + 1] = math.floor(strength + 0.5)
      end

      while #profile > 0 and profile[1] == 0 do
         table.remove(profile, 1)
      end
      while #profile > 0 and profile[#profile] == 0 do
         table.remove(profile, #profile)
      end

      return profile
   end

   local function append_bar(field, profile, tint)
      for i = 1, #profile do
         local intensity = profile[i] / 100.0
         -- Keep the warm highlight mix but slightly tighter
         local center_mix = intensity * intensity * 0.92
         local hr, hg, hb = 255, 255, 210
         local r = math.floor((tint.r * intensity * (1.0 - center_mix) + hr * center_mix) + 0.5)
         local g = math.floor((tint.g * intensity * (1.0 - center_mix) + hg * center_mix) + 0.5)
         local b = math.floor((tint.b * intensity * (1.0 - center_mix) + hb * center_mix) + 0.5)
         -- Use square root for alpha so it stays opaque much longer at the edges
         local a = math.floor(255 * math.sqrt(intensity) + 0.5)
         add_color_line(field, r, g, b, a, 1)
      end
   end

   local field = {}
   local profile = build_bar_intensity_profile()
   local tints = {
      color.rgb(255, 0, 0),    -- Red
      color.rgb(255, 127, 0),  -- Orange
      color.rgb(255, 255, 0),  -- Yellow
      color.rgb(0, 255, 0),    -- Green
      color.rgb(0, 255, 255),  -- Cyan
      color.rgb(0, 100, 255),  -- Blue
      color.rgb(139, 0, 255),  -- Violet
      color.rgb(255, 0, 127),  -- Rose
   }

   for i = 1, #tints do
      append_bar(field, profile, tints[i])
   end

   return field
end

local function calc_title_color(out, index)
   local phase = scene.title_phase + index * 0.42
   local r = math.floor(125 + 120 * (0.5 + 0.5 * math.sin(phase)))
   local g = math.floor(130 + 110 * (0.5 + 0.5 * math.sin(phase + 2.1)))
   local b = math.floor(150 + 105 * (0.5 + 0.5 * math.sin(phase + 4.2)))
   out:set(r, g, b, full_alpha)
   return out
end

local function draw_title(renderer, layout)
   local title_baseline_y = layout.title_y
   local run = scene.title_run
   local base_x = (window_width - run.width) * 0.5

   draw_text_run(scene.title_style, run, base_x + scene.title_shadow_offset, title_baseline_y + scene.title_shadow_offset, function()
      return title_shadow_color
   end)

   local draw_color = color.WHITE:copy()
   draw_text_run(scene.title_style, run, base_x, title_baseline_y, function(index)
      return calc_title_color(draw_color, index)
   end)
end

local function calc_scroll_color(out, index, x, y)
   local phase = scene.raster_phase * 1.7 + index * 0.18 + x * 0.003
   local r = math.floor(150 + 105 * (0.5 + 0.5 * math.sin(phase)))
   local g = math.floor(110 + 130 * (0.5 + 0.5 * math.sin(phase + 1.9)))
   local b = math.floor(80 + 165 * (0.5 + 0.5 * math.sin(phase + 3.7)))
   local a = math.floor(220 + 35 * (0.5 + 0.5 * math.sin(phase + y * 0.01)))
   out:set(r, g, b, a)
   return out
end

local function draw_scroller_copy(renderer, layout, base_x)
   local scroll_baseline_y = layout.scroll_y
   local run = scene.scroll_run
   local glyph_color = color.WHITE:copy()
   for i = 1, #run.entries do
      local entry = run.entries[i]
      local packed = entry.packed
      local x = base_x + entry.layout_x
      local y = scroll_baseline_y + entry.layout_y
      local wave_phase = scene.scroll_wave_phase
         + entry.layout_x * scene.scroll_wave_frequency
         + i * 0.11
      y = y + math.sin(wave_phase) * scene.scroll_wave_amplitude

      if x + packed.width >= -48 then
         if x <= window_width + 48 then
            calc_scroll_color(glyph_color, i, x, y)
            scene.scroll_style:draw_packed_glyph(packed, x, y, glyph_color, 1.0)
         elseif x > window_width + 48 then
            break
         end
      end
   end
end

local function draw_scroller(renderer, layout)
   local run = scene.scroll_run
   local first_x = window_width - scene.scroll_offset
   draw_scroller_copy(renderer, layout, first_x)

   local second_x = first_x + run.width + scene.scroll_loop_gap
   if second_x < window_width + 96 then
      draw_scroller_copy(renderer, layout, second_x)
   end
end

local function draw_profiler(renderer)
   local profile = frame_profiler:snapshot()
   local panel_x = 18
   local panel_y = 16
   local panel_w = 378
   local panel_h = 194

   set_draw_color(renderer, profiler_panel_color:unpack())
   fill_rect(renderer, panel_x, panel_y, panel_w, panel_h)

   local text_x = panel_x + 10
   local header = "      CUR / 1S / MAX"
   local line_1 = ("CPU %.2f / %.2f / %.2f"):format(profile.cpu_ms, profile.cpu_max_1s_ms, profile.cpu_max_ms)
   local line_2 = ("PRS %.2f / %.2f / %.2f"):format(profile.present_ms, profile.present_max_1s_ms, profile.present_max_ms)
   local line_3 = ("TOT %.2f / %.2f / %.2f"):format(profile.total_ms, profile.total_max_1s_ms, profile.total_max_ms)
   local line_4 = ("INT %.2f / %.2f / %.2f"):format(profile.interval_ms, profile.interval_max_1s_ms, profile.interval_max_ms)
   local line_5 = ("GAP %.2f / %.2f / %.2f"):format(profile.gap_ms, profile.gap_max_1s_ms, profile.gap_max_ms)
   local line_6 = ("OVR %d"):format(profile.overruns)
   local line_7 = vsync_enabled and "VSYNC ON [V]" or "VSYNC OFF [V]"
   local line_8 = scene.raster_enabled and "RASTER ON [1]" or "RASTER OFF [1]"
   local line_9 = scene.sprites_enabled and "SPRITES ON [2]" or "SPRITES OFF [2]"
   local line_10 = scene.sprite_outline_enabled and "OUTLINE ON [3]" or "OUTLINE OFF [3]"
   local line_11 = scene.scroller_enabled and "SCROLLER ON [4]" or "SCROLLER OFF [4]"
   local line_12 = scene.animate_enabled and "ANIM ON [5]" or "ANIM OFF [5]"
   local line_13 = "PROFILER ON [0]"

   draw_label(profiler_style, header, text_x, panel_y + 16, profiler_header_color)
   draw_label(profiler_style, line_1, text_x, panel_y + 32, profiler_body_color)
   draw_label(profiler_style, line_2, text_x, panel_y + 48, profiler_body_color)
   draw_label(profiler_style, line_3, text_x, panel_y + 64, profiler_body_color)
   draw_label(profiler_style, line_4, text_x, panel_y + 80, profiler_body_color)
   draw_label(profiler_style, line_5, text_x, panel_y + 96, profiler_body_color)
   draw_label(profiler_style, line_6, text_x, panel_y + 112, profiler_warn_color)
   draw_label(profiler_style, line_7, text_x, panel_y + 128, profiler_toggle_color)
   draw_label(profiler_style, line_8, text_x, panel_y + 144, profiler_toggle_color)
   draw_label(profiler_style, line_9, text_x + 150, panel_y + 144, profiler_toggle_color)
   draw_label(profiler_style, line_10, text_x, panel_y + 160, profiler_toggle_color)
   draw_label(profiler_style, line_11, text_x + 150, panel_y + 160, profiler_toggle_color)
   draw_label(profiler_style, line_12, text_x, panel_y + 176, profiler_toggle_color)
   draw_label(profiler_style, line_13, text_x + 150, panel_y + 176, profiler_toggle_color)
end

local function set_vsync(enabled)
   local renderer = sdl3.get_renderer()
   local interval = enabled and 1 or 0
   if not sdl3.SetRenderVSync(renderer, interval) then
      rig.raise("failed to set renderer vsync: " .. ffi.string(sdl3.GetError()))
   end
   vsync_enabled = enabled
end

local function toggle_vsync()
   set_vsync(not vsync_enabled)
end

local function set_animation_enabled(enabled)
   scene.animate_enabled = enabled

   if enabled then
      local scheduler = sched.active_scheduler()
      if scheduler ~= nil then
         if scene.animation_driver_task ~= nil then
            scheduler:wake(scene.animation_driver_task)
         end
         for i = 1, #scene.animate_tasks do
            scheduler:wake(scene.animate_tasks[i])
         end
      end
   end
end

local function toggle_animation()
   set_animation_enabled(not scene.animate_enabled)
end

local function on_key(key_info)
   if key_info.action ~= "down" or key_info["repeat"] then
      return
   end

   if key_info.key == "0" then
      profiler_enabled = not profiler_enabled
   elseif key_info.key == "V" or key_info.key == "v" then
      toggle_vsync()
   elseif key_info.key == "1" then
      scene.raster_enabled = not scene.raster_enabled
   elseif key_info.key == "2" then
      scene.sprites_enabled = not scene.sprites_enabled
   elseif key_info.key == "3" then
      scene.sprite_outline_enabled = not scene.sprite_outline_enabled
   elseif key_info.key == "4" then
      scene.scroller_enabled = not scene.scroller_enabled
   elseif key_info.key == "5" then
      toggle_animation()
   end
end

local function draw_sprites(renderer, layout)
   for i = 1, #scene.sprites do
      scene.sprites[i]:draw(
         scene.sprite_style,
         layout,
         scene.sprite_snake_phase,
         scene.sprite_outline_enabled
      )
   end
end

local function run_animation_driver()
   local last = time.monotonic()
   local accumulator = 0.0

   while true do
      if not scene.animate_enabled then
         sched.park()
         last = time.monotonic()
      end

      local now = time.monotonic()
      local dt = now - last
      last = now
      if dt < 0.0 then
         dt = 0.0
      elseif dt > max_animation_dt then
         dt = max_animation_dt
      end

      accumulator = accumulator + dt
      local steps = 0
      while accumulator >= fixed_animation_dt and steps < max_animation_steps_per_frame do
         accumulator = accumulator - fixed_animation_dt
         steps = steps + 1
      end

      if steps == max_animation_steps_per_frame and accumulator > fixed_animation_dt then
         accumulator = fixed_animation_dt
      end

      if steps > 0 then
         scene.animation_time = scene.animation_time + steps * fixed_animation_dt
         scene.animation_step_count = steps
         scene.animation_step_generation = scene.animation_step_generation + 1

         local scheduler = sched.active_scheduler()
         if scheduler ~= nil then
            for i = 1, #scene.animation_step_tasks do
               scheduler:wake(scene.animation_step_tasks[i])
            end
         end
      end

      sched.yield()
   end
end

local function next_animation_steps(last_generation)
   while true do
      if not scene.animate_enabled then
         sched.park()
      elseif scene.animation_step_generation ~= last_generation then
         return scene.animation_step_generation, scene.animation_step_count
      else
         sched.park()
      end
   end
end

local function run_object_animation(update_step)
   local generation = scene.animation_step_generation
   while true do
      local step_count
      generation, step_count = next_animation_steps(generation)
      for _ = 1, step_count do
         update_step(fixed_animation_dt)
      end
   end
end

local function sleep_scene_time(duration)
   local deadline = scene.animation_time + duration
   local generation = scene.animation_step_generation

   while scene.animation_time < deadline do
      generation = next_animation_steps(generation)
   end
end

local function fade_raster_alpha(from_alpha, to_alpha, duration)
   local generation = scene.animation_step_generation
   local elapsed = 0.0

   while elapsed < duration do
      local step_count
      generation, step_count = next_animation_steps(generation)
      for _ = 1, step_count do
         elapsed = math.min(duration, elapsed + fixed_animation_dt)
         local t = elapsed / duration
         scene.raster_alpha = lerp(from_alpha, to_alpha, t)
      end
   end
end

local function animate_raster_phase()
   run_object_animation(function(dt)
      scene.raster_phase = scene.raster_phase + dt * 1.6
   end)
end

local function animate_raster_transition()
   local visible_duration = 4.0
   local fade_duration = 0.5

   while true do
      scene.raster_transition_state = "VISIBLE"
      scene.raster_alpha = 1.0
      sleep_scene_time(visible_duration)

      scene.raster_transition_state = "FADING_OUT"
      fade_raster_alpha(1.0, 0.0, fade_duration)
      scene.raster_alpha = 0.0

      scene.raster_transition_state = "SWITCHING"
      scene.raster_preset_index = (scene.raster_preset_index % 4) + 1
      apply_preset(scene.raster_preset_index)

      scene.raster_transition_state = "FADING_IN"
      fade_raster_alpha(0.0, 1.0, fade_duration)
      scene.raster_alpha = 1.0
   end
end

local function animate_scroller()
   local period = scene.scroll_run.width + scene.scroll_loop_gap
   run_object_animation(function(dt)
      scene.scroll_offset = (scene.scroll_offset + scene.scroll_speed * dt) % period
      scene.scroll_wave_phase = scene.scroll_wave_phase + dt * scene.scroll_wave_speed
   end)
end

local function animate_sprites()
   run_object_animation(function(dt)
      scene.sprite_snake_phase = scene.sprite_snake_phase + dt * 2.35
   end)
end

local function animate_title()
   run_object_animation(function(dt)
      scene.title_phase = scene.title_phase + dt * 1.8
   end)
end

local function create_sprite_glyphs(sprite_style, text)
   local glyphs = {}
   for i = 1, #text do
      local character = text:sub(i, i)
      if glyphs[character] == nil then
         local shaped = font.shape(sprite_style.sized_face, character)
         glyphs[character] = sprite_style:get_glyph(shaped.glyphs[1].glyph_id)
      end
   end
   return glyphs
end

local function initialize_scene()
   local renderer = sdl3.get_renderer()
   font_path = find_font_path()
   face = font.load_face(font_path)
   frame_profiler = profiler.FrameProfiler()
   scene.title_style = font.create_style(face, {
      pixel_size = 74,
      page_width = 512,
      page_height = 256,
      padding = 2,
   })
   scene.scroll_style = font.create_style(face, {
      pixel_size = 38,
      page_width = 1024,
      page_height = 512,
      padding = 2,
   })
   scene.sprite_style = font.create_style(face, {
      pixel_size = 82,
      page_width = 256,
      page_height = 256,
      padding = 2,
   })
   profiler_style = font.create_style(face, {
      pixel_size = 14,
      page_width = 256,
      page_height = 128,
      padding = 1,
   })

   scene.title_run = scene.title_style:build_run("NEON PHANTOMS")
   scene.scroll_run = scene.scroll_style:build_run(scroll_text)
   scene.sprite_glyphs = create_sprite_glyphs(scene.sprite_style, scene.sprite_text)
   profiler_style:warm_text(
      "CPU PRS TOT INT GAP OVR CUR MAX VSYNC RASTER SPRITES OUTLINE SCROLLER ANIM PROFILER ON OFF [] 0123456789./-"
   )

   scene.raster_field = build_raster_field()
   scene.raster_texture, scene.raster_texture_height =
      upload_raster_texture(renderer, scene.raster_field, 2)
   scene.raster_splits = {}
   for i = 1, scene.raster_split_count do
      scene.raster_splits[i] = RasterSplit(i)
   end
   scene.raster_alpha = 1.0
   scene.raster_transition_state = "VISIBLE"
   scene.animation_time = 0.0
   scene.animation_step_generation = 0
   scene.animation_step_count = 0
   apply_preset(1)

   scene.sprites = {}
   for i = 1, #scene.sprite_text do
      local character = scene.sprite_text:sub(i, i)
      scene.sprites[i] = Sprite(i, character, scene.sprite_glyphs[character])
   end

   scene.animation_driver_task = sched.spawn(run_animation_driver)
   scene.animation_step_tasks = {
      sched.spawn(animate_raster_phase),
      sched.spawn(animate_raster_transition),
      sched.spawn(animate_scroller),
      sched.spawn(animate_sprites),
      sched.spawn(animate_title),
   }
   scene.animate_tasks = {
      scene.animation_step_tasks[1],
      scene.animation_step_tasks[2],
      scene.animation_step_tasks[3],
      scene.animation_step_tasks[4],
      scene.animation_step_tasks[5],
   }
end

local function release_scene()
   frame_profiler = nil
   scene.animation_driver_task = nil
   scene.animation_time = 0.0
   scene.animation_step_generation = 0
   scene.animation_step_count = 0
   scene.animation_step_tasks = {}
   scene.animate_tasks = {}
   if scene.raster_texture ~= nil and scene.raster_texture ~= ffi.NULL then
      sdl3.DestroyTexture(scene.raster_texture)
      scene.raster_texture = nil
   end
   scene.raster_texture_height = nil

   if scene.title_style ~= nil then
      scene.title_style:release()
      scene.title_style = nil
   end
   if scene.scroll_style ~= nil then
      scene.scroll_style:release()
      scene.scroll_style = nil
   end
   if scene.sprite_style ~= nil then
      scene.sprite_style:release()
      scene.sprite_style = nil
   end
   if profiler_style ~= nil then
      profiler_style:release()
      profiler_style = nil
   end
   if face ~= nil then
      face:release()
      face = nil
   end
   font_path = nil
end

local function render_frame()
   frame_profiler:begin_cpu()
   local renderer = sdl3.get_renderer()
   local layout = current_layout()
   set_draw_color(
      renderer,
      scene.background_color:unpack()
   )
   if not sdl3.RenderClear(renderer) then
      rig.raise("failed to clear SDL renderer: " .. ffi.string(sdl3.GetError()))
   end

   if scene.raster_enabled then
      draw_rasterbars(renderer, layout)
   end
   if scene.sprites_enabled then
      draw_sprites(renderer, layout)
   end
   --draw_title(renderer, layout)
   if scene.scroller_enabled then
      draw_scroller(renderer, layout)
   end
   if profiler_enabled then
      draw_profiler(renderer)
   end
   frame_profiler:end_cpu()
end

local function on_resize(info)
   window_width = math.max(1, info.width)
   window_height = math.max(1, info.height)
end

rig.run {
   mode = "sdl3",
   event_handlers = {
      key = on_key,
      resize = on_resize,
   },
   driver_config = {
      sdl3 = {
         window_props = {
            [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "Neon Phantoms - Midnight Mirror Cracktro",
            [sdl3.PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN] = true,
         },
         render = render_frame,
      },
   },
   hooks = {
      after_setup = initialize_scene,
      before_frame = function()
         frame_profiler:begin_frame()
      end,
      after_frame = function()
         frame_profiler:end_frame()
      end,
      before_shutdown = release_scene,
   },
}
