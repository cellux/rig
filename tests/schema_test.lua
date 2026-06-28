local test = require("test")
local ffi = require("ffi")
local rig = require("rig")
local schema = require("schema")

ffi.cdef[[
typedef struct rig_schema_test_Point {
   int x;
   int y;
} rig_schema_test_Point;

typedef struct rig_schema_test_Line {
   rig_schema_test_Point start;
   rig_schema_test_Point finish;
} rig_schema_test_Line;

typedef struct rig_schema_test_IntList {
   int *values;
   int count;
} rig_schema_test_IntList;

typedef struct rig_schema_test_Message {
   const char *text;
   int len;
} rig_schema_test_Message;
]]

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

test.case("schema instance_of accepts subclass instances", function()
   local Base = rig.Class()
   local Child = rig.Class(Base)
   local value = Child()

   local decoded = schema.assert(
      schema.instance_of(Base, "a Base instance"),
      value,
      "thing"
   )
   test.equal(decoded, value)

   local ok, err = schema.check(schema.instance_of(Base, "a Base instance"), {}, "thing")
   test.falsey(ok)
   test.match(err, "thing expects a Base instance")
end)

test.case("schema.ffi.struct populates simple and nested structs", function()
   local point_schema = schema.ffi.struct("rig_schema_test_Point", {
      x = schema.integer({
         coerce = true,
      }),
      y = schema.integer({
         coerce = true,
      }),
   })
   local line_schema = schema.ffi.struct("rig_schema_test_Line", {
      start = point_schema,
      ["end"] = {
         schema = point_schema,
         to = "finish",
      },
   })

   local line = schema.assert(line_schema, {
      start = {
         x = "1",
         y = "2",
      },
      ["end"] = {
         x = "3",
         y = "4",
      },
   }, "line")

   test.equal(line.value.start.x, 1)
   test.equal(line.value.start.y, 2)
   test.equal(line.value.finish.x, 3)
   test.equal(line.value.finish.y, 4)
   test.equal(#line.keepalive, 2)
end)

test.case("schema.ffi.array and count_field populate pointer fields", function()
   local int_array_schema = schema.ffi.array("int", schema.integer({
      coerce = true,
   }))
   local list_schema = schema.ffi.struct("rig_schema_test_IntList", {
      values = {
         schema = int_array_schema,
         count_field = "count",
      },
   })

   local list = schema.assert(list_schema, {
      values = { "4", "5", "6" },
   }, "list")

   test.equal(list.value.count, 3)
   test.equal(list.value.values[0], 4)
   test.equal(list.value.values[1], 5)
   test.equal(list.value.values[2], 6)
   test.equal(#list.keepalive, 1)
end)

test.case("schema.ffi.struct supports custom assign hooks", function()
   local message_schema = schema.ffi.struct("rig_schema_test_Message", {
      text = {
         schema = schema.non_empty_string(),
         assign = function(dst, value, bundle)
            local buffer = ffi.new("char[?]", #value + 1)
            ffi.copy(buffer, value)
            dst.text = buffer
            dst.len = #value
            bundle:retain(buffer)
         end,
      },
   })

   local message = schema.assert(message_schema, {
      text = "hello",
   }, "message")

   test.equal(ffi.string(message.value.text), "hello")
   test.equal(message.value.len, 5)
   test.equal(#message.keepalive, 1)
end)
