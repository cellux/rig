local sdl3 = require("sdl3")
local scenegraph = require("scenegraph")
local animator = require("animator")
local font = require("font")
local mathx = require("mathx")
local color = require("color")
local profiler = require("profiler")
local ffi = require("ffi")

local window_width
local window_height
local font_path
local face
local profiler_style
local frame_profiler
local profiler_enabled = true
local vsync_enabled = true
local fullscreen_enabled = false

local draw_rect = ffi.new("SDL_FRect[1]")
local src_rect = ffi.new("SDL_FRect[1]")
local dst_rect = ffi.new("SDL_FRect[1]")
local full_alpha = 255
local tau = math.pi * 2.0
local lerp = mathx.lerp
local upload_raster_texture
local build_raster_field
local set_draw_color
local draw_profiler
local toggle_vsync
local toggle_fullscreen
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

local Object = scenegraph.Object
local Sprite = rig.Class()
local RasterSplit = rig.Class()
local RasterSplits = rig.Class(Object)
local Title = rig.Class(Object)
local Scroller = rig.Class(Object)
local SpriteSnake = rig.Class(Object)
local ProfilerOverlay = rig.Class(Object)
local Scene = rig.Class(Object)
local App = rig.Class(animator.App)

local find_font_path
local scroll_text

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
      self.offset = math.random() * tau
      self.speed = 0.5 + math.random() * 0.4
      self.base_offset = (split_index - 1) * offset_step
   elseif preset_index == 2 then -- Smooth Sine
      self.offset = (split_index - 1) * (tau / split_count)
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

function RasterSplit:draw(renderer, raster_texture, raster_phase, layout, split_width, split_gap, visible_height, line_height, texture_height, field_height)
   local base_x = layout.left + (self.index - 1) * (split_width + split_gap)
   local motion_range = math.floor(layout.split_height / line_height) * 2
   local split_phase = raster_phase * self.speed + self.offset
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
      if not sdl3.RenderTexture(renderer, raster_texture, src_rect, dst_rect) then
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
   if not sdl3.RenderTexture(renderer, raster_texture, src_rect, dst_rect) then
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
   if not sdl3.RenderTexture(renderer, raster_texture, src_rect, dst_rect) then
      rig.raise("failed to render raster texture tail: " .. ffi.string(sdl3.GetError()))
   end
end

function RasterSplits:init(renderer, count)
   self:super().init(self)
   self.count = count
   self.items = {}
   self.field = build_raster_field()
   self.texture, self.texture_height = upload_raster_texture(renderer, self.field, 2)
   self.texture = self:replace_owned("texture", self.texture, function(_, texture)
      if texture ~= nil and texture ~= ffi.NULL then
         sdl3.DestroyTexture(texture)
      end
   end)
   self.alpha = 1.0
   self.preset_index = 1
   self.target_preset_index = 1
   self.transition_state = "VISIBLE"
   self.phase = 0.0
   self.phase_speed = 1.6
   self.preset_hold_duration = 4.0
   self.fade_duration = 0.5

   for i = 1, count do
      self.items[i] = RasterSplit(i)
   end

   self:set_preset(1, true)
end

function RasterSplits:release()
   self.running = false
   self.items = {}
   self.field = nil
   self.texture_height = nil
   self.texture = nil
end

