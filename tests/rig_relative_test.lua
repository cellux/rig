local test = require("test")
local color = require("color")

test.case("rig.require forwards non-relative names to stock require", function()
   test.equal(rig.require("color"), color)
end)

test.case("rig.require loads a sibling lua module", function()
   local base = rig.require("./fixtures/relative_base")

   test.equal(base.kind, "lua")
end)

test.case("rig.require accepts an explicit extension", function()
   local base = rig.require("./fixtures/relative_base.lua")

   test.equal(base.kind, "lua")
end)

test.case("rig.require caches by resolved path", function()
   local first = rig.require("./fixtures/relative_base")
   local second = rig.require("./fixtures/relative_base")

   test.equal(first, second)
end)

test.case("nested relative requires resolve against the nested file", function()
   local parent = rig.require("./fixtures/relative_parent")
   local base = rig.require("./fixtures/relative_base")

   test.equal(parent.kind, "parent")
   test.equal(parent.base, base)
end)

test.case("rig.require loads a fennel sibling", function()
   local value = rig.require("./fixtures/relative_fennel")

   test.equal(value.kind, "fennel")
end)

test.case("rig.require loads a package init module", function()
   local value = rig.require("./fixtures/relative_pkg")

   test.equal(value.kind, "package")
end)

test.case("relative modules do not enter the stock require cache", function()
   rig.require("./fixtures/relative_base")

   local leaked = nil
   for key in pairs(package.loaded) do
      if type(key) == "string" and key:find("relative_base", 1, true) then
         leaked = key
      end
   end

   test.equal(leaked, nil)
end)

test.case("rig.realpath canonicalizes an existing path", function()
   local canonical = rig.realpath(".")

   test.truthy(canonical ~= nil)
   test.equal(canonical:sub(1, 1), "/")
end)

test.case("rig.realpath reports a missing path", function()
   local canonical, err = rig.realpath("this/path/does/not/exist")

   test.equal(canonical, nil)
   test.truthy(err ~= nil)
end)

test.case("equivalent relative spellings share one module instance", function()
   local first = rig.require("./fixtures/relative_base")
   local second = rig.require("./fixtures/../fixtures/relative_base")

   test.equal(first, second)
end)

test.case("rig.require reports a missing module", function()
   local ok, err = pcall(function()
      rig.require("./fixtures/does_not_exist")
   end)

   test.falsey(ok)
   test.match(tostring(err), "could not find")
end)