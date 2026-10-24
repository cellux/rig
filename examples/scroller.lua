local asset = require("asset")
local color = require("color")
local ffi = require("ffi")
local font = require("font")
local lerp = require("mathx").lerp
local profiler = require("profiler")
local rig = require("rig")

-- A cracktro scroller built entirely on the backend-neutral 2D stack: `font`
-- for the text and `draw` for the rectangles and the scrolling raster field.
-- Nothing here talks to a specific graphics backend, so the same script runs on
-- SDL_Renderer, OpenGL, and SDL_GPU. Pick one with RIG_BACKEND (see
-- examples/backend.lua); the default is `gl`.

local backend = rig.require("./backend").select {
   backends = { renderer = true, gl = true, gpu = true },
}

local face_path = asset.path("../assets/DejaVuSans.ttf")
local tau = math.pi * 2.0

local sprite_outline_color = color.BLACK:with_alpha(128)
local title_shadow_color = color.BLACK:with_alpha(220)
local profiler_panel_color = color.BLACK:with_alpha(150)
local profiler_header_color = color.rgb(255, 184, 150)
local profiler_body_color = color.rgb(255, 248, 224)
local profiler_warn_color = color.rgb(255, 214, 160)
local profiler_toggle_color = color.rgb(196, 220, 255)
local raster_modulate = color.WHITE:copy()
local scratch_glyph_color = color.WHITE:copy()

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

--[ state ]--

local surface_width = 1
local surface_height = 1

local face
local title_style
local scroller_style
local sprite_style
local profiler_style
local title_run
local scroller_run
local sprite_glyphs
local sprites = {}

local state = {
   anim_enabled = true,
   profiler_enabled = true,
   vsync_enabled = true,
   vsync_supported = true,
   fullscreen_enabled = false,
   frame_profiler = nil,
   sprite = {
      enabled = true,
      outline_enabled = true,
      phase = 0.0,
   },
   title = {
      phase = 0.0,
   },
   scroller = {
      enabled = true,
      speed = 204.0,
      wave_amplitude = 48.0,
      wave_frequency = 0.001,
      wave_speed = 2.8,
      loop_gap = 240.0,
      offset = 0.0,
      wave_phase = 0.0,
   },
   raster = {
      enabled = true,
      count = 8,
      items = {},
      field = nil,
      texture = nil,
      texture_height = 0,
      alpha = 1.0,
      preset_index = 1,
      target_preset_index = 1,
      transition_state = "VISIBLE",
      phase = 0.0,
      phase_speed = 1.6,
      preset_hold_duration = 4.0,
      fade_duration = 0.5,
      hold = 0.0,
   },
}

