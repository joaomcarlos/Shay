local handler = require("__core__.lualib.event_handler")
local layer = require("lib.layer")

handler.add_libraries
{
  require("lib.turrets"),
  layer,
  require("lib.ramp"),
  require("lib.stock")
}

remote.add_interface("shay", layer.remote)
