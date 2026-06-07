local oop = require("oop")
local test = require("test")

test.case("oop.class constructs instances and calls init", function()
   local Point = oop.class()

   function Point:init(x, y)
      self.x = x
      self.y = y
   end

   function Point:sum()
      return self.x + self.y
   end

   local point = Point(3, 4)
   test.equal(type(point), "table")
   test.equal(point.x, 3)
   test.equal(point.y, 4)
   test.equal(point:sum(), 7)
   test.equal(getmetatable(point), Point)
end)

test.case("oop.class supports single inheritance for methods", function()
   local Animal = oop.class()

   function Animal:init(name)
      self.name = name
   end

   function Animal:speak()
      return "..."
   end

   function Animal:describe()
      return self.name .. ":" .. self:speak()
   end

   local Dog = oop.class(Animal)

   function Dog:speak()
      return "woof"
   end

   local dog = Dog("fido")
   test.equal(dog.name, "fido")
   test.equal(dog:speak(), "woof")
   test.equal(dog:describe(), "fido:woof")
   test.equal(getmetatable(Dog).__index, Animal)
end)

test.case("oop.class accepts missing init", function()
   local Empty = oop.class()
   local instance = Empty()

   test.equal(type(instance), "table")
   test.equal(getmetatable(instance), Empty)
end)

test.case("oop.class validates parent type", function()
   local ok, err = pcall(function()
      oop.class("not a class")
   end)

   test.falsey(ok)
   test.match(tostring(err), "expects parent to be a table")
end)

test.case("oop.class supports is_instance across inheritance", function()
   local Animal = oop.class()
   local Dog = oop.class(Animal)
   local dog = Dog()

   test.truthy(Dog:is_instance(dog))
   test.truthy(Animal:is_instance(dog))
   test.falsey(Dog:is_instance({}))
end)

test.case("rig.class aliases oop.class", function()
   test.equal(rig.class, oop.class)
end)
