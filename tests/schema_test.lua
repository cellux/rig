local test = require("test")
local schema = require("schema")

test.case("schema number can coerce and constrain values", function()
   local jobs_schema = schema.positive_number {
      coerce = true,
      integer = true,
   }

   test.equal(schema.assert(jobs_schema, "4", "jobs"), 4)

   local ok, err = schema.check(jobs_schema, "0", "jobs")
   test.falsey(ok)
   test.match(err, "jobs expects a positive number")
end)

test.case("schema positive_integer coerces integers and rejects non-positive or fractional values", function()
   local history_schema = schema.positive_integer {
      coerce = true,
   }

   test.equal(schema.assert(history_schema, "4", "history"), 4)

   local zero_ok, zero_err = schema.check(history_schema, "0", "history")
   test.falsey(zero_ok)
   test.match(zero_err, "history expects a positive integer")

   local fractional_ok, fractional_err = schema.check(history_schema, "1.5", "history")
   test.falsey(fractional_ok)
   test.match(fractional_err, "history expects a positive integer")
end)

test.case("schema record supports optional defaults and extra-field control", function()
   local point_schema = schema.record({
      x = schema.number(),
      y = schema.number(),
      label = schema.non_empty_string():optional("pt"),
   })

   local decoded = schema.assert(point_schema, {
      x = 3,
      y = 5,
   }, "point")

   test.equal(decoded.x, 3)
   test.equal(decoded.y, 5)
   test.equal(decoded.label, "pt")

   local ok, err = schema.check(point_schema, {
      x = 1,
      y = 2,
      z = 3,
   }, "point")
   test.falsey(ok)
   test.match(err, "point.z is not allowed")
end)

test.case("schema optional_with constructs a fresh default value", function()
   local tags_schema = schema.optional_with(schema.array(schema.non_empty_string()), function()
      return {}
   end)

   local first = schema.assert(tags_schema, nil, "tags")
   local second = schema.assert(tags_schema, nil, "tags")

   test.truthy(first ~= second)

   first[1] = "alpha"
   test.equal(#second, 0)
end)

test.case("schema record can opt in to allow extra fields", function()
   local point_schema = schema.record({
      x = schema.number(),
      y = schema.number(),
   }, {
      allow_extra = true,
   })

   local decoded = schema.assert(point_schema, {
      x = 1,
      y = 2,
      z = 3,
   }, "point")

   test.equal(decoded.x, 1)
   test.equal(decoded.y, 2)
   test.equal(decoded.z, 3)
end)

test.case("schema array can enforce uniqueness", function()
   local names_schema = schema.array(schema.non_empty_string(), {
      unique = true,
   })

   local decoded = schema.assert(names_schema, {
      "alpha",
      "beta",
   }, "names")
   test.equal(decoded[1], "alpha")
   test.equal(decoded[2], "beta")

   local ok, err = schema.check(names_schema, {
      "alpha",
      "alpha",
   }, "names")
   test.falsey(ok)
   test.match(err, "duplicates an earlier array value")
end)

test.case("schema transform injects caller normalization logic", function()
   local trim_and_upper = schema.non_empty_string():transform(function(value)
      return value:gsub("^%s+", ""):gsub("%s+$", ""):upper()
   end)

   test.equal(schema.assert(trim_and_upper, "  hello  ", "greeting"), "HELLO")
end)

test.case("schema transform can normalize whole records", function()
   local point_schema = schema.record({
      x = schema.number(),
      y = schema.number(),
   }):transform(function(decoded)
      decoded.length_sq = decoded.x * decoded.x + decoded.y * decoded.y
      return decoded
   end)

   local point = schema.assert(point_schema, {
      x = 3,
      y = 4,
   }, "point")

   test.equal(point.length_sq, 25)
end)

test.case("schema has_metatable validates metatable-backed values", function()
   local mt = {}
   local value = setmetatable({}, mt)

   local decoded = schema.assert(
      schema.has_metatable(mt, "a test instance"),
      value,
      "thing"
   )
   test.equal(decoded, value)

   local ok, err = schema.check(schema.has_metatable(mt, "a test instance"), {}, "thing")
   test.falsey(ok)
   test.match(err, "thing expects a test instance")
end)
