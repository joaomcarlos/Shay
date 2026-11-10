local handler = require("__core__.lualib.event_handler")

handler.add_libraries
{
  require("lib.turrets"),
  require("lib.layer"),
  require("lib.ramp")
}
