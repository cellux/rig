-- Procedural Córdoba material textures.
--
-- Every texture is generated in-repo from a deterministic seed and contains no
-- external photographic data. `M.provenance` records the generator, seed, size,
-- and license for each image so the material set can be regenerated or audited.

local M = {}

local function clamp(x, lo, hi)
   if x < lo then
      return lo
   end
   if x > hi then
      return hi
   end
   return x
end

local function byte(x)
   return math.floor(clamp(x, 0.0, 255.0) + 0.5)
end

-- Deterministic lattice hash. This is not cryptographic; it only needs to look
-- irregular and to be stable across runs.
local function hash(ix, iy, seed)
   local n = math.sin(ix * 127.1 + iy * 311.7 + seed * 74.7) * 43758.5453
   return n - math.floor(n)
end

local function smooth(t)
   return t * t * (3.0 - 2.0 * t)
end

local function value_noise(x, y, period, seed)
   local ix = math.floor(x)
   local iy = math.floor(y)
   local fx = smooth(x - ix)
   local fy = smooth(y - iy)
   local x0 = ix % period
   local y0 = iy % period
   local x1 = (ix + 1) % period
   local y1 = (iy + 1) % period
   local a = hash(x0, y0, seed)
   local b = hash(x1, y0, seed)
   local c = hash(x0, y1, seed)
   local d = hash(x1, y1, seed)
   local ab = a + (b - a) * fx
   local cd = c + (d - c) * fx
   return ab + (cd - ab) * fy
end

local function fbm(u, v, period, seed, octaves)
   local total, weight, norm = 0.0, 0.5, 0.0
   local p = period
   for octave = 0, octaves - 1 do
      total = total + value_noise(u * p, v * p, p, seed + octave * 19) * weight
      norm = norm + weight
      weight = weight * 0.5
      p = p * 2
   end
   return total / norm
end

