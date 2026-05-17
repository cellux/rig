local test = require("test")
local dl = require("dl")

test.case("dl can resolve a known exported symbol", function()
   local handle, open_err = dl.open(nil)
   test.truthy(handle ~= nil, open_err)

   local symbol, sym_err = dl.sym(handle, "rig_dl_open")
   test.truthy(symbol ~= nil, sym_err)

   local ok, close_err = dl.close(handle)
   test.truthy(ok == true, close_err)
end)
