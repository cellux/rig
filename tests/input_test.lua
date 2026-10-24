local test = require("test")
local input = require("input")

test.case("input tracks held, pressed, and released keys by name and scancode", function()
   local state = input.Input()

   state:on_key { action = "down", key = "W", scancode = 26 }
   test.truthy(state:key_down("w"))
   test.truthy(state:key_down("W"))
   test.truthy(state:key_down(26))
   test.truthy(state:key_pressed("W"))
   test.truthy(state:key_pressed(26))

   state:on_key { action = "up", key = "W", scancode = 26 }
   test.falsey(state:key_down("W"))
   test.truthy(state:key_released("W"))
   test.truthy(state:key_released(26))

   state:begin_frame()
   test.falsey(state:key_released("W"))
   test.falsey(state:key_pressed("W"))
end)

test.case("input ignores repeat key-downs for the pressed edge", function()
   local state = input.Input()

   state:on_key { action = "down", key = "Space", scancode = 44 }
   state:begin_frame()
   state:on_key { action = "down", key = "Space", scancode = 44, ["repeat"] = true }

   test.truthy(state:key_down("Space"))
   test.falsey(state:key_pressed("Space"))
end)

test.case("input tracks mouse motion, buttons, and deltas", function()
   local state = input.Input()

   state:on_mouse { action = "move", x = 10, y = 20, xrel = 3, yrel = -2 }
   state:on_mouse { action = "move", x = 14, y = 18, xrel = 4, yrel = -2 }

   local x, y = state:mouse_position()
   test.equal(x, 14)
   test.equal(y, 18)

   local dx, dy = state:mouse_delta()
   test.equal(dx, 7)
   test.equal(dy, -4)

   state:on_mouse { action = "down", button = 1, x = 14, y = 18 }
   test.truthy(state:mouse_down(1))
   test.truthy(state:mouse_pressed(1))
   test.truthy(state:mouse_down())

   state:on_mouse { action = "up", button = 1, x = 14, y = 18 }
   test.falsey(state:mouse_down(1))
   test.truthy(state:mouse_released(1))

   state:begin_frame()
   test.equal(select(1, state:mouse_delta()), 0)
   test.falsey(state:mouse_pressed(1))
end)

test.case("input exposes axes and modifier state", function()
   local state = input.Input()

   state:on_key { action = "down", key = "A", scancode = 4 }
   state:on_key { action = "down", key = "D", scancode = 7 }

   test.equal(state:axis("A", "D"), 0)
   test.equal(state:axis("A", "Q"), -1)
   test.equal(state:axis("X", "D"), 1)

   state:on_key {
      action = "down",
      key = "A",
      scancode = 4,
      mods = { shift = true, ctrl = true },
   }
   test.truthy(state.shift)
   test.truthy(state.ctrl)
   test.falsey(state.alt)
end)