local function image(width, height, fn)
   local rows = {}
   for y = 0, height - 1 do
      local row = {}
      local v = (y + 0.5) / height
      for x = 0, width - 1 do
         local u = (x + 0.5) / width
         local r, g, b = fn(u, v, x, y)
         row[#row + 1] = string.char(byte(r), byte(g), byte(b), 255)
      end
      rows[#rows + 1] = table.concat(row)
   end
   return {
      width = width,
      height = height,
      channels = 4,
      pixels = table.concat(rows),
   }
end

local function limestone(u, v)
   local coarse = fbm(u, v, 5, 11, 4)
   local fine = fbm(u, v, 21, 17, 3)
   local pit = value_noise(u * 57, v * 57, 57, 23)
   local base = 205 + (coarse - 0.5) * 28 + (fine - 0.5) * 12
   if pit > 0.93 then
      base = base - 16
   end
   return base + 8, base, base - 12
end

local function plaster(u, v)
   local n = fbm(u, v, 15, 31, 4)
   local streak = 0.5 + 0.5 * math.sin(v * 31.0 + n * 4.0)
   local base = 226 + (n - 0.5) * 16 + (streak - 0.5) * 5
   return base + 4, base, base - 10
end

local function brick(u, v)
   local rows = 8
   local columns = 4
   local row = math.floor(v * rows)
   local offset = (row % 2 == 0) and 0.0 or 0.5
   local column = math.floor(u * columns + offset)
   local mortar = math.min(
      math.abs((u * columns + offset) % 1.0),
      math.abs((v * rows) % 1.0)
   )
   local variation = hash(column, row, 41)
   local grain = fbm(u, v, 18, 43, 3)
   local r = 146 + variation * 30 + (grain - 0.5) * 14
   local g = 58 + variation * 18 + (grain - 0.5) * 8
   local b = 43 + variation * 12 + (grain - 0.5) * 6
   if mortar < 0.035 then
      r, g, b = 208, 194, 168
   end
   return r, g, b
end

local function terracotta_floor(u, v)
   -- Four large tiles across and eight down, with staggered joints.
   local columns = 4
   local rows = 8
   local row = math.floor(v * rows)
   local offset = (row % 2 == 0) and 0.0 or 0.5
   local column = math.floor(u * columns + offset)
   local fu = (u * columns + offset) % 1.0
   local fv = (v * rows) % 1.0
   local joint = math.min(fu, 1.0 - fu, fv, 1.0 - fv)
   local tile = hash(column, row, 53)
   local grain = fbm(u, v, 24, 59, 4)
   local wear = fbm(u + 0.3, v + 0.7, 8, 61, 2)
   local r = 150 + tile * 46 + (grain - 0.5) * 26 + (wear - 0.5) * 12
   local g = 83 + tile * 30 + (grain - 0.5) * 18 + (wear - 0.5) * 8
   local b = 52 + tile * 18 + (grain - 0.5) * 12 + (wear - 0.5) * 5
   if joint < 0.022 then
      r, g, b = 72, 62, 50
   else
      -- A few darker, cooler replacement tiles break up the repetition.
      if tile < 0.18 then
         r, g, b = r * 0.72, g * 0.72, b * 0.72
      elseif tile > 0.84 then
         r, g, b = r * 1.06, g * 0.98, b * 0.90
      end
   end
   return r, g, b
end

local function marble(u, v)
   local vein = fbm(u * 1.6, v * 2.0, 7, 71, 5)
   local secondary = fbm(u * 4.0, v * 3.0, 13, 73, 3)
   local line = math.abs(math.sin((u * 5.0 + v * 3.0 + vein * 2.4) * math.pi))
   local dark = math.max(0.0, 1.0 - line * 24.0)
   local base = 216 + (secondary - 0.5) * 12 - dark * 34
   return base + 6, base, base - 12
end

local function wood(u, v)
   local plank = math.floor(v * 6.0)
   local plank_variation = hash(plank, 0, 83)
   local grain = fbm(u * 2.0, v * 14.0, 16, 89, 4)
   local ring = 0.5 + 0.5 * math.sin(v * 90.0 + grain * 9.0 + plank_variation * 4.0)
   local seam = math.min((v * 6.0) % 1.0, 1.0 - (v * 6.0) % 1.0)
   local base = 112 + plank_variation * 28 + (grain - 0.5) * 22
   local r = base + 28 + ring * 14
   local g = base + 10 + ring * 8
   local b = base - 12 + ring * 3
   if seam < 0.025 then
      r, g, b = 54, 38, 27
   end
   return r, g, b
end

local function granite(u, v)
   local coarse = fbm(u, v, 9, 97, 4)
   local speckle = value_noise(u * 70, v * 70, 70, 101)
   local base = 58 + (coarse - 0.5) * 18
   local r = base + 6
   local g = base + 8
   local b = base + 10
   if speckle > 0.84 then
      r, g, b = r + 54, g + 52, b + 46
   elseif speckle < 0.09 then
      r, g, b = r - 18, g - 16, b - 12
   end
   return r, g, b
end

local function stained_glass(u, v)
   local columns = 5
   local rows = 10
   local cx = u * columns
   local cy = v * rows
   local column = math.floor(cx)
   local row = math.floor(cy)
   local fu = cx % 1.0
   local fv = cy % 1.0
   local lead = math.min(fu, 1.0 - fu, fv, 1.0 - fv)
   local cell = hash(column, row, 127)
   local grain = value_noise(cx * 2.0, cy * 2.0, 32, 131)
   local palette = {
      { 126, 28, 30 },
      { 28, 52, 118 },
      { 36, 94, 72 },
      { 176, 122, 38 },
      { 76, 38, 96 },
      { 148, 64, 48 },
   }
   local tint = palette[math.floor(cell * #palette) + 1]
   local brightness = 0.78 + cell * 0.30 + (grain - 0.5) * 0.08
   local dx = u - 0.5
   local dy = (v - 0.47) * 1.15
   local medallion = math.sqrt(dx * dx + dy * dy)
   if medallion < 0.23 then
      -- A brighter central medallion keeps the windows from reading as a
      -- uniform grid of coloured rectangles.
      local jewel = palette[math.floor(hash(0, 0, 133) * #palette) + 1]
      tint = jewel
      brightness = brightness + 0.20 * (1.0 - medallion / 0.23)
   end
   local r = tint[1] * brightness
   local g = tint[2] * brightness
   local b = tint[3] * brightness
   if lead < 0.035 or math.abs(medallion - 0.23) < 0.018 then
      r, g, b = 26, 24, 22
   elseif u < 0.030 or u > 0.970 or v < 0.018 or v > 0.982 then
      r, g, b = 44, 38, 32
   end
   return r, g, b
end

local function painting(u, v)
   -- A dark old-master canvas: warm shadowed ground, a brighter central figure
   -- mass, and a few gold/red drapery highlights. It reads at a distance and is
   -- deliberately low-contrast so individual paintings do not compete with the
   -- architecture.
   local ground = fbm(u, v, 6, 151, 4)
   local dx = (u - 0.5) * 2.0
   local dy = (v - 0.5) * 2.0
   local vignette = math.min(1.0, math.sqrt(dx * dx + dy * dy))
   local glow = 1.0 - vignette
   local figure = math.exp(-((u - 0.5) * (u - 0.5)) / 0.020) * (0.45 + 0.55 * v)
   local drapery = fbm(u * 2.0, v * 3.0, 9, 157, 3)
   local highlight = math.max(0.0, drapery - 0.62) * 2.0
   local r = 34 + ground * 52 + glow * 74 + figure * 96 + highlight * 60
   local g = 26 + ground * 38 + glow * 48 + figure * 60 + highlight * 30
   local b = 20 + ground * 28 + glow * 30 + figure * 36 + highlight * 22
   return r, g, b
end

local function metal(u, v)
   local brushed = fbm(u * 30.0, v * 1.5, 30, 109, 3)
   local patina = fbm(u, v, 7, 113, 4)
   local base = 48 + (brushed - 0.5) * 18 + (patina - 0.5) * 16
   return base + 4, base + 5, base + 7
end

local dimensions = {
   limestone = { 128, 128, limestone, 11 },
   plaster = { 128, 128, plaster, 31 },
   brick = { 128, 128, brick, 41 },
   terracotta_floor = { 256, 256, terracotta_floor, 53 },
   marble = { 128, 128, marble, 71 },
   wood = { 128, 128, wood, 83 },
   granite = { 128, 128, granite, 97 },
   metal = { 128, 128, metal, 109 },
   stained_glass = { 128, 256, stained_glass, 127 },
   painting = { 128, 192, painting, 151 },
}

function M.create()
   local images = {}
   for name, spec in pairs(dimensions) do
      images[name] = image(spec[1], spec[2], spec[3])
   end
   return images
end

M.provenance = {
   limestone = {
      kind = "procedural",
      generator = "examples/Cordoba/scene/textures.lua:limestone",
      seed = 11,
      size = "128x128",
      license = "generated in-repo",
      source = "deterministic value noise and limestone tint",
   },
   plaster = {
      kind = "procedural",
      generator = "examples/Cordoba/scene/textures.lua:plaster",
      seed = 31,
      size = "128x128",
      license = "generated in-repo",
      source = "deterministic value noise and warm plaster tint",
   },
   brick = {
      kind = "procedural",
      generator = "examples/Cordoba/scene/textures.lua:brick",
      seed = 41,
      size = "128x128",
      license = "generated in-repo",
      source = "staggered brick courses with mortar and per-brick variation",
   },
   terracotta_floor = {
      kind = "procedural",
      generator = "examples/Cordoba/scene/textures.lua:terracotta_floor",
      seed = 53,
      size = "256x256",
      license = "generated in-repo",
      source = "staggered terracotta tile grid with wear and replacement tiles",
   },
   marble = {
      kind = "procedural",
      generator = "examples/Cordoba/scene/textures.lua:marble",
      seed = 71,
      size = "128x128",
      license = "generated in-repo",
      source = "veined pale limestone/marble approximation",
   },
   wood = {
      kind = "procedural",
      generator = "examples/Cordoba/scene/textures.lua:wood",
      seed = 83,
      size = "128x128",
      license = "generated in-repo",
      source = "dark timber planks with grain and seams",
   },
   granite = {
      kind = "procedural",
      generator = "examples/Cordoba/scene/textures.lua:granite",
      seed = 97,
      size = "128x128",
      license = "generated in-repo",
      source = "dark polished granite with light speckle",
   },
   metal = {
      kind = "procedural",
      generator = "examples/Cordoba/scene/textures.lua:metal",
      seed = 109,
      size = "128x128",
      license = "generated in-repo",
      source = "brushed dark iron with subtle patina",
   },
   stained_glass = {
      kind = "procedural",
      generator = "examples/Cordoba/scene/textures.lua:stained_glass",
      seed = 127,
      size = "128x256",
      license = "generated in-repo",
      source = "jewel-toned leaded glass panes",
   },
   painting = {
      kind = "procedural",
      generator = "examples/Cordoba/scene/textures.lua:painting",
      seed = 151,
      size = "128x192",
      license = "generated in-repo",
      source = "dark old-master canvas with a central figure mass and drapery highlights",
   },
}

return M
