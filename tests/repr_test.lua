local test = require("test")
local repr = require("repr")

test.case("repr returns readable source for plain data", function()
   local value = {
      "alpha",
      "beta",
      foo = 3,
      nested = {
         1,
         two = "x",
      },
      [false] = "no",
   }

   local text = repr.repr(value)
   test.equal(text, '{"alpha", "beta", foo = 3, nested = {1, two = "x"}, [false] = "no"}')

   local chunk = assert(loadstring("return " .. text))
   local roundtrip = chunk()
   test.equal(roundtrip[1], "alpha")
   test.equal(roundtrip[2], "beta")
   test.equal(roundtrip.foo, 3)
   test.equal(roundtrip.nested[1], 1)
   test.equal(roundtrip.nested.two, "x")
   test.equal(roundtrip[false], "no")
end)

test.case("repr supports multiline indentation", function()
   local text = repr.repr({
      answer = 42,
      nested = {
         1,
         two = "x",
      },
   }, {
      indent = "  ",
   })

   test.equal(text, [[{
  answer = 42,
  nested = {
    1,
    two = "x",
  },
}]])
end)

test.case("repr handles cycles and non-reconstructible values", function()
   local value = {}
   value.self = value

   test.equal(repr.repr(value), '{self = "<cycle>"}')
   test.match(repr.repr(function() end), '^"<function: 0x%x+>"$')
   test.match(repr.repr(coroutine.create(function() end)), '^"<thread: 0x%x+>"$')
end)

test.case("repr module is callable", function()
   test.equal(repr({
      a = 1,
   }), '{a = 1}')
end)
