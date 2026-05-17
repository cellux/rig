local sdl3 = require("sdl3")
local sched = require("sched")
local font = require("font")
local time = require("time")
local ffi = ffi

local window_width = 1280
local window_height = 720
local background_color = { 6, 8, 18, 255 }
local scroll_baseline_y = 596
local scroll_speed = 204.0
local scroll_wave_amplitude = 48.0
local scroll_wave_frequency = 0.001
local scroll_wave_speed = 2.8
local scroll_loop_gap = 240.0
local title_baseline_y = 126
local title_shadow_offset = 4
local raster_split_count = 8
local sprite_text = "NEON PHANTOMS"

local draw_rect = ffi.new("SDL_FRect[1]")
local src_rect = ffi.new("SDL_FRect[1]")
local dst_rect = ffi.new("SDL_FRect[1]")
local full_alpha = 255
local perf_frequency = tonumber(sdl3.GetPerformanceFrequency())
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

local scene = {
   font_path = nil,
   face = nil,
   title_face = nil,
   scroll_face = nil,
   sprite_face = nil,
   profiler_face = nil,
   title_atlas = nil,
   scroll_atlas = nil,
   sprite_atlas = nil,
   profiler_atlas = nil,
   raster_texture = nil,
   raster_texture_height = nil,
   title_textures = nil,
   scroll_textures = nil,
   sprite_textures = nil,
   profiler_textures = nil,
   title_run = nil,
   scroll_run = nil,
   sprite_glyphs = nil,
   sprites = {},
   raster_splits = {},
   raster_field = {},
   raster_alpha = 1.0,
   raster_preset_index = 1,
   raster_transition_timer = 0.0,
   scroll_offset = 0.0,
   scroll_wave_phase = 0.0,
   raster_phase = 0.0,
   sprite_snake_phase = 0.0,
   title_phase = 0.0,
   profiler_cpu_ms = 0.0,
   profiler_cpu_max_ms = 0.0,
   profiler_interval_ms = 0.0,
   profiler_interval_max_ms = 0.0,
   profiler_overruns = 0,
   profiler_last_frame_counter = nil,
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

   error("examples/scroller.lua could not find a system TTF font; install DejaVu Sans or edit the font candidates", 0)
end

local function clamp(value, low, high)
   if value < low then
      return low
   end
   if value > high then
      return high
   end
   return value
end

local function lerp(a, b, t)
   return a + (b - a) * t
end

local function set_draw_color(renderer, r, g, b, a)
   if not sdl3.SetRenderDrawColor(renderer, r, g, b, a) then
      error("failed to set renderer color: " .. ffi.string(sdl3.GetError()), 0)
   end
end

local function fill_rect(renderer, x, y, w, h)
   draw_rect[0].x = x
   draw_rect[0].y = y
   draw_rect[0].w = w
   draw_rect[0].h = h
   if not sdl3.RenderFillRect(renderer, draw_rect) then
      error("failed to draw rectangle: " .. ffi.string(sdl3.GetError()), 0)
   end
end

local function upload_gray_page_texture(renderer, page)
   local pixel_count = page.width * page.height
   local rgba = ffi.new("uint8_t[?]", pixel_count * 4)

   for i = 0, pixel_count - 1 do
      local alpha = page.buffer[i]
      local base = i * 4
      rgba[base] = 255
      rgba[base + 1] = 255
      rgba[base + 2] = 255
      rgba[base + 3] = alpha
   end

   local texture = sdl3.CreateTexture(
      renderer,
      sdl3.PIXELFORMAT_RGBA32,
      sdl3.TEXTUREACCESS_STATIC,
      page.width,
      page.height
   )
   if texture == nil or texture == ffi.NULL then
      error("failed to create SDL texture: " .. ffi.string(sdl3.GetError()), 0)
   end

   if not sdl3.UpdateTexture(texture, nil, rgba, page.width * 4) then
      sdl3.DestroyTexture(texture)
      error("failed to upload SDL texture: " .. ffi.string(sdl3.GetError()), 0)
   end

   if not sdl3.SetTextureBlendMode(texture, sdl3.BLENDMODE_BLEND) then
      sdl3.DestroyTexture(texture)
      error("failed to set SDL texture blend mode: " .. ffi.string(sdl3.GetError()), 0)
   end

   return texture
end

local function upload_atlas_textures(renderer, atlas)
   local textures = {}
   for i = 1, #atlas.pages do
      local page = atlas.pages[i]
      textures[page.index] = upload_gray_page_texture(renderer, page)
   end
   return textures
end

local function upload_raster_texture(renderer, field, line_height)
   local texture_height = #field * line_height
   local rgba = ffi.new("uint8_t[?]", texture_height * 4)

   for i = 1, #field do
      local color = field[i]
      for line = 0, line_height - 1 do
         local pixel_index = ((i - 1) * line_height + line) * 4
         rgba[pixel_index] = color[1]
         rgba[pixel_index + 1] = color[2]
         rgba[pixel_index + 2] = color[3]
         rgba[pixel_index + 3] = color[4]
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
      error("failed to create raster texture: " .. ffi.string(sdl3.GetError()), 0)
   end

   if not sdl3.UpdateTexture(texture, nil, rgba, 4) then
      sdl3.DestroyTexture(texture)
      error("failed to upload raster texture: " .. ffi.string(sdl3.GetError()), 0)
   end

   if not sdl3.SetTextureBlendMode(texture, sdl3.BLENDMODE_BLEND) then
      sdl3.DestroyTexture(texture)
      error("failed to set raster texture blend mode: " .. ffi.string(sdl3.GetError()), 0)
   end

   return texture, texture_height
end

local function destroy_textures(textures)
   if textures == nil then
      return
   end
   for i = 1, #textures do
      local texture = textures[i]
      if texture ~= nil and texture ~= ffi.NULL then
         sdl3.DestroyTexture(texture)
      end
   end
end

local function build_text_run(sized_face, atlas, text, options)
   local shaped = font.shape(sized_face, text, options)
   local entries = {}
   local pen_x = 0.0
   local pen_y = 0.0

   for i = 1, #shaped.glyphs do
      local glyph = shaped.glyphs[i]
      local packed = atlas:get_glyph(glyph.glyph_id)
      entries[#entries + 1] = {
         packed = packed,
         layout_x = pen_x + glyph.x_offset + packed.left,
         layout_y = pen_y - glyph.y_offset - packed.top,
         cluster = glyph.cluster,
      }
      pen_x = pen_x + glyph.x_advance
      pen_y = pen_y + glyph.y_advance
   end

   return {
      text = text,
      width = shaped.x_advance,
      glyph_count = shaped.glyph_count,
      entries = entries,
   }
end

local function warm_atlas_text(sized_face, atlas, text)
   local shaped = font.shape(sized_face, text)
   for i = 1, #shaped.glyphs do
      atlas:get_glyph(shaped.glyphs[i].glyph_id)
   end
end

local function draw_packed_glyph(renderer, textures, packed, x, y, scale, r, g, b, a)
   if packed.width <= 0 or packed.height <= 0 then
      return
   end

   local texture = textures[packed.page_index]
   if texture == nil or texture == ffi.NULL then
      return
   end

   if not sdl3.SetTextureColorMod(texture, r, g, b) then
      error("failed to set texture color modulation: " .. ffi.string(sdl3.GetError()), 0)
   end
   if not sdl3.SetTextureAlphaMod(texture, a) then
      error("failed to set texture alpha modulation: " .. ffi.string(sdl3.GetError()), 0)
   end

   src_rect[0].x = packed.x
   src_rect[0].y = packed.y
   src_rect[0].w = packed.width
   src_rect[0].h = packed.height

   dst_rect[0].x = x
   dst_rect[0].y = y
   dst_rect[0].w = packed.width * scale
   dst_rect[0].h = packed.height * scale

   if not sdl3.RenderTexture(renderer, texture, src_rect, dst_rect) then
      error("failed to render SDL texture: " .. ffi.string(sdl3.GetError()), 0)
   end
end

local function draw_text_run(renderer, textures, run, base_x, baseline_y, color_fn)
   for i = 1, #run.entries do
      local entry = run.entries[i]
      local packed = entry.packed
      local draw_x = base_x + entry.layout_x
      local draw_y = baseline_y + entry.layout_y

      if draw_x + packed.width >= -32 then
         if draw_x <= window_width + 32 then
            local r, g, b, a = color_fn(i, entry, draw_x, draw_y)
            draw_packed_glyph(
               renderer,
               textures,
               packed,
               draw_x,
               draw_y,
               1.0,
               r,
               g,
               b,
               a
            )
         elseif draw_x > window_width + 32 then
            break
         end
      end
   end
end

local function draw_label(renderer, sized_face, atlas, textures, text, x, baseline_y, r, g, b, a)
   local run = build_text_run(sized_face, atlas, text)
   draw_text_run(renderer, textures, run, x, baseline_y, function()
      return r, g, b, a
   end)
end

local function apply_preset(index)
   local offset_step = raster_split_count > 0 and (#scene.raster_field / raster_split_count) or 0
   for i = 1, raster_split_count do
      local split = scene.raster_splits[i]
      if index == 1 then -- Random (Original)
         split.offset = math.random() * math.pi * 2.0
         split.speed = 0.5 + math.random() * 0.4
         split.base_offset = (i - 1) * offset_step
      elseif index == 2 then -- Smooth Sine
         split.offset = (i - 1) * (math.pi * 2.0 / raster_split_count)
         split.speed = 0.7
         split.base_offset = (i - 1) * offset_step * 0.5
      elseif index == 3 then -- Linear Slant
         split.offset = (i - 1) * 0.4
         split.speed = 0.8
         split.base_offset = (i - 1) * offset_step * 0.2
      elseif index == 4 then -- Grouped Pairs
         local group = math.floor((i - 1) / 2)
         split.offset = group * 1.5
         split.speed = 0.6 + (group % 2) * 0.3
         split.base_offset = group * offset_step
      end
   end
end

local function draw_rasterbars(renderer)
   local split_top = 154
   local split_height = 312
   local split_gap = 1
   local line_height = 2.0
   local left = 88
   local total_width = window_width - left * 2
   local split_width = (total_width - split_gap * (raster_split_count - 1)) / raster_split_count
   local field_height = #scene.raster_field
   local visible_lines = math.floor(split_height / line_height)
   local visible_height = visible_lines * line_height
   local texture_height = scene.raster_texture_height
   local motion_range = visible_lines * 2
   local half_motion_range = motion_range * 0.5

   if not sdl3.SetTextureAlphaMod(scene.raster_texture, math.floor(scene.raster_alpha * 255 + 0.5)) then
      error("failed to set raster texture alpha modulation: " .. ffi.string(sdl3.GetError()), 0)
   end

   for split_index = 1, #scene.raster_splits do
      local split = scene.raster_splits[split_index]
      local base_x = left + (split_index - 1) * (split_width + split_gap)
      local split_phase = scene.raster_phase * split.speed + split.offset
      local center_offset = split.base_offset + math.sin(split_phase) * half_motion_range
      center_offset = math.floor(center_offset + 0.5)
      local source_y = ((center_offset % field_height) + field_height) % field_height
      local source_y_pixels = source_y * line_height

      if source_y_pixels + visible_height <= texture_height then
         src_rect[0].x = 0
         src_rect[0].y = source_y_pixels
         src_rect[0].w = 1
         src_rect[0].h = visible_height
         dst_rect[0].x = base_x
         dst_rect[0].y = split_top
         dst_rect[0].w = split_width
         dst_rect[0].h = visible_height
         if not sdl3.RenderTexture(renderer, scene.raster_texture, src_rect, dst_rect) then
            error("failed to render raster texture: " .. ffi.string(sdl3.GetError()), 0)
         end
      else
         local first_height = texture_height - source_y_pixels
         local second_height = visible_height - first_height

         src_rect[0].x = 0
         src_rect[0].y = source_y_pixels
         src_rect[0].w = 1
         src_rect[0].h = first_height
         dst_rect[0].x = base_x
         dst_rect[0].y = split_top
         dst_rect[0].w = split_width
         dst_rect[0].h = first_height
         if not sdl3.RenderTexture(renderer, scene.raster_texture, src_rect, dst_rect) then
            error("failed to render raster texture head: " .. ffi.string(sdl3.GetError()), 0)
         end

         src_rect[0].x = 0
         src_rect[0].y = 0
         src_rect[0].w = 1
         src_rect[0].h = second_height
         dst_rect[0].x = base_x
         dst_rect[0].y = split_top + first_height
         dst_rect[0].w = split_width
         dst_rect[0].h = second_height
         if not sdl3.RenderTexture(renderer, scene.raster_texture, src_rect, dst_rect) then
            error("failed to render raster texture tail: " .. ffi.string(sdl3.GetError()), 0)
         end
      end
   end
end

local function build_raster_field()
   local function add_color_line(field, r, g, b, a, repeat_count)
      repeat_count = repeat_count or 1
      for _ = 1, repeat_count do
         field[#field + 1] = { r, g, b, a }
      end
   end

   local function add_spacer(field, line_count)
      for _ = 1, line_count do
         field[#field + 1] = { 0, 0, 0, 0 }
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
         local r = math.floor((tint[1] * intensity * (1.0 - center_mix) + hr * center_mix) + 0.5)
         local g = math.floor((tint[2] * intensity * (1.0 - center_mix) + hg * center_mix) + 0.5)
         local b = math.floor((tint[3] * intensity * (1.0 - center_mix) + hb * center_mix) + 0.5)
         -- Use square root for alpha so it stays opaque much longer at the edges
         local a = math.floor(255 * math.sqrt(intensity) + 0.5)
         add_color_line(field, r, g, b, a, 1)
      end
   end

   local field = {}
   local profile = build_bar_intensity_profile()
   local tints = {
      { 255, 0, 0 },    -- Red
      { 255, 127, 0 },  -- Orange
      { 255, 255, 0 },  -- Yellow
      { 0, 255, 0 },    -- Green
      { 0, 255, 255 },  -- Cyan
      { 0, 100, 255 },  -- Blue
      { 139, 0, 255 },  -- Violet
      { 255, 0, 127 },  -- Rose
   }

   for i = 1, #tints do
      append_bar(field, profile, tints[i])
   end

   return field
end

local function title_color(index)
   local phase = scene.title_phase + index * 0.42
   local r = math.floor(125 + 120 * (0.5 + 0.5 * math.sin(phase)))
   local g = math.floor(130 + 110 * (0.5 + 0.5 * math.sin(phase + 2.1)))
   local b = math.floor(150 + 105 * (0.5 + 0.5 * math.sin(phase + 4.2)))
   return r, g, b, full_alpha
end

local function draw_title(renderer)
   local run = scene.title_run
   local base_x = (window_width - run.width) * 0.5

   draw_text_run(renderer, scene.title_textures, run, base_x + title_shadow_offset, title_baseline_y + title_shadow_offset, function()
      return 0, 0, 0, 220
   end)

   draw_text_run(renderer, scene.title_textures, run, base_x, title_baseline_y, function(index)
      return title_color(index)
   end)
end

local function scroll_color(index, x, y)
   local phase = scene.raster_phase * 1.7 + index * 0.18 + x * 0.003
   local r = math.floor(150 + 105 * (0.5 + 0.5 * math.sin(phase)))
   local g = math.floor(110 + 130 * (0.5 + 0.5 * math.sin(phase + 1.9)))
   local b = math.floor(80 + 165 * (0.5 + 0.5 * math.sin(phase + 3.7)))
   local a = math.floor(220 + 35 * (0.5 + 0.5 * math.sin(phase + y * 0.01)))
   return r, g, b, a
end

local function draw_scroller_copy(renderer, base_x)
   local run = scene.scroll_run
   for i = 1, #run.entries do
      local entry = run.entries[i]
      local packed = entry.packed
      local x = base_x + entry.layout_x
      local y = scroll_baseline_y + entry.layout_y
      local wave_phase = scene.scroll_wave_phase
         + entry.layout_x * scroll_wave_frequency
         + i * 0.11
      y = y + math.sin(wave_phase) * scroll_wave_amplitude

      if x + packed.width >= -48 then
         if x <= window_width + 48 then
            local r, g, b, a = scroll_color(i, x, y)
            draw_packed_glyph(renderer, scene.scroll_textures, packed, x, y, 1.0, r, g, b, a)
         elseif x > window_width + 48 then
            break
         end
      end
   end
end

local function draw_scroller(renderer)
   local run = scene.scroll_run
   local first_x = window_width - scene.scroll_offset
   draw_scroller_copy(renderer, first_x)

   local second_x = first_x + run.width + scroll_loop_gap
   if second_x < window_width + 96 then
      draw_scroller_copy(renderer, second_x)
   end
end

local function draw_profiler(renderer)
   local panel_x = 18
   local panel_y = 16
   local panel_w = 210
   local panel_h = 70

   set_draw_color(renderer, 0, 0, 0, 150)
   fill_rect(renderer, panel_x, panel_y, panel_w, panel_h)

   local text_x = panel_x + 10
   local line_1 = ("CPU %.2f"):format(scene.profiler_cpu_ms)
   local line_2 = ("INT %.2f"):format(scene.profiler_interval_ms)
   local line_3 = ("OVR %d"):format(scene.profiler_overruns)
   local line_4 = ("MAX %.2f %.2f"):format(scene.profiler_cpu_max_ms, scene.profiler_interval_max_ms)

   draw_label(renderer, scene.profiler_face, scene.profiler_atlas, scene.profiler_textures, line_1, text_x, panel_y + 18, 255, 248, 224, 255)
   draw_label(renderer, scene.profiler_face, scene.profiler_atlas, scene.profiler_textures, line_2, text_x, panel_y + 34, 255, 248, 224, 255)
   draw_label(renderer, scene.profiler_face, scene.profiler_atlas, scene.profiler_textures, line_3, text_x, panel_y + 50, 255, 214, 160, 255)
   draw_label(renderer, scene.profiler_face, scene.profiler_atlas, scene.profiler_textures, line_4, text_x, panel_y + 66, 255, 184, 150, 255)
end

local function make_sprite(i, character)
   return {
      glyph = scene.sprite_glyphs[character],
      character = character,
      color = {
         110 + ((i * 31) % 145),
         120 + ((i * 47) % 120),
         150 + ((i * 59) % 90),
      },
      lag = (i - 1) * 0.32,
      bob = (i - 1) * 0.21,
   }
end

local function draw_sprites(renderer)
   local split_top = 154
   local split_height = 312
   local split_bottom = split_top + split_height

   for i = 1, #scene.sprites do
      local sprite = scene.sprites[i]
      local phase = scene.sprite_snake_phase - sprite.lag
      local orbit = 0.5 + 0.5 * math.sin(phase * 0.74)
      local alpha = math.floor(145 + 110 * (0.5 + 0.5 * math.sin(phase * 2.2 + 0.4)))
      local scale = 1.08 + 0.44 * (0.5 + 0.5 * math.sin(phase * 1.7 + 0.8))
      local glyph_width = sprite.glyph.width * scale
      local min_x = 0
      local max_x = window_width - glyph_width
      local x = lerp(min_x, max_x, orbit)
      local glyph_height = sprite.glyph.height * scale
      local min_y = split_top
      local max_y = split_bottom - glyph_height
      local y_phase = 0.5 + 0.5 * math.sin(phase * 1.45 + sprite.bob)
      local y = lerp(min_y, max_y, y_phase)
      local outline_scale = scale * 1.03

      for j = 1, #sprite_outline_offsets do
         local offset = sprite_outline_offsets[j]
         draw_packed_glyph(
            renderer,
            scene.sprite_textures,
            sprite.glyph,
            x + offset[1],
            y + offset[2],
            outline_scale,
            0,
            0,
            0,
            128
         )
      end

      draw_packed_glyph(
         renderer,
         scene.sprite_textures,
         sprite.glyph,
         x,
         y,
         scale,
         sprite.color[1],
         sprite.color[2],
         sprite.color[3],
         alpha
      )
   end
end

local function animate_scroller()
   local last = time.monotonic()
   local period = scene.scroll_run.width + scroll_loop_gap
   local transition_duration = 0.5
   local visible_duration = 4.0
   local state = "VISIBLE" -- VISIBLE, FADING_OUT, FADING_IN

   while true do
      local now = time.monotonic()
      local dt = now - last
      last = now

      scene.raster_transition_timer = scene.raster_transition_timer + dt

      if state == "VISIBLE" then
         scene.raster_alpha = 1.0
         if scene.raster_transition_timer >= visible_duration then
            state = "FADING_OUT"
            scene.raster_transition_timer = 0.0
         end
      elseif state == "FADING_OUT" then
         scene.raster_alpha = 1.0 - (scene.raster_transition_timer / transition_duration)
         if scene.raster_transition_timer >= transition_duration then
            scene.raster_alpha = 0.0
            state = "FADING_IN"
            scene.raster_transition_timer = 0.0
            scene.raster_preset_index = (scene.raster_preset_index % 4) + 1
            apply_preset(scene.raster_preset_index)
         end
      elseif state == "FADING_IN" then
         scene.raster_alpha = scene.raster_transition_timer / transition_duration
         if scene.raster_transition_timer >= transition_duration then
            scene.raster_alpha = 1.0
            state = "VISIBLE"
            scene.raster_transition_timer = 0.0
         end
      end

      scene.scroll_offset = (scene.scroll_offset + scroll_speed * dt) % period
      scene.scroll_wave_phase = scene.scroll_wave_phase + dt * scroll_wave_speed
      scene.raster_phase = scene.raster_phase + dt * 1.6
      scene.sprite_snake_phase = scene.sprite_snake_phase + dt * 2.35
      scene.title_phase = scene.title_phase + dt * 1.8
      sched.yield()
   end
end

local function create_sprite_glyphs(sprite_face, sprite_atlas, text)
   local glyphs = {}
   for i = 1, #text do
      local character = text:sub(i, i)
      if glyphs[character] == nil then
         local shaped = font.shape(sprite_face, character)
         glyphs[character] = sprite_atlas:get_glyph(shaped.glyphs[1].glyph_id)
      end
   end
   return glyphs
end

local function initialize_scene()
   local renderer = sdl3.get_renderer()
   scene.font_path = find_font_path()
   scene.face = font.load_face(scene.font_path)
   scene.title_face = scene.face:create_sized_face(74)
   scene.scroll_face = scene.face:create_sized_face(38)
   scene.sprite_face = scene.face:create_sized_face(82)
   scene.profiler_face = scene.face:create_sized_face(14)

   scene.title_atlas = scene.title_face:create_atlas {
      page_width = 512,
      page_height = 256,
      padding = 2,
   }
   scene.scroll_atlas = scene.scroll_face:create_atlas {
      page_width = 1024,
      page_height = 512,
      padding = 2,
   }
   scene.sprite_atlas = scene.sprite_face:create_atlas {
      page_width = 256,
      page_height = 256,
      padding = 2,
   }
   scene.profiler_atlas = scene.profiler_face:create_atlas {
      page_width = 256,
      page_height = 128,
      padding = 1,
   }

   scene.title_run = build_text_run(scene.title_face, scene.title_atlas, "NEON PHANTOMS")
   scene.scroll_run = build_text_run(scene.scroll_face, scene.scroll_atlas, scroll_text)
   scene.sprite_glyphs = create_sprite_glyphs(
      scene.sprite_face,
      scene.sprite_atlas,
      sprite_text
   )
   warm_atlas_text(scene.profiler_face, scene.profiler_atlas, "CPU INT OVR MAX 0123456789.-")

   scene.title_textures = upload_atlas_textures(renderer, scene.title_atlas)
   scene.scroll_textures = upload_atlas_textures(renderer, scene.scroll_atlas)
   scene.sprite_textures = upload_atlas_textures(renderer, scene.sprite_atlas)
   scene.profiler_textures = upload_atlas_textures(renderer, scene.profiler_atlas)

   scene.raster_field = build_raster_field()
   scene.raster_texture, scene.raster_texture_height =
      upload_raster_texture(renderer, scene.raster_field, 2)
   scene.raster_splits = {}
   for i = 1, raster_split_count do
      scene.raster_splits[i] = {}
   end
   apply_preset(1)

   scene.sprites = {}
   for i = 1, #sprite_text do
      local sprite = make_sprite(i, sprite_text:sub(i, i))
      scene.sprites[i] = sprite
   end

   sched.spawn(animate_scroller)
end

local function release_scene()
   destroy_textures(scene.title_textures)
   destroy_textures(scene.scroll_textures)
   destroy_textures(scene.sprite_textures)
    destroy_textures(scene.profiler_textures)
   scene.title_textures = nil
   scene.scroll_textures = nil
   scene.sprite_textures = nil
   scene.profiler_textures = nil
   if scene.raster_texture ~= nil and scene.raster_texture ~= ffi.NULL then
      sdl3.DestroyTexture(scene.raster_texture)
      scene.raster_texture = nil
   end
   scene.raster_texture_height = nil

   if scene.title_atlas ~= nil then
      scene.title_atlas:release()
      scene.title_atlas = nil
   end
   if scene.scroll_atlas ~= nil then
      scene.scroll_atlas:release()
      scene.scroll_atlas = nil
   end
   if scene.sprite_atlas ~= nil then
      scene.sprite_atlas:release()
      scene.sprite_atlas = nil
   end
   if scene.profiler_atlas ~= nil then
      scene.profiler_atlas:release()
      scene.profiler_atlas = nil
   end

   if scene.title_face ~= nil then
      scene.title_face:release()
      scene.title_face = nil
   end
   if scene.scroll_face ~= nil then
      scene.scroll_face:release()
      scene.scroll_face = nil
   end
   if scene.sprite_face ~= nil then
      scene.sprite_face:release()
      scene.sprite_face = nil
   end
   if scene.profiler_face ~= nil then
      scene.profiler_face:release()
      scene.profiler_face = nil
   end
   if scene.face ~= nil then
      scene.face:release()
      scene.face = nil
   end
end

local function render_frame()
   local frame_start = tonumber(sdl3.GetPerformanceCounter())
   local last_frame_counter = scene.profiler_last_frame_counter
   if last_frame_counter ~= nil then
      scene.profiler_interval_ms = (frame_start - last_frame_counter) * 1000.0 / perf_frequency
      if scene.profiler_interval_ms > scene.profiler_interval_max_ms then
         scene.profiler_interval_max_ms = scene.profiler_interval_ms
      end
   end
   scene.profiler_last_frame_counter = frame_start

   local renderer = sdl3.get_renderer()
   set_draw_color(
      renderer,
      background_color[1],
      background_color[2],
      background_color[3],
      background_color[4]
   )
   if not sdl3.RenderClear(renderer) then
      error("failed to clear SDL renderer: " .. ffi.string(sdl3.GetError()), 0)
   end

   draw_rasterbars(renderer)
   draw_sprites(renderer)
   --draw_title(renderer)
   draw_scroller(renderer)
   draw_profiler(renderer)

   local frame_end = tonumber(sdl3.GetPerformanceCounter())
   scene.profiler_cpu_ms = (frame_end - frame_start) * 1000.0 / perf_frequency
   if scene.profiler_cpu_ms > scene.profiler_cpu_max_ms then
      scene.profiler_cpu_max_ms = scene.profiler_cpu_ms
   end
   if scene.profiler_cpu_ms > 16.67 then
      scene.profiler_overruns = scene.profiler_overruns + 1
   end
end

rig.run {
   mode = "sdl3",
   sdl3 = {
      window_props = {
         [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "Neon Phantoms - Midnight Mirror Cracktro",
         [sdl3.PROP_WINDOW_CREATE_WIDTH_NUMBER] = window_width,
         [sdl3.PROP_WINDOW_CREATE_HEIGHT_NUMBER] = window_height,
      },
      on_render = render_frame,
   },
   hooks = {
      after_setup = initialize_scene,
      before_shutdown = release_scene,
   },
}
