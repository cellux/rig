local prelude = require("prelude")
local test = require("test")

test.case("prelude.Class constructs classes and instances and calls init", function()
   local Point = prelude.Class()

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

test.case("prelude.Class supports single inheritance for methods", function()
   local Animal = prelude.Class()

   function Animal:init(name)
      self.name = name
   end

   function Animal:speak()
      return "..."
   end

   function Animal:describe()
      return self.name .. ":" .. self:speak()
   end

   local Dog = prelude.Class(Animal)

   function Dog:speak()
      return "woof"
   end

   local dog = Dog("fido")
   test.equal(dog.name, "fido")
   test.equal(dog:speak(), "woof")
   test.equal(dog:describe(), "fido:woof")
   test.equal(getmetatable(Dog), prelude.Class)
   test.equal(Dog:super(), Animal)
end)

test.case("prelude.Class exposes super for explicit parent init calls", function()
   local Animal = prelude.Class()

   function Animal:init(name)
      self.name = name
   end

   local Dog = prelude.Class(Animal)

   function Dog:init(name, breed)
      self:super().init(self, name)
      self.breed = breed
   end

   local dog = Dog("fido", "mutt")
   test.equal(dog:super(), Animal)
   test.equal(dog.name, "fido")
   test.equal(dog.breed, "mutt")
end)

test.case("prelude.Class accepts missing init", function()
   local Empty = prelude.Class()
   local instance = Empty()

   test.equal(type(instance), "table")
   test.equal(getmetatable(instance), Empty)
end)

test.case("prelude.Class validates parent type", function()
   local ok, err = pcall(function()
      prelude.Class("not a class")
   end)

   test.falsey(ok)
   test.match(tostring(err), "expects parent to be a class")
end)

test.case("prelude.Class rejects Class itself as a declared parent", function()
   local ok, err = pcall(function()
      prelude.Class(prelude.Class)
   end)

   test.falsey(ok)
   test.match(tostring(err), "other than Class")
end)

test.case("prelude.is_class identifies rig classes exactly", function()
   local Animal = prelude.Class()
   local Dog = prelude.Class(Animal)
   local dog = Dog()
   local fake_class = {}
   fake_class.__index = fake_class

   test.truthy(prelude.is_class(Animal))
   test.truthy(prelude.is_class(Dog))
   test.truthy(prelude.is_class(prelude.Class))
   test.falsey(prelude.is_class(dog))
   test.falsey(prelude.is_class(fake_class))
   test.falsey(prelude.is_class({}))
   test.falsey(prelude.is_class("Animal"))
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

test.case("prelude.Class supports is_instance across inheritance", function()
   local Animal = prelude.Class()

   function Animal:speak()
      return "..."
   end

   local Dog = prelude.Class(Animal)

   function Dog:speak()
      return "woof"
   end

   local Puppy = prelude.Class(Dog)

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

test.case("prelude.Class supports is_descendant across inheritance", function()
   local Animal = prelude.Class()
   local Dog = prelude.Class(Animal)
   local Puppy = prelude.Class(Dog)
   local dog = Dog()

   test.truthy(Puppy:is_descendant(Dog))
   test.truthy(Puppy:is_descendant(Animal))
   test.truthy(Puppy:is_descendant(prelude.Class))
   test.truthy(Dog:is_descendant(Animal))
   test.truthy(Animal:is_descendant(Animal))
   test.truthy(Animal:is_descendant(prelude.Class))
   test.truthy(prelude.Class:is_descendant(prelude.Class))
   test.falsey(Animal:is_descendant(Dog))
   test.falsey(dog:is_descendant(Animal))
   test.falsey(Dog:is_descendant({}))
end)

test.case("prelude.Class supports is_ancestor across inheritance", function()
   local Animal = prelude.Class()
   local Dog = prelude.Class(Animal)
   local Puppy = prelude.Class(Dog)
   local dog = Dog()

   test.truthy(prelude.Class:is_ancestor(Animal))
   test.truthy(prelude.Class:is_ancestor(Dog))
   test.truthy(Animal:is_ancestor(Dog))
   test.truthy(Animal:is_ancestor(Puppy))
   test.truthy(Dog:is_ancestor(Puppy))
   test.truthy(Animal:is_ancestor(Animal))
   test.falsey(Dog:is_ancestor(Animal))
   test.falsey(Animal:is_ancestor(dog))
   test.falsey(Animal:is_ancestor({}))
end)

test.case("prelude.Class is the metaclass for rig classes", function()
   local Animal = prelude.Class()
   local animal = Animal()

   test.equal(getmetatable(Animal), prelude.Class)
   test.equal(Animal:super(), nil)
   test.truthy(prelude.Class:is_instance(prelude.Class))
   test.truthy(prelude.Class:is_instance(Animal))
   test.falsey(prelude.Class:is_instance(animal))
end)

test.case("prelude.raise raises without stack location and formats when needed", function()
   local ok, err = pcall(function()
      prelude.raise("bad value '%s'", "x")
   end)

   test.falsey(ok)
   test.equal(err, "bad value 'x'")
end)

test.case("rig aliases prelude Class helpers and raise", function()
   test.equal(rig.set, prelude.set)
   test.equal(rig.is_class, prelude.is_class)
   test.equal(rig.Class, prelude.Class)
   test.equal(rig.raise, prelude.raise)
end)