function RasterSplits:apply_preset(preset_index)
   self.preset_index = preset_index
   local offset_step = self.count > 0 and (#self.field / self.count) or 0
   for i = 1, #self.items do
      self.items[i]:apply_preset(preset_index, self.count, offset_step)
   end
end

function RasterSplits:set_preset(preset_index, snap)
   self.target_preset_index = preset_index
   if snap then
      self:apply_preset(preset_index)
      self.alpha = 1.0
      self.transition_state = "VISIBLE"
   end
end

function RasterSplits:draw(context)
   local renderer = context.renderer
   local layout = context.layout
   local split_gap = 1
   local line_height = 2.0
   local total_width = window_width - layout.left * 2
   local split_width = (total_width - split_gap * (self.count - 1)) / self.count
   local visible_lines = math.floor(layout.split_height / line_height)
   local visible_height = visible_lines * line_height

   if not sdl3.SetTextureAlphaMod(self.texture, math.floor(self.alpha * 255 + 0.5)) then
      rig.raise("failed to set raster texture alpha modulation: " .. ffi.string(sdl3.GetError()))
   end

   for i = 1, #self.items do
      self.items[i]:draw(
         renderer,
         self.texture,
         self.phase,
         layout,
         split_width,
         split_gap,
         visible_height,
         line_height,
         self.texture_height,
         #self.field
      )
   end
end

function RasterSplits:update(dt)
   self.phase = self.phase + dt * self.phase_speed

   if self.transition_state == "VISIBLE" then
      if self.target_preset_index ~= self.preset_index then
         self.transition_state = "FADING_OUT"
      end
      return
   end

   if self.transition_state == "FADING_OUT" then
      self.alpha = math.max(0.0, self.alpha - (dt / self.fade_duration))
      if self.alpha == 0.0 then
         self:apply_preset(self.target_preset_index)
         self.transition_state = "FADING_IN"
      end
      return
   end

   if self.transition_state == "FADING_IN" then
      self.alpha = math.min(1.0, self.alpha + (dt / self.fade_duration))
      if self.alpha == 1.0 then
         self.transition_state = "VISIBLE"
      end
   end
end

function RasterSplits:drive()
   while self.running do
      self.animator:sleep(self.preset_hold_duration)
      if not self.running then
         break
      end

      self.target_preset_index = (self.target_preset_index % 4) + 1
   end
end

function Title:init(face, text)
   self:super().init(self)
   self.enabled = false
   self.shadow_offset = 4
   self.phase = 0.0
   self.style = self:replace_owned("style", font.create_style(face, {
      pixel_size = 74,
      page_width = 512,
      page_height = 256,
      padding = 2,
   }), function(_, style)
      style:release()
   end)
   self.run = self.style:build_run(text)
   self.draw_color = color.WHITE:copy()
end

function Title:release()
   self.run = nil
   self.draw_color = nil
   self.style = nil
end

function Title:calc_color(out, index)
   local phase = self.phase + index * 0.42
   local r = math.floor(125 + 120 * (0.5 + 0.5 * math.sin(phase)))
   local g = math.floor(130 + 110 * (0.5 + 0.5 * math.sin(phase + 2.1)))
   local b = math.floor(150 + 105 * (0.5 + 0.5 * math.sin(phase + 4.2)))
   out:set(r, g, b, full_alpha)
   return out
end

function Title:draw(context)
   local layout = context.layout
   local title_baseline_y = layout.title_y
   local base_x = (window_width - self.run.width) * 0.5

   draw_text_run(
      self.style,
      self.run,
      base_x + self.shadow_offset,
      title_baseline_y + self.shadow_offset,
      function()
         return title_shadow_color
      end
   )

   draw_text_run(self.style, self.run, base_x, title_baseline_y, function(index)
      return self:calc_color(self.draw_color, index)
   end)
end

function Title:update(dt)
   self.phase = self.phase + dt * 1.8
end

function Scroller:init(face, text)
   self:super().init(self)
   self.speed = 204.0
   self.wave_amplitude = 48.0
   self.wave_frequency = 0.001
   self.wave_speed = 2.8
   self.loop_gap = 240.0
   self.offset = 0.0
   self.wave_phase = 0.0
   self.style = self:replace_owned("style", font.create_style(face, {
      pixel_size = 38,
      page_width = 1024,
      page_height = 512,
      padding = 2,
   }), function(_, style)
      style:release()
   end)
   self.run = self.style:build_run(text)
   self.glyph_color = color.WHITE:copy()
end

function Scroller:release()
   self.run = nil
   self.glyph_color = nil
   self.style = nil
end

function Scroller:calc_color(out, index, x, y)
   local phase = self.parent.raster_splits.phase * 1.7 + index * 0.18 + x * 0.003
   local r = math.floor(150 + 105 * (0.5 + 0.5 * math.sin(phase)))
   local g = math.floor(110 + 130 * (0.5 + 0.5 * math.sin(phase + 1.9)))
   local b = math.floor(80 + 165 * (0.5 + 0.5 * math.sin(phase + 3.7)))
   local a = math.floor(220 + 35 * (0.5 + 0.5 * math.sin(phase + y * 0.01)))
   out:set(r, g, b, a)
   return out
end

function Scroller:draw_copy(layout, base_x)
   local scroll_baseline_y = layout.scroll_y
   for i = 1, #self.run.entries do
      local entry = self.run.entries[i]
      local packed = entry.packed
      local x = base_x + entry.layout_x
      local y = scroll_baseline_y + entry.layout_y
      local wave_phase = self.wave_phase
         + entry.layout_x * self.wave_frequency
         + i * 0.11
      y = y + math.sin(wave_phase) * self.wave_amplitude

      if x + packed.width >= -48 then
         if x <= window_width + 48 then
            self:calc_color(self.glyph_color, i, x, y)
            self.style:draw_packed_glyph(packed, x, y, self.glyph_color, 1.0)
         elseif x > window_width + 48 then
            break
         end
      end
   end
end

function Scroller:draw(context)
   local layout = context.layout
   local first_x = window_width - self.offset
   self:draw_copy(layout, first_x)

   local second_x = first_x + self.run.width + self.loop_gap
   if second_x < window_width + 96 then
      self:draw_copy(layout, second_x)
   end
end

function Scroller:update(dt)
   local period = self.run.width + self.loop_gap
   self.offset = (self.offset + self.speed * dt) % period
   self.wave_phase = self.wave_phase + dt * self.wave_speed
end

function SpriteSnake:init(face, text)
   self:super().init(self)
   self.outline_enabled = true
   self.text = text
   self.phase = 0.0
   self.style = self:replace_owned("style", font.create_style(face, {
      pixel_size = 82,
      page_width = 256,
      page_height = 256,
      padding = 2,
   }), function(_, style)
      style:release()
   end)
   self.glyphs = self:create_glyphs(text)
   self.sprites = {}

   for i = 1, #text do
      local character = text:sub(i, i)
      self.sprites[i] = Sprite(i, character, self.glyphs[character])
   end
end

function SpriteSnake:create_glyphs(text)
   local glyphs = {}
   for i = 1, #text do
      local character = text:sub(i, i)
      if glyphs[character] == nil then
         local shaped = font.shape(self.style.sized_face, character)
         glyphs[character] = self.style:get_glyph(shaped.glyphs[1].glyph_id)
      end
   end
   return glyphs
end

function SpriteSnake:release()
   self.sprites = {}
   self.glyphs = nil
   self.style = nil
end

function SpriteSnake:draw(context)
   local layout = context.layout
   for i = 1, #self.sprites do
      self.sprites[i]:draw(
         self.style,
         layout,
         self.phase,
         self.outline_enabled
      )
   end
end

function SpriteSnake:update(dt)
   self.phase = self.phase + dt * 2.35
end

function ProfilerOverlay:init()
   self:super().init(self)
end

function ProfilerOverlay:draw(context)
   if profiler_enabled then
      draw_profiler(
         context.renderer,
         context.scene,
         context.profiler_style,
         context.frame_profiler
      )
   end
end

function Scene:init(renderer, face, scroll_text_value)
   self:super().init(self)
   self.background_color = color.rgb(6, 8, 18)
   self.raster_splits = self:add_child(RasterSplits(renderer, 8))
   self.sprite_snake = self:add_child(SpriteSnake(face, "NEON PHANTOMS"))
   self.title = self:add_child(Title(face, "NEON PHANTOMS"))
   self.scroller = self:add_child(Scroller(face, scroll_text_value))
   self.profiler_overlay = self:add_child(ProfilerOverlay())
end

function Scene:draw(context)
   local renderer = context.renderer
   set_draw_color(
      renderer,
      self.background_color:to_rgba()
   )
   if not sdl3.RenderClear(renderer) then
      rig.raise("failed to clear SDL renderer: " .. ffi.string(sdl3.GetError()))
   end
end

function Scene:set_animation_enabled(enabled)
   self.animator:set_enabled(enabled)
end

function Scene:toggle_animation()
   self:set_animation_enabled(not self.animator.animate_enabled)
end

function Scene:on_key(key_info)
   if key_info.action ~= "down" or key_info["repeat"] then
      return
   end

   if key_info.key == "0" then
      profiler_enabled = not profiler_enabled
   elseif key_info.key == "V" or key_info.key == "v" then
      toggle_vsync()
   elseif key_info.key == "1" then
      self.raster_splits.enabled = not self.raster_splits.enabled
   elseif key_info.key == "2" then
      self.sprite_snake.enabled = not self.sprite_snake.enabled
   elseif key_info.key == "3" then
      self.sprite_snake.outline_enabled = not self.sprite_snake.outline_enabled
   elseif key_info.key == "4" then
      self.scroller.enabled = not self.scroller.enabled
   elseif key_info.key == "5" then
      self:toggle_animation()
   elseif key_info.key == "F" or key_info.key == "f" then
      toggle_fullscreen()
   end
end

function Scene:release()
   self.raster_splits = nil
   self.sprite_snake = nil
   self.title = nil
   self.scroller = nil
   self.profiler_overlay = nil
end

scroll_text = table.concat({
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

find_font_path = function()
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

set_draw_color = function(renderer, r, g, b, a)
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

upload_raster_texture = function(renderer, field, line_height)
   local texture_height = #field * line_height
   local rgba = ffi.new("uint8_t[?]", texture_height * 4)

   for i = 1, #field do
      local line_color = field[i]
      for line = 0, line_height - 1 do
         local pixel_index = ((i - 1) * line_height + line) * 4
         line_color:write_rgba8(rgba, pixel_index)
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

build_raster_field = function()
   local function add_color_line(field, r, g, b, a, repeat_count)
      repeat_count = repeat_count or 1
      for _ = 1, repeat_count do
         field[#field + 1] = color.rgba(r, g, b, a)
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
         local center_mix = intensity * intensity * 0.92
         local hr, hg, hb = 255, 255, 210
         local r = math.floor((tint.r * intensity * (1.0 - center_mix) + hr * center_mix) + 0.5)
         local g = math.floor((tint.g * intensity * (1.0 - center_mix) + hg * center_mix) + 0.5)
         local b = math.floor((tint.b * intensity * (1.0 - center_mix) + hb * center_mix) + 0.5)
         local a = math.floor(255 * math.sqrt(intensity) + 0.5)
         add_color_line(field, r, g, b, a, 1)
      end
   end

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

draw_profiler = function(renderer, scene, style, frame_profiler)
   local profile = frame_profiler:snapshot()
   local panel_x = 18
   local panel_y = 16
   local panel_w = 378
   local panel_h = 210

   set_draw_color(renderer, profiler_panel_color:to_rgba())
   fill_rect(renderer, panel_x, panel_y, panel_w, panel_h)

   local text_x = panel_x + 10
   local header = "      CUR / 1S / MAX"
   local line_1 = ("CPU %.2f / %.2f / %.2f"):format(profile.cpu_ms, profile.cpu_window_max_ms, profile.cpu_peak_ms)
   local line_2 = ("PRS %.2f / %.2f / %.2f"):format(profile.present_ms, profile.present_window_max_ms, profile.present_peak_ms)
   local line_3 = ("TOT %.2f / %.2f / %.2f"):format(profile.total_ms, profile.total_window_max_ms, profile.total_peak_ms)
   local line_4 = ("INT %.2f / %.2f / %.2f"):format(profile.interval_ms, profile.interval_window_max_ms, profile.interval_peak_ms)
   local line_5 = ("GAP %.2f / %.2f / %.2f"):format(profile.gap_ms, profile.gap_window_max_ms, profile.gap_peak_ms)
   local line_6 = ("OVR %d"):format(profile.overruns)
   local line_7 = vsync_enabled and "VSYNC ON [V]" or "VSYNC OFF [V]"
   local line_8 = scene.raster_splits.enabled and "RASTER ON [1]" or "RASTER OFF [1]"
   local line_9 = scene.sprite_snake.enabled and "SPRITES ON [2]" or "SPRITES OFF [2]"
   local line_10 = scene.sprite_snake.outline_enabled and "OUTLINE ON [3]" or "OUTLINE OFF [3]"
   local line_11 = scene.scroller.enabled and "SCROLLER ON [4]" or "SCROLLER OFF [4]"
   local line_12 = scene.animator.animate_enabled and "ANIM ON [5]" or "ANIM OFF [5]"
   local line_13 = fullscreen_enabled and "FULLSCREEN ON [F]" or "FULLSCREEN OFF [F]"
   local line_14 = "PROFILER ON [0]"

   draw_label(style, header, text_x, panel_y + 16, profiler_header_color)
   draw_label(style, line_1, text_x, panel_y + 32, profiler_body_color)
   draw_label(style, line_2, text_x, panel_y + 48, profiler_body_color)
   draw_label(style, line_3, text_x, panel_y + 64, profiler_body_color)
   draw_label(style, line_4, text_x, panel_y + 80, profiler_body_color)
   draw_label(style, line_5, text_x, panel_y + 96, profiler_body_color)
   draw_label(style, line_6, text_x, panel_y + 112, profiler_warn_color)
   draw_label(style, line_7, text_x, panel_y + 128, profiler_toggle_color)
   draw_label(style, line_8, text_x, panel_y + 144, profiler_toggle_color)
   draw_label(style, line_9, text_x + 150, panel_y + 144, profiler_toggle_color)
   draw_label(style, line_10, text_x, panel_y + 160, profiler_toggle_color)
   draw_label(style, line_11, text_x + 150, panel_y + 160, profiler_toggle_color)
   draw_label(style, line_12, text_x, panel_y + 176, profiler_toggle_color)
   draw_label(style, line_13, text_x + 150, panel_y + 176, profiler_toggle_color)
   draw_label(style, line_14, text_x, panel_y + 192, profiler_toggle_color)
end

local function set_vsync(enabled)
   local renderer = sdl3.get_renderer()
   local interval = enabled and 1 or 0
   if not sdl3.SetRenderVSync(renderer, interval) then
      rig.raise("failed to set renderer vsync: " .. ffi.string(sdl3.GetError()))
   end
   vsync_enabled = enabled
end

toggle_vsync = function()
   set_vsync(not vsync_enabled)
end

local function set_fullscreen_enabled(enabled)
   local window = sdl3.get_window()
   if window == nil then
      rig.raise("sdl3 runtime did not provide a window")
   end
   if not sdl3.SetWindowFullscreen(window, enabled) then
      rig.raise("failed to set window fullscreen: " .. ffi.string(sdl3.GetError()))
   end
   if not sdl3.SyncWindow(window) then
      rig.raise("failed to synchronize fullscreen state: " .. ffi.string(sdl3.GetError()))
   end
   fullscreen_enabled = enabled
end

toggle_fullscreen = function()
   set_fullscreen_enabled(not fullscreen_enabled)
end

function App:init()
   self:super().init(self)

   local renderer = sdl3.get_renderer()
   if renderer == nil then
      rig.raise("sdl3 runtime did not provide a renderer")
   end

   font_path = find_font_path()
   face = font.load_face(font_path)
   frame_profiler = profiler.FrameProfiler {
      fps = 60,
   }
   profiler_style = font.create_style(face, {
      pixel_size = 14,
      page_width = 256,
      page_height = 128,
      padding = 1,
   })

   profiler_style:warm_text(
      "CPU PRS TOT INT GAP OVR CUR MAX VSYNC RASTER SPRITES OUTLINE SCROLLER ANIM FULLSCREEN PROFILER ON OFF [] 0123456789./-"
   )

   self.frame_profiler = frame_profiler
   self.profiler_style = profiler_style
   self.root = Scene(renderer, face, scroll_text)
end

function App:before_frame()
   self.frame_profiler:begin_frame()
end

function App:after_frame()
   self.frame_profiler:end_frame()
end

function App:on_key(key_info)
   if self.root ~= nil then
      self.root:on_key(key_info)
   end
end

function App:on_resize(info)
   window_width = math.max(1, info.width)
   window_height = math.max(1, info.height)
end

function App:render()
   self.frame_profiler:begin_cpu()
   local renderer = sdl3.get_renderer()
   local layout = current_layout()
   if self.root ~= nil then
      self.root:draw_tree({
         renderer = renderer,
         layout = layout,
         scene = self.root,
         profiler_style = self.profiler_style,
         frame_profiler = self.frame_profiler,
      })
   end
   self.frame_profiler:end_cpu()
end

function App:release()
   self.frame_profiler = nil
   self.profiler_style = nil
   if profiler_style ~= nil then
      profiler_style:release()
      profiler_style = nil
   end
   if face ~= nil then
      face:release()
      face = nil
   end
   frame_profiler = nil
   font_path = nil
end

rig.run {
   mode = "sdl3",
   driver_config = {
      sdl3 = {
         window_props = {
            [sdl3.PROP_WINDOW_CREATE_TITLE_STRING] = "Neon Phantoms - Midnight Mirror Cracktro",
            [sdl3.PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN] = true,
         },
      },
   },
   app = App,
}