--[ raster field ]--

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
      local center_mix = intensity * intensity * 0.92
      local hr, hg, hb = 255, 255, 210
      local r = math.floor((tint.r * intensity * (1.0 - center_mix) + hr * center_mix) + 0.5)
      local g = math.floor((tint.g * intensity * (1.0 - center_mix) + hg * center_mix) + 0.5)
      local b = math.floor((tint.b * intensity * (1.0 - center_mix) + hb * center_mix) + 0.5)
      local a = math.floor(255 * math.sqrt(intensity) + 0.5)
      field[#field + 1] = color.rgba(r, g, b, a)
   end
end

local function build_raster_field()
   local field = {}
   local profile = build_bar_intensity_profile()
   local tints = {
      color.rgb(255, 0, 0),
      color.rgb(255, 127, 0),
      color.rgb(255, 255, 0),
      color.rgb(0, 255, 0),
      color.rgb(0, 255, 255),
      color.rgb(0, 100, 255),
      color.rgb(139, 0, 255),
      color.rgb(255, 0, 127),
   }

   for i = 1, #tints do
      append_bar(field, profile, tints[i])
   end

   return field
end

-- Packs the line colors into a `1 x (#field * line_height)` RGBA8 byte string,
-- the shape `draw.create_texture` expects.
local function build_raster_pixels(field, line_height)
   local height = #field * line_height
   local rgba = ffi.new("uint8_t[?]", height * 4)

   for i = 1, #field do
      local line_color = field[i]
      for line = 0, line_height - 1 do
         local pixel_index = ((i - 1) * line_height + line) * 4
         line_color:write_rgba8(rgba, pixel_index)
      end
   end

   return ffi.string(rgba, height * 4), height
end

local function apply_split_preset(split, preset_index, split_count, offset_step)
   local split_index = split.index
   if preset_index == 1 then -- Random (Original)
      split.offset = math.random() * tau
      split.speed = 0.5 + math.random() * 0.4
      split.base_offset = (split_index - 1) * offset_step
   elseif preset_index == 2 then -- Smooth Sine
      split.offset = (split_index - 1) * (tau / split_count)
      split.speed = 0.7
      split.base_offset = (split_index - 1) * offset_step * 0.5
   elseif preset_index == 3 then -- Linear Slant
      split.offset = (split_index - 1) * 0.4
      split.speed = 0.8
      split.base_offset = (split_index - 1) * offset_step * 0.2
   elseif preset_index == 4 then -- Grouped Pairs
      local group = math.floor((split_index - 1) / 2)
      split.offset = group * 1.5
      split.speed = 0.6 + (group % 2) * 0.3
      split.base_offset = group * offset_step
   end
end

local function apply_raster_preset(preset_index)
   local raster = state.raster
   raster.preset_index = preset_index
   local offset_step = raster.count > 0 and (#raster.field / raster.count) or 0
   for i = 1, #raster.items do
      apply_split_preset(raster.items[i], preset_index, raster.count, offset_step)
   end
end

local function set_raster_preset(preset_index, snap)
   local raster = state.raster
   raster.target_preset_index = preset_index
   if snap then
      apply_raster_preset(preset_index)
      raster.alpha = 1.0
      raster.transition_state = "VISIBLE"
   end
end

local function update_raster(dt)
   local raster = state.raster
   raster.phase = raster.phase + dt * raster.phase_speed

   raster.hold = raster.hold + dt
   if raster.hold >= raster.preset_hold_duration then
      raster.hold = 0.0
      raster.target_preset_index = (raster.target_preset_index % 4) + 1
   end

   if raster.transition_state == "VISIBLE" then
      if raster.target_preset_index ~= raster.preset_index then
         raster.transition_state = "FADING_OUT"
      end
      return
   end

   if raster.transition_state == "FADING_OUT" then
      raster.alpha = math.max(0.0, raster.alpha - (dt / raster.fade_duration))
      if raster.alpha == 0.0 then
         apply_raster_preset(raster.target_preset_index)
         raster.transition_state = "FADING_IN"
      end
      return
   end

   if raster.transition_state == "FADING_IN" then
      raster.alpha = math.min(1.0, raster.alpha + (dt / raster.fade_duration))
      if raster.alpha == 1.0 then
         raster.transition_state = "VISIBLE"
      end
   end
end

--[ sprites ]--

local function create_sprite(index, glyph)
   return {
      glyph = glyph,
      color = color.rgb(
         110 + ((index * 31) % 145),
         120 + ((index * 47) % 120),
         150 + ((index * 59) % 90)
      ),
      lag = (index - 1) * 0.32,
      bob = (index - 1) * 0.21,
   }
end

local function create_glyphs(text)
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

--[ shared text helpers ]--

-- Iterates a run manually so it can cull horizontally off-screen glyphs.
local function draw_run_clipped(style, run, base_x, baseline_y, color_fn)
   for i = 1, #run.entries do
      local entry = run.entries[i]
      local packed = entry.packed
      local draw_x = base_x + entry.layout_x
      local draw_y = baseline_y + entry.layout_y

      if draw_x + packed.width >= -32 then
         if draw_x <= surface_width + 32 then
            scratch_glyph_color:set(color_fn(i, entry, draw_x, draw_y))
            style:draw_packed_glyph(packed, draw_x, draw_y, scratch_glyph_color, 1.0)
         elseif draw_x > surface_width + 32 then
            break
         end
      end
   end
end

local function draw_label(style, text, x, baseline_y, draw_color)
   local run = style:build_run(text)
   draw_run_clipped(style, run, x, baseline_y, function()
      return draw_color
   end)
end

--[ layout ]--

local function current_layout()
   return {
      title_y = math.floor(surface_height * 0.175 + 0.5),
      split_top = math.floor(surface_height * 0.214 + 0.5),
      split_height = math.floor(surface_height * 0.433 + 0.5),
      left = math.floor(surface_width * 0.069 + 0.5),
      scroll_y = math.floor(surface_height * 0.828 + 0.5),
   }
end

--[ drawing ]--

local function draw_raster(canvas, layout)
   local raster = state.raster
   local split_gap = 1
   local line_height = 2.0
   local total_width = surface_width - layout.left * 2
   local split_width = (total_width - split_gap * (raster.count - 1)) / raster.count
   local visible_lines = math.floor(layout.split_height / line_height)
   local visible_height = visible_lines * line_height
   local field_height = #raster.field
   local texture_height = raster.texture_height

   raster_modulate.a = math.floor(raster.alpha * 255 + 0.5)

   for i = 1, #raster.items do
      local split = raster.items[i]
      local base_x = layout.left + (i - 1) * (split_width + split_gap)
      local motion_range = math.floor(layout.split_height / line_height) * 2
      local split_phase = raster.phase * split.speed + split.offset
      local center_offset = split.base_offset + math.sin(split_phase) * (motion_range * 0.5)
      center_offset = math.floor(center_offset + 0.5)

      local source_y = ((center_offset % field_height) + field_height) % field_height
      local source_y_pixels = source_y * line_height

      if source_y_pixels + visible_height <= texture_height then
         canvas:draw_texture_region(
            raster.texture,
            0,
            source_y_pixels,
            1,
            visible_height,
            base_x,
            layout.split_top,
            split_width,
            visible_height,
            raster_modulate
         )
      else
         local first_height = texture_height - source_y_pixels
         local second_height = visible_height - first_height

         canvas:draw_texture_region(
            raster.texture,
            0,
            source_y_pixels,
            1,
            first_height,
            base_x,
            layout.split_top,
            split_width,
            first_height,
            raster_modulate
         )
         canvas:draw_texture_region(
            raster.texture,
            0,
            0,
            1,
            second_height,
            base_x,
            layout.split_top + first_height,
            split_width,
            second_height,
            raster_modulate
         )
      end
   end
end

local function draw_sprites(layout)
   local split_top = layout.split_top
   local split_bottom = split_top + layout.split_height

   for i = 1, #sprites do
      local sprite = sprites[i]
      local glyph = sprite.glyph
      local phase = state.sprite.phase - sprite.lag
      local orbit = 0.5 + 0.5 * math.sin(phase * 0.74)
      local alpha = math.floor(145 + 110 * (0.5 + 0.5 * math.sin(phase * 2.2 + 0.4)))
      local scale = 1.08 + 0.44 * (0.5 + 0.5 * math.sin(phase * 1.7 + 0.8))
      local glyph_width = glyph.width * scale
      local x = lerp(0, surface_width - glyph_width, orbit)
      local glyph_height = glyph.height * scale
      local y_phase = 0.5 + 0.5 * math.sin(phase * 1.45 + sprite.bob)
      local y = lerp(split_top, split_bottom - glyph_height, y_phase)
      local outline_scale = scale * 1.03

      if state.sprite.outline_enabled then
         for offset_index = 1, #sprite_outline_offsets do
            local offset = sprite_outline_offsets[offset_index]
            sprite_style:draw_packed_glyph(
               glyph,
               x + offset[1],
               y + offset[2],
               sprite_outline_color,
               outline_scale
            )
         end
      end

      sprite.color.a = alpha
      sprite_style:draw_packed_glyph(glyph, x, y, sprite.color, scale)
   end
end

local function calc_title_color(out, index)
   local phase = state.title.phase + index * 0.42
   local r = math.floor(125 + 120 * (0.5 + 0.5 * math.sin(phase)))
   local g = math.floor(130 + 110 * (0.5 + 0.5 * math.sin(phase + 2.1)))
   local b = math.floor(150 + 105 * (0.5 + 0.5 * math.sin(phase + 4.2)))
   out:set(r, g, b, 255)
   return out
end

local function draw_title(layout)
   local base_x = (surface_width - title_run.width) * 0.5
   local shadow_offset = 4

   draw_run_clipped(
      title_style,
      title_run,
      base_x + shadow_offset,
      layout.title_y + shadow_offset,
      function()
         return title_shadow_color
      end
   )

   draw_run_clipped(title_style, title_run, base_x, layout.title_y, function(index)
      return calc_title_color(scratch_glyph_color, index)
   end)
end

local function calc_scroller_color(out, index, x, y)
   local phase = state.raster.phase * 1.7 + index * 0.18 + x * 0.003
   local r = math.floor(150 + 105 * (0.5 + 0.5 * math.sin(phase)))
   local g = math.floor(110 + 130 * (0.5 + 0.5 * math.sin(phase + 1.9)))
   local b = math.floor(80 + 165 * (0.5 + 0.5 * math.sin(phase + 3.7)))
   local a = math.floor(220 + 35 * (0.5 + 0.5 * math.sin(phase + y * 0.01)))
   out:set(r, g, b, a)
   return out
end

local function draw_scroller_copy(layout, base_x)
   local scroller = state.scroller
   for i = 1, #scroller_run.entries do
      local entry = scroller_run.entries[i]
      local packed = entry.packed
      local x = base_x + entry.layout_x
      local y = layout.scroll_y + entry.layout_y
      local wave_phase = scroller.wave_phase
         + entry.layout_x * scroller.wave_frequency
         + i * 0.11
      y = y + math.sin(wave_phase) * scroller.wave_amplitude

      if x + packed.width >= -48 then
         if x <= surface_width + 48 then
            calc_scroller_color(scratch_glyph_color, i, x, y)
            scroller_style:draw_packed_glyph(packed, x, y, scratch_glyph_color, 1.0)
         elseif x > surface_width + 48 then
            break
         end
      end
   end
end

local function draw_scroller(layout)
   local scroller = state.scroller
   local first_x = surface_width - scroller.offset
   draw_scroller_copy(layout, first_x)

   local second_x = first_x + scroller_run.width + scroller.loop_gap
   if second_x < surface_width + 96 then
      draw_scroller_copy(layout, second_x)
   end
end

local function draw_profiler(canvas)
   local snapshot = state.frame_profiler:snapshot()
   local panel_x = 18
   local panel_y = 16
   local panel_w = 378
   local panel_h = 210

   canvas:rect(panel_x, panel_y, panel_w, panel_h, profiler_panel_color)

   local text_x = panel_x + 10
   local header = "      CUR / 1S / MAX"
   local line_1 = ("CPU %.2f / %.2f / %.2f"):format(
      snapshot.cpu_ms,
      snapshot.cpu_window_max_ms,
      snapshot.cpu_peak_ms
   )
   local line_2 = ("PRS %.2f / %.2f / %.2f"):format(
      snapshot.present_ms,
      snapshot.present_window_max_ms,
      snapshot.present_peak_ms
   )
   local line_3 = ("TOT %.2f / %.2f / %.2f"):format(
      snapshot.total_ms,
      snapshot.total_window_max_ms,
      snapshot.total_peak_ms
   )
   local line_4 = ("INT %.2f / %.2f / %.2f"):format(
      snapshot.interval_ms,
      snapshot.interval_window_max_ms,
      snapshot.interval_peak_ms
   )
   local line_5 = ("GAP %.2f / %.2f / %.2f"):format(
      snapshot.gap_ms,
      snapshot.gap_window_max_ms,
      snapshot.gap_peak_ms
   )
   local line_6 = ("OVR %d"):format(snapshot.overruns)
   local line_7 = state.vsync_supported
      and (state.vsync_enabled and "VSYNC ON [V]" or "VSYNC OFF [V]")
      or "VSYNC N/A"
   local line_8 = state.raster.enabled and "RASTER ON [1]" or "RASTER OFF [1]"
   local line_9 = state.sprite.enabled and "SPRITES ON [2]" or "SPRITES OFF [2]"
   local line_10 = state.sprite.outline_enabled and "OUTLINE ON [3]" or "OUTLINE OFF [3]"
   local line_11 = state.scroller.enabled and "SCROLLER ON [4]" or "SCROLLER OFF [4]"
   local line_12 = state.anim_enabled and "ANIM ON [5]" or "ANIM OFF [5]"
   local line_13 = state.fullscreen_enabled and "FULLSCREEN ON [F]" or "FULLSCREEN OFF [F]"
   local line_14 = "PROFILER ON [0]"

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
   draw_label(profiler_style, line_14, text_x, panel_y + 192, profiler_toggle_color)
end

local function draw_overlay(app, frame)
   surface_width = math.max(1, frame.surface.width or 1)
   surface_height = math.max(1, frame.surface.height or 1)
   local layout = current_layout()
   local canvas = app.ctx.draw

   state.frame_profiler:begin_cpu()

   if state.raster.enabled then
      draw_raster(canvas, layout)
   end
   if state.sprite.enabled then
      draw_sprites(layout)
   end
   draw_title(layout)
   if state.scroller.enabled then
      draw_scroller(layout)
   end
   if state.profiler_enabled then
      draw_profiler(canvas)
   end

   state.frame_profiler:end_cpu()
   state.frame_profiler:end_frame()
end

local function update(app, frame)
   surface_width = math.max(1, frame.surface.width or 1)
   surface_height = math.max(1, frame.surface.height or 1)

   state.frame_profiler:begin_frame()

   if state.anim_enabled then
      local dt = frame.dt
      update_raster(dt)

      state.sprite.phase = state.sprite.phase + dt * 2.35
      state.title.phase = state.title.phase + dt * 1.8

      local scroller = state.scroller
      local period = scroller_run.width + scroller.loop_gap
      scroller.offset = (scroller.offset + scroller.speed * dt) % period
      scroller.wave_phase = scroller.wave_phase + dt * scroller.wave_speed
   end
end

--[ toggles ]--

local function set_vsync(app, enabled)
   local graphics = app.ctx.graphics
   if type(graphics.set_vsync) == "function" then
      graphics:set_vsync(enabled)
   elseif type(graphics.set_swap_interval) == "function" then
      graphics:set_swap_interval(enabled and 1 or 0)
   else
      state.vsync_supported = false
      return
   end
   state.vsync_supported = true
   state.vsync_enabled = enabled
end

local function toggle_vsync(app)
   set_vsync(app, not state.vsync_enabled)
end

local function set_fullscreen(app, enabled)
   local window = app.ctx.window
   window:set_fullscreen(enabled)
   window:sync()
   state.fullscreen_enabled = enabled
end

local function toggle_fullscreen(app)
   set_fullscreen(app, not state.fullscreen_enabled)
end

local function on_key(app, key_info)
   if key_info.action ~= "down" or key_info["repeat"] then
      return
   end

   local key = key_info.key
   if key == "0" then
      state.profiler_enabled = not state.profiler_enabled
   elseif key == "v" or key == "V" then
      toggle_vsync(app)
   elseif key == "1" then
      state.raster.enabled = not state.raster.enabled
   elseif key == "2" then
      state.sprite.enabled = not state.sprite.enabled
   elseif key == "3" then
      state.sprite.outline_enabled = not state.sprite.outline_enabled
   elseif key == "4" then
      state.scroller.enabled = not state.scroller.enabled
   elseif key == "5" then
      state.anim_enabled = not state.anim_enabled
   elseif key == "f" or key == "F" then
      toggle_fullscreen(app)
   end
end

--[ startup ]--

local function start(app)
   face = font.load_face(face_path)

   title_style = app.ctx.font:create_style(face, {
      pixel_size = 74,
      page_width = 512,
      page_height = 256,
      padding = 2,
   })
   scroller_style = app.ctx.font:create_style(face, {
      pixel_size = 38,
      page_width = 1024,
      page_height = 512,
      padding = 2,
   })
   sprite_style = app.ctx.font:create_style(face, {
      pixel_size = 82,
      page_width = 256,
      page_height = 256,
      padding = 2,
   })
   profiler_style = app.ctx.font:create_style(face, {
      pixel_size = 14,
      page_width = 256,
      page_height = 128,
      padding = 1,
   })
   profiler_style:warm_text(
      "CPU PRS TOT INT GAP OVR CUR MAX VSYNC RASTER SPRITES OUTLINE SCROLLER ANIM FULLSCREEN PROFILER ON OFF [] 0123456789./-"
   )

   title_run = title_style:build_run("NEON PHANTOMS")
   scroller_run = scroller_style:build_run(scroll_text)

   local raster = state.raster
   raster.field = build_raster_field()
   local pixels, height = build_raster_pixels(raster.field, 2)
   raster.texture = app.ctx.draw:create_texture {
      width = 1,
      height = height,
      pixels = pixels,
      filter = "linear",
      wrap = "clamp",
   }
   raster.texture_height = height

   for i = 1, raster.count do
      raster.items[i] = { index = i, offset = 0.0, speed = 0.0, base_offset = 0.0 }
   end
   set_raster_preset(1, true)

   local sprite_text = "NEON PHANTOMS"
   sprite_glyphs = create_glyphs(sprite_text)
   for i = 1, #sprite_text do
      local character = sprite_text:sub(i, i)
      sprites[i] = create_sprite(i, sprite_glyphs[character])
   end

   state.frame_profiler = profiler.FrameProfiler { fps = 60 }
end

rig.run {
   title = "Rig " .. backend.label .. " Neon Phantoms",
   bundle = backend.bundle,
   bundle_options = backend.bundle_options,
   background = color.rgb(6, 8, 18),
   build = function(app)
      app:on_update(update)
      app:on_overlay(draw_overlay)
      app:on_key(on_key)
   end,
   start = start,
}
