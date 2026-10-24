local test = require("test")
local input = require("input")
local overlay = require("overlay")
local params = require("params")

local function fake_scene()
   return {
      width = 800,
      height = 600,
      draws = {},
      draw_screen = function(self, mesh, x, y, width, height)
         self.draws[#self.draws + 1] = {
            mesh = mesh,
            x = x,
            y = y,
            width = width,
            height = height,
         }
      end,
   }
end

local function store()
   return params.params {
      { name = "speed", min = 0.0, max = 10.0, step = 1.0, value = 0.0 },
      { name = "debug", kind = "boolean", value = false },
   }
end

test.case("overlay selects and adjusts parameters from the keyboard", function()
   local values = store()
   local view = overlay.overlay(values)
   local state = input.Input()
   local scene = fake_scene()

   state:on_key { action = "down", key = "Down", scancode = 81 }
   view:update(state, scene)
   test.equal(view.selected, 2)

   state:begin_frame()
   state:on_key { action = "down", key = "Space", scancode = 44 }
   view:update(state, scene)
   test.equal(values:get("debug"), true)

   state:begin_frame()
   state:on_key { action = "down", key = "Up", scancode = 82 }
   view:update(state, scene)
   test.equal(view.selected, 1)

   state:begin_frame()
   state:on_key { action = "down", key = "Right", scancode = 79 }
   view:update(state, scene)
   test.equal(values:get("speed"), 1.0)

   state:begin_frame()
   state:on_key { action = "down", key = "Left", scancode = 80 }
   view:update(state, scene)
   test.equal(values:get("speed"), 0.0)
end)

test.case("overlay wraps keyboard selection", function()
   local values = store()
   local view = overlay.overlay(values)
   local state = input.Input()
   local scene = fake_scene()

   state:on_key { action = "down", key = "Up", scancode = 82 }
   view:update(state, scene)
   test.equal(view.selected, 2)
end)

test.case("overlay drags a number bar with the mouse", function()
   local values = store()
   local view = overlay.overlay(values)
   local state = input.Input()
   local scene = fake_scene()

   -- top-left margin 12, label 96, gap 4 => bar starts at 112, width 160.
   state:on_mouse { action = "down", button = 1, x = 112 + 80, y = 20 }
   view:update(state, scene)

   test.equal(view.selected, 1)
   test.equal(view.dragging, 1)
   test.equal(values:get("speed"), 5.0)

   state:begin_frame()
   state:on_mouse { action = "move", x = 112 + 160, y = 20 }
   view:update(state, scene)
   test.equal(values:get("speed"), 10.0)

   state:begin_frame()
   state:on_mouse { action = "up", button = 1, x = 112 + 160, y = 20 }
   view:update(state, scene)
   test.equal(view.dragging, nil)
end)

test.case("overlay draws a track, a fill, and a selection per row", function()
   local values = store()
   local view = overlay.overlay(values)
   local scene = fake_scene()

   values:set("speed", 5.0)
   view:draw(scene)

   -- Two rows: track + fill for the number, track for the boolean, plus one
   -- selection indicator.
   test.equal(#scene.draws, 4)
   test.equal(scene.draws[1].x, 112)
   test.equal(scene.draws[1].width, 160)
   test.equal(scene.draws[2].width, 80)
end)

test.case("overlay supports a text callback and positions", function()
   local values = store()
   local labels = {}
   local view = overlay.overlay(values, {
      position = "bottom-right",
      draw_text = function(_, _, _, text)
         labels[#labels + 1] = text
      end,
   })
   local scene = fake_scene()

   view:draw(scene)

   test.equal(#labels, 2)
   test.match(labels[1], "speed")
end)
