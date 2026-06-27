local prelude = require("prelude")
local test = require("test")

test.case("prelude.class constructs instances and calls init", function()
   local Point = prelude.class()

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

test.case("prelude.class supports single inheritance for methods", function()
   local Animal = prelude.class()

   function Animal:init(name)
      self.name = name
   end

   function Animal:speak()
      return "..."
   end

   function Animal:describe()
      return self.name .. ":" .. self:speak()
   end

   local Dog = prelude.class(Animal)

   function Dog:speak()
      return "woof"
   end

   local dog = Dog("fido")
   test.equal(dog.name, "fido")
   test.equal(dog:speak(), "woof")
   test.equal(dog:describe(), "fido:woof")
   test.equal(getmetatable(Dog).__index, Animal)
end)

test.case("prelude.class exposes super for explicit parent init calls", function()
   local Animal = prelude.class()

   function Animal:init(name)
      self.name = name
   end

   local Dog = prelude.class(Animal)

   function Dog:init(name, breed)
      self:super().init(self, name)
      self.breed = breed
   end

   local dog = Dog("fido", "mutt")
   test.equal(dog:super(), Animal)
   test.equal(dog.name, "fido")
   test.equal(dog.breed, "mutt")
end)

test.case("prelude.class accepts missing init", function()
   local Empty = prelude.class()
   local instance = Empty()

   test.equal(type(instance), "table")
   test.equal(getmetatable(instance), Empty)
end)

test.case("prelude.class validates parent type", function()
   local ok, err = pcall(function()
      prelude.class("not a class")
   end)

   test.falsey(ok)
   test.match(tostring(err), "expects parent to be a table")
end)

test.case("prelude.set builds membership sets from arrays", function()
   local values = prelude.set({
      "alpha",
      "beta",
      "alpha",
   })

   test.truthy(values.alpha)
   test.truthy(values.beta)
   test.falsey(values.gamma)
end)

test.case("prelude.class supports is_instance across inheritance", function()
   local Animal = prelude.class()
 
   function Animal:speak()
      return "..."
   end

   local Dog = prelude.class(Animal)

   function Dog:speak()
      return "woof"
   end

   local Puppy = prelude.class(Dog)

   function Puppy:speak()
      return "yip"
   end

   function Animal:parent_speak()
      return self:super().speak(self)
   end

   local dog = Dog()
   local puppy = Puppy()

   test.truthy(Dog:is_instance(dog))
   test.truthy(Animal:is_instance(dog))
   test.equal(puppy:parent_speak(), "woof")
   test.falsey(Dog:is_instance({}))
end)

test.case("prelude.class supports is_descendant across inheritance", function()
   local Animal = prelude.class()
   local Dog = prelude.class(Animal)
   local Puppy = prelude.class(Dog)

   test.truthy(Puppy:is_descendant(Dog))
   test.truthy(Puppy:is_descendant(Animal))
   test.truthy(Dog:is_descendant(Animal))
   test.truthy(Animal:is_descendant(Animal))
   test.falsey(Animal:is_descendant(Dog))
   test.falsey(Dog:is_descendant({}))
end)

test.case("prelude.raise raises without stack location and formats when needed", function()
   local ok, err = pcall(function()
      prelude.raise("bad value '%s'", "x")
   end)

   test.falsey(ok)
   test.equal(err, "bad value 'x'")
end)

test.case("rig aliases prelude.class and prelude.raise", function()
   test.equal(rig.set, prelude.set)
   test.equal(rig.class, prelude.class)
   test.equal(rig.raise, prelude.raise)
end)
