local test = require("test")
local app = require("app")

local function fake_window()
   local calls = {}
   return {
      set_relative_mouse_mode = function(_, enabled)
         calls.relative = enabled
         return enabled
      end,
      set_mouse_grab = function(_, enabled)
         calls.grab = enabled
         return enabled
      end,
   }, calls
end

test.case("app.App toggles relative mouse mode and grab together", function()
   local window, calls = fake_window()
   local instance = app.App { window = window }

   test.truthy(instance:can_mouse_grab())
   test.equal(instance:set_mouse_grab(true), true)
   test.equal(calls.relative, true)
   test.equal(calls.grab, true)
   test.equal(instance.mouse_grab_enabled, true)
   test.equal(instance:toggle_mouse_grab(), false)
   test.equal(calls.relative, false)
   test.equal(calls.grab, false)
   test.equal(instance.mouse_grab_enabled, false)
end)

test.case("app.App releases grab on focus loss and restores it on focus gain", function()
   local window, calls = fake_window()
   local instance = app.App { window = window }

   instance:set_mouse_grab(true)
   instance.focused = false
   instance:apply_mouse_grab()
   test.equal(calls.relative, false)
   test.equal(instance.mouse_grab_enabled, false)

   instance.focused = true
   instance:apply_mouse_grab()
   test.equal(calls.relative, true)
   test.equal(instance.mouse_grab_enabled, true)
end)

test.case("app.App reports unsupported grab when the window has no method", function()
   local instance = app.App { window = {} }

   test.falsey(instance:can_mouse_grab())
   test.equal(instance:set_mouse_grab(true), false)
   test.falsey(instance.mouse_grab_enabled)
end)
